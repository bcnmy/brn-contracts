// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import {SafeCast} from "openzeppelin-contracts/utils/math/SafeCast.sol";

import {ITATransactionAllocation} from "./interfaces/ITATransactionAllocation.sol";
import {TATransactionAllocationGetters} from "./TATransactionAllocationGetters.sol";
import {TAHelpers} from "ta-common/TAHelpers.sol";
import {U32ArrayHelper} from "src/library/arrays/U32ArrayHelper.sol";
import {U16ArrayHelper} from "src/library/arrays/U16ArrayHelper.sol";
import {RAArrayHelper} from "src/library/arrays/RAArrayHelper.sol";
import {
    FixedPointTypeHelper,
    FixedPointType,
    Uint256WrapperHelper,
    FP_ZERO,
    FP_ONE
} from "src/library/FixedPointArithmetic.sol";
import {VersionManager} from "src/library/VersionManager.sol";
import {RelayerAddress, TokenAddress, RelayerAccountAddress, RelayerState, RelayerStatus} from "ta-common/TATypes.sol";
import {PERCENTAGE_MULTIPLIER} from "ta-common/TAConstants.sol";

/// @title TATransactionAllocation
/// @dev This contract is responsible for allocating transactions to relayers and their execution.
///      A window is defined as a contigous set of blocks. The window size is defined by blocksPerWindow.
///      An epoch is defined as a period of time in which liveness is measured. The epoch length is defined by epochLengthInSec.
///
///      1. Transaction Allocation and Execution:
///      Each window, relayersPerWindow relayers are selected in a pseudo-random manner to submit transactions.
///      The execute function verifies that the calling relayer is selected in the current window, then executes the transactions.
///      Each transaction delegates to a transaction specific module, which verifies if that particular transaction was assigned to the relayer.
///
///      2. State Updation:
///      In the fist transaction of each epoch, the liveness of each relayer is verified.
///      Any relayers that fail the liveness check are penalized, and if their stake falls below a threshold, they are jailed.
///      Once the liveness check is complete, the pending state is scheduled for activation in the next window.
contract TATransactionAllocation is ITATransactionAllocation, TAHelpers, TATransactionAllocationGetters {
    using SafeCast for uint256;
    using FixedPointTypeHelper for FixedPointType;
    using Uint256WrapperHelper for uint256;
    using VersionManager for VersionManager.VersionManagerState;
    using U16ArrayHelper for uint16[];
    using U32ArrayHelper for uint32[];
    using RAArrayHelper for RelayerAddress[];

    ///////////////////////////////// Transaction Execution ///////////////////////////////

    /// @inheritdoc ITATransactionAllocation
    function execute(ExecuteParams calldata _params) external payable noSelfCall {
        uint256 length = _params.reqs.length;
        if (length != _params.forwardedNativeAmounts.length) {
            revert ParameterLengthMismatch();
        }

        _verifySufficientValueAttached(_params.forwardedNativeAmounts);

        // Verify Relayer Selection
        uint256 selectionCount = _verifyRelayerSelection(
            msg.sender,
            _params.activeState,
            _params.relayerIndex,
            _params.relayerGenerationIterationBitmap,
            block.number
        );

        TAStorage storage ts = getTAStorage();
        RelayerAddress relayerAddress = _params.activeState.relayers[_params.relayerIndex];

        // Ensure the relayer can call execute() once per window
        {
            uint256 windowId = _windowIndex(block.number);
            if (ts.lastTransactionSubmissionWindow[relayerAddress] == windowId) {
                revert RelayerAlreadySubmittedTransaction(relayerAddress, windowId);
            }
            ts.lastTransactionSubmissionWindow[relayerAddress] = windowId;
        }

        // Execute Transactions
        _executeTransactions(
            _params.reqs,
            _params.forwardedNativeAmounts,
            getRMStorage().relayersPerWindow,
            relayerAddress,
            _params.relayerGenerationIterationBitmap
        );

        uint256 epochEndTimestamp_ = ts.epochEndTimestamp;

        if (block.timestamp >= epochEndTimestamp_) {
            // Run liveness checks for last epoch
            _processLivenessCheck(_params.activeState, _params.latestState, _params.activeStateToLatestStateMap);

            // Process any pending Updates
            uint256 updateWindowIndex = _nextWindowForUpdate(block.number);
            getRMStorage().relayerStateVersionManager.setLatestStateForActivation(updateWindowIndex);

            // Update the epoch end time
            epochEndTimestamp_ = block.timestamp + ts.epochLengthInSec;
            ts.epochEndTimestamp = epochEndTimestamp_;
            emit EpochEndTimestampUpdated(epochEndTimestamp_);
        }

        // Record Liveness Metrics
        if (_params.reqs.length != 0) {
            unchecked {
                ts.transactionsSubmitted[epochEndTimestamp_][relayerAddress] += selectionCount;
                ts.totalTransactionsSubmitted[epochEndTimestamp_] += selectionCount;
            }
        }

        // TODO: Check how to update this logic
        // Validate that the relayer has sent enough gas for the call.
        // if (gasleft() <= totalGas / 63) {
        //     assembly {
        //         invalid()
        //     }
        // }
    }

    /// @dev Verifies that the relayer has been selected for the current window.
    /// @param _relayer The relayer address.
    /// @param _activeState The active realyer state, against which the relayer selection is verified.
    /// @param _relayerIndex The index of the relayer in the active state.
    /// @param _relayerGenerationIterationBitmap The bitmap of relayer generation iterations for which the relayer has been selected.
    /// @param _blockNumber The block number at which the verification logic needs to be run.
    function _verifyRelayerSelection(
        address _relayer,
        RelayerState calldata _activeState,
        uint256 _relayerIndex,
        uint256 _relayerGenerationIterationBitmap,
        uint256 _blockNumber
    ) internal view returns (uint256 selectionCount) {
        _verifyExternalStateForTransactionAllocation(
            _activeState.cdf.cd_hash(), _activeState.relayers.cd_hash(), _blockNumber
        );

        RMStorage storage ds = getRMStorage();

        {
            // If the ith bit of _relayerGenerationIterationBitmap is set, then the relayer has been selected as the ith relayer
            // where 0 <= i < relayersPerWindow.
            // This also means that the relayer is allowed to submit all transactions which satisfy the following condition:
            //   hash(txn) % relayersPerWindow == i

            // Verify Each Iteration against _cdfIndex in _cdf
            uint16 maxCdfElement = _activeState.cdf[_activeState.cdf.length - 1];
            uint256 relayerGenerationIteration;
            uint256 relayersPerWindow = ds.relayersPerWindow;

            while (_relayerGenerationIterationBitmap != 0) {
                if (_relayerGenerationIterationBitmap & 1 == 1) {
                    if (relayerGenerationIteration >= relayersPerWindow) {
                        revert InvalidRelayerGenerationIteration();
                    }

                    // Verify if correct stake prefix sum index has been provided
                    uint16 randomRelayerStake =
                        _randomNumberForCdfSelection(_blockNumber, relayerGenerationIteration, maxCdfElement);

                    if (
                        !(
                            (_relayerIndex == 0 || _activeState.cdf[_relayerIndex - 1] < randomRelayerStake)
                                && randomRelayerStake <= _activeState.cdf[_relayerIndex]
                        )
                    ) {
                        // The supplied index does not point to the correct interval
                        revert RelayerIndexDoesNotPointToSelectedCdfInterval();
                    }

                    selectionCount++;
                }

                unchecked {
                    ++relayerGenerationIteration;
                    _relayerGenerationIterationBitmap >>= 1;
                }
            }
        }

        RelayerAddress relayerAddress = _activeState.relayers[_relayerIndex];
        RelayerInfo storage node = ds.relayerInfo[relayerAddress];

        if (relayerAddress != RelayerAddress.wrap(_relayer) && !node.isAccount[RelayerAccountAddress.wrap(_relayer)]) {
            revert RelayerAddressDoesNotMatchSelectedRelayer();
        }
    }

    /// @dev Generates a pseudo random number used for selecting a relayer.
    /// @param _blockNumber The block number at which the random number needs to be generated.
    /// @param _iter The ith iteration corresponds to the ith relayer being generated
    /// @param _max The modulo value for the random number generation.
    function _randomNumberForCdfSelection(uint256 _blockNumber, uint256 _iter, uint16 _max)
        internal
        view
        returns (uint16)
    {
        // The seed for jth iteration is a function of the base seed and j
        uint256 baseSeed = uint256(keccak256(abi.encodePacked(_windowIndex(_blockNumber))));
        uint256 seed = uint256(keccak256(abi.encodePacked(baseSeed, _iter)));
        return (seed % _max + 1).toUint16();
    }

    /// @dev Executes the transactions, appending necessary data to the calldata for each.
    /// @param _reqs The array of transactions to execute.
    /// @param _forwardedNativeAmounts The array of forwarded native amounts for each transaction.
    /// @param _relayerCount The number of relayers that have been selected for the current window.
    /// @param _relayerAddress The address of the relayer that has been selected for the current window.
    /// @param _relayerGenerationIterationBitmap The bitmap of relayer generation iterations for which the relayer has been selected.
    function _executeTransactions(
        bytes[] calldata _reqs,
        uint256[] calldata _forwardedNativeAmounts,
        uint256 _relayerCount,
        RelayerAddress _relayerAddress,
        uint256 _relayerGenerationIterationBitmap
    ) internal {
        uint256 length = _reqs.length;

        for (uint256 i; i != length;) {
            (bool success, bytes memory returndata) = _executeTransaction(
                _reqs[i], _forwardedNativeAmounts[i], _relayerGenerationIterationBitmap, _relayerCount, _relayerAddress
            );

            emit TransactionStatus(i, success, returndata);

            if (!success) {
                revert TransactionExecutionFailed(i, returndata);
            }

            unchecked {
                ++i;
            }
        }
    }

    /// @dev Executes a single transaction, appending necessary data to the calldata .
    /// @param _req The transactions to execute.
    /// @param _value The native amount to forward to the transaction.
    /// @param _relayerGenerationIterationBitmap The bitmap of relayer generation iterations for which the relayer has been selected.
    /// @param _relayerCount The number of relayers that have been selected for the current window.
    /// @param _relayerAddress The address of the relayer that has been selected for the current window.
    /// @return status The status of the transaction.
    /// @return returndata The return data of the transaction.
    function _executeTransaction(
        bytes calldata _req,
        uint256 _value,
        uint256 _relayerGenerationIterationBitmap,
        uint256 _relayerCount,
        RelayerAddress _relayerAddress
    ) internal returns (bool status, bytes memory returndata) {
        (status, returndata) = address(this).call{value: _value}(
            abi.encodePacked(
                _req, _relayerGenerationIterationBitmap, _relayerCount, RelayerAddress.unwrap(_relayerAddress)
            )
        );
    }

    /// @dev Verifies that sum(_forwardedNativeAmounts) == msg.value
    /// @param _forwardedNativeAmounts The array of forwarded native amounts for each transaction.
    function _verifySufficientValueAttached(uint256[] calldata _forwardedNativeAmounts) internal view {
        uint256 totalExpectedValue;
        uint256 length = _forwardedNativeAmounts.length;
        for (uint256 i; i != length;) {
            totalExpectedValue += _forwardedNativeAmounts[i];
            unchecked {
                ++i;
            }
        }
        if (msg.value != totalExpectedValue) {
            revert InvalidFeeAttached(totalExpectedValue, msg.value);
        }
    }

    /////////////////////////////// Allocation Helpers ///////////////////////////////

    /// @inheritdoc ITATransactionAllocation
    function allocateRelayers(RelayerState calldata _activeState)
        external
        view
        override
        returns (RelayerAddress[] memory selectedRelayers, uint256[] memory cdfIndex)
    {
        _verifyExternalStateForTransactionAllocation(
            _activeState.cdf.cd_hash(), _activeState.relayers.cd_hash(), block.number
        );

        if (_activeState.cdf.length == 0) {
            revert NoRelayersRegistered();
        }

        if (_activeState.cdf[_activeState.cdf.length - 1] == 0) {
            revert NoRelayersRegistered();
        }

        {
            RMStorage storage ds = getRMStorage();
            selectedRelayers = new RelayerAddress[](ds.relayersPerWindow);
            cdfIndex = new uint256[](ds.relayersPerWindow);
        }

        uint256 relayersPerWindow = getRMStorage().relayersPerWindow;
        uint256 relayerCount = _activeState.relayers.length;

        for (uint256 i = 0; i != relayersPerWindow;) {
            uint16 randomCdfNumber = _randomNumberForCdfSelection(block.number, i, _activeState.cdf[relayerCount - 1]);
            cdfIndex[i] = _activeState.cdf.cd_lowerBound(randomCdfNumber);
            selectedRelayers[i] = _activeState.relayers[cdfIndex[i]];
            unchecked {
                ++i;
            }
        }
        return (selectedRelayers, cdfIndex);
    }

    ///////////////////////////////// Liveness ///////////////////////////////
    struct ProcessLivenessCheckMemoryState {
        // Cache to prevent multiple SLOADs
        uint256 epochEndTimestamp;
        uint256 updatedUnpaidProtocolRewards;
        uint256 stakeThresholdForJailing;
        uint256 totalTransactionsInEpoch;
        FixedPointType zScoreSquared;
        FixedPointType updatedSharePrice;
        // Intermediate state, written to storage at the end of the function
        uint256 activeRelayersJailedCount;
        uint256 totalPenalty;
        uint256 totalActiveRelayerPenalty;
        uint256 totalActiveRelayerJailedStake;
        FixedPointType totalProtocolRewardSharesBurnt;
        uint256 totalProtocolRewardsPaid;
        RelayerAddress[] newRelayerList;
    }

    /// @dev Processes the liveness check for the current epoch for all active relayers.
    /// @param _activeRelayerState The active relayer state.
    /// @param _pendingRelayerState The pending relayer state.
    /// @param _activeStateToLatestStateMap The map of active state index to latest state index.
    function _processLivenessCheck(
        RelayerState calldata _activeRelayerState,
        RelayerState calldata _pendingRelayerState,
        uint256[] calldata _activeStateToLatestStateMap
    ) internal {
        ProcessLivenessCheckMemoryState memory state;

        TAStorage storage ta = getTAStorage();
        state.epochEndTimestamp = ta.epochEndTimestamp;
        state.totalTransactionsInEpoch = ta.totalTransactionsSubmitted[state.epochEndTimestamp];
        state.zScoreSquared = ta.livenessZParameter;
        state.zScoreSquared = state.zScoreSquared * state.zScoreSquared;
        state.stakeThresholdForJailing = ta.stakeThresholdForJailing;
        delete ta.totalTransactionsSubmitted[state.epochEndTimestamp];

        // If no transactions were submitted in the epoch, then no need to process liveness check
        if (state.totalTransactionsInEpoch == 0) {
            emit NoTransactionsSubmittedInEpoch();
            return;
        }

        uint256 activeRelayerCount = _activeRelayerState.relayers.length;
        for (uint256 i; i != activeRelayerCount;) {
            _processLivenessCheckForRelayer(
                _activeRelayerState, _pendingRelayerState, _activeStateToLatestStateMap, i, state
            );

            unchecked {
                ++i;
            }
        }

        _postLivenessCheck(_pendingRelayerState, state);

        emit LivenessCheckProcessed(state.epochEndTimestamp);
    }

    /// @dev Processes the liveness check for the current epoch for a single relayer.
    /// @param _activeRelayerState The active relayer state.
    /// @param _pendingRelayerState Teh pending relayer state.
    /// @param _activeStateToLatestStateMap The map of active state index to latest state index.
    /// @param _relayerIndex The index of the relayer to process.
    /// @param _state In memory struct to store intermediate state.
    function _processLivenessCheckForRelayer(
        RelayerState calldata _activeRelayerState,
        RelayerState calldata _pendingRelayerState,
        uint256[] calldata _activeStateToLatestStateMap,
        uint256 _relayerIndex,
        ProcessLivenessCheckMemoryState memory _state
    ) internal {
        if (
            _verifyRelayerLiveness(
                _activeRelayerState,
                _relayerIndex,
                _state.epochEndTimestamp,
                _state.totalTransactionsInEpoch,
                _state.zScoreSquared
            )
        ) {
            return;
        }

        RelayerAddress relayerAddress = _activeRelayerState.relayers[_relayerIndex];
        RelayerInfo storage relayerInfo = getRMStorage().relayerInfo[relayerAddress];
        uint256 stake = relayerInfo.stake;
        uint256 penalty = _calculatePenalty(stake);

        // Initialize protocol reward state cache if not already done
        // TODO: Test this thoroughly
        if (_state.updatedSharePrice == FP_ZERO) {
            _state.updatedUnpaidProtocolRewards = _getLatestTotalUnpaidProtocolRewardsAndUpdateUpdatedTimestamp();
            _state.updatedSharePrice = _protocolRewardRelayerSharePrice(_state.updatedUnpaidProtocolRewards);
        }

        if (stake - penalty >= _state.stakeThresholdForJailing) {
            _penalizeRelayer(relayerAddress, relayerInfo, stake, penalty, _state);
        } else {
            _penalizeAndJailRelayer(
                _pendingRelayerState,
                _activeStateToLatestStateMap,
                relayerAddress,
                relayerInfo,
                stake,
                _relayerIndex,
                penalty,
                _state
            );
        }
    }

    /// @dev Assuming that the relayer failed the liveness check AND does not qualify for jailing, only penalize it's stake
    /// @param _relayerAddress The address of the relayer to penalize.
    /// @param _relayerInfo The relayer info of the relayer to penalize.
    /// @param _stake The current stake of the relayer.
    /// @param _penalty The penalty to be deducted from the relayer's stake.
    /// @param _state In memory struct to store intermediate state.
    function _penalizeRelayer(
        RelayerAddress _relayerAddress,
        RelayerInfo storage _relayerInfo,
        uint256 _stake,
        uint256 _penalty,
        ProcessLivenessCheckMemoryState memory _state
    ) internal {
        RelayerStatus statusBeforeLivenessCheck = _relayerInfo.status;

        // Penalize the relayer
        uint256 updatedStake = _stake - _penalty;
        _relayerInfo.stake = updatedStake;

        // The amount to be transferred to the recipients of the penalty (msg.sender, foundation, dao, governance...)
        _state.totalPenalty += _penalty;

        // If the relayer was an active relayer, decrease it's protocol reward shares accordingly
        if (statusBeforeLivenessCheck == RelayerStatus.Active) {
            // The penalty to be deducted from global totalStake in _postLivenessCheck
            _state.totalActiveRelayerPenalty += _penalty;

            // No need to process pending rewards since the relayer is still in the system, and pending rewards
            // don't change when shares equivalent to penalty are burnt
            FixedPointType protocolRewardSharesBurnt = _penalty.fp() / _state.updatedSharePrice;
            _relayerInfo.rewardShares = _relayerInfo.rewardShares - protocolRewardSharesBurnt;

            _state.totalProtocolRewardSharesBurnt = _state.totalProtocolRewardSharesBurnt + protocolRewardSharesBurnt;
        }

        // TODO: Emit shares burnt
        emit RelayerPenalized(_relayerAddress, updatedStake, _penalty);
    }

    /// @dev Assuming that the relayer failed the liveness check AND qualifies for jailing, penalize it's stake and jail it.
    ///      Process any pending rewards and then destroy all of the relayer's protocol reward shares, to prevent it from earning
    ///      any more rewards.
    /// @param _pendingRelayerState The pending relayer state. The relayer needs to be removed from this state.
    /// @param _activeStateToLatestStateMap The map of active state index to latest state index.
    /// @param _relayerAddress The address of the relayer to jail.
    /// @param _relayerInfo The relayer info of the relayer to jail.
    /// @param _stake The current stake of the relayer.
    /// @param _relayerIndex The index of the relayer to jail.
    /// @param _penalty The penalty to be deducted from the relayer's stake.
    /// @param _state In memory struct to store intermediate state.
    function _penalizeAndJailRelayer(
        RelayerState calldata _pendingRelayerState,
        uint256[] calldata _activeStateToLatestStateMap,
        RelayerAddress _relayerAddress,
        RelayerInfo storage _relayerInfo,
        uint256 _stake,
        uint256 _relayerIndex,
        uint256 _penalty,
        ProcessLivenessCheckMemoryState memory _state
    ) internal {
        RMStorage storage rms = getRMStorage();
        RelayerStatus statusBeforeLivenessCheck = _relayerInfo.status;

        // If the relayer was an active relayer, process any pending protocol rewards, then destory all of it's shares
        if (statusBeforeLivenessCheck == RelayerStatus.Active) {
            // Calculate Rewards
            (uint256 relayerRewards, uint256 delegatorRewards,) =
                _getPendingProtocolRewardsData(_relayerAddress, _state.updatedUnpaidProtocolRewards);
            _relayerInfo.unpaidProtocolRewards += relayerRewards;

            // Process Delegator Rewards
            _addDelegatorRewards(_relayerAddress, TokenAddress.wrap(address(rms.bondToken)), delegatorRewards);

            FixedPointType protocolRewardSharesBurnt = _relayerInfo.rewardShares;
            _relayerInfo.rewardShares = FP_ZERO;

            _state.totalProtocolRewardSharesBurnt = _state.totalProtocolRewardSharesBurnt + protocolRewardSharesBurnt;
            _state.totalProtocolRewardsPaid += relayerRewards + delegatorRewards;
        }

        // Penalize the relayer
        uint256 updatedStake = _stake - _penalty;
        _relayerInfo.stake = updatedStake;

        // Jail the relayer
        uint256 jailedUntilTimestamp = block.timestamp + rms.jailTimeInSec;
        _relayerInfo.status = RelayerStatus.Jailed;
        _relayerInfo.minExitTimestamp = jailedUntilTimestamp;

        // The amount to be transferred to the recipients of the penalty (msg.sender, foundation, dao, governance...)
        _state.totalPenalty += _penalty;

        // Update accumulators for _postLivenessCheck
        if (statusBeforeLivenessCheck == RelayerStatus.Active) {
            // The penalty to be deducted from global totalStake in _postLivenessCheck
            _state.totalActiveRelayerPenalty += _penalty;

            // The jailed stake to be deducted from global totalStake
            _state.totalActiveRelayerJailedStake += updatedStake;

            // Initialize jailedRelayers array if it is not initialized
            if (_state.activeRelayersJailedCount == 0) {
                _state.newRelayerList = _pendingRelayerState.relayers;
            }

            _removeRelayerFromRelayerList(
                _state.newRelayerList, _relayerAddress, _activeStateToLatestStateMap[_relayerIndex]
            );
            unchecked {
                ++_state.activeRelayersJailedCount;
            }
        }

        emit RelayerPenalized(_relayerAddress, updatedStake, _penalty);
        emit RelayerJailed(_relayerAddress, jailedUntilTimestamp);
    }

    /// @dev Writes the update state to storage after liveness check has been performed.
    /// @param _latestState The latest relayer state.
    /// @param _state The in memory struct to store intermediate state.
    function _postLivenessCheck(RelayerState calldata _latestState, ProcessLivenessCheckMemoryState memory _state)
        internal
    {
        RMStorage storage rms = getRMStorage();

        // Update Global Counters
        if (_state.totalActiveRelayerPenalty + _state.totalActiveRelayerJailedStake != 0) {
            rms.totalStake -= _state.totalActiveRelayerPenalty + _state.totalActiveRelayerJailedStake;
        }
        if (_state.activeRelayersJailedCount != 0) {
            rms.relayerCount -= _state.activeRelayersJailedCount;
        }
        if (_state.totalProtocolRewardSharesBurnt != FP_ZERO) {
            rms.totalProtocolRewardShares = rms.totalProtocolRewardShares - _state.totalProtocolRewardSharesBurnt;
        }

        uint256 newUnpaidRewards = _state.updatedUnpaidProtocolRewards - _state.totalProtocolRewardsPaid;
        if (newUnpaidRewards > 0 && newUnpaidRewards != rms.totalUnpaidProtocolRewards) {
            rms.totalUnpaidProtocolRewards = newUnpaidRewards;
        }

        // Schedule CDF Update if Necessary
        if (_state.totalActiveRelayerPenalty != 0 || _state.activeRelayersJailedCount != 0) {
            _verifyExternalStateForRelayerStateUpdation(_latestState.cdf.cd_hash(), _latestState.relayers.cd_hash());
            if (_state.activeRelayersJailedCount == 0) {
                _updateCdf_c(_latestState.relayers);
            } else {
                _updateCdf_m(_state.newRelayerList);
            }
        }

        // Transfer the penalty to the caller
        if (_state.totalPenalty != 0) {
            _transfer(TokenAddress.wrap(address(rms.bondToken)), msg.sender, _state.totalPenalty);
        }
    }

    /// @dev Utillity function to remove a relayer from a relayer list.
    /// @param _relayerList The relayer list.
    /// @param _expectedRelayerAddress The address of the relayer to be removed.
    /// @param _relayerIndex The index of the relayer in the relayer list.
    function _removeRelayerFromRelayerList(
        RelayerAddress[] memory _relayerList,
        RelayerAddress _expectedRelayerAddress,
        uint256 _relayerIndex
    ) internal pure {
        if (_relayerList[_relayerIndex] != _expectedRelayerAddress) {
            revert RelayerAddressMismatch(_relayerList[_relayerIndex], _expectedRelayerAddress);
        }
        _relayerList.m_remove(_relayerIndex);
    }

    /// @inheritdoc ITATransactionAllocation
    function calculateMinimumTranasctionsForLiveness(
        uint256 _relayerStake,
        uint256 _totalStake,
        uint256 _totalTransactions,
        FixedPointType _zScore
    ) external pure override returns (FixedPointType) {
        // The condition for liveness is:
        //   Probability (p) = _relayerStake / _totalStake
        //   Standard Deviation (s) = √(p * (1 - p) * _totalTransactions)
        //   Expected Number of Transactions (e) = p * _totalTransactions
        //   Minimum Number of Transactions = Max(e - z * s, 0)

        if (_totalTransactions == 0) {
            return FP_ZERO;
        }

        if (_totalStake == 0) {
            revert NoRelayersRegistered();
        }

        FixedPointType p = _relayerStake.fp().div(_totalStake);
        FixedPointType s = ((p * (FP_ONE - p)) * _totalTransactions.fp()).sqrt();
        FixedPointType d = _zScore * s;
        FixedPointType e = p * _totalTransactions.fp();
        unchecked {
            if (e > d) {
                return e - d;
            }
        }

        return FP_ZERO;
    }

    /// @dev Returns true if the relayer passes the liveness check for the current epoch, else false.
    /// @param _activeState The active relayer state.
    /// @param _relayerIndex The index of the relayer in the active relayer list.
    /// @param _epochEndTimestamp The end timestamp of the current epoch.
    /// @param _totalTransactionsInEpoch  The total number of transactions in the current epoch.
    /// @param _zScoreSquared A precomputed zScore parameter squared value.
    /// @return True if the relayer passes the liveness check for the current epoch, else false.
    function _verifyRelayerLiveness(
        RelayerState calldata _activeState,
        uint256 _relayerIndex,
        uint256 _epochEndTimestamp,
        uint256 _totalTransactionsInEpoch,
        FixedPointType _zScoreSquared
    ) internal returns (bool) {
        TAStorage storage ts = getTAStorage();

        RelayerAddress relayerAddress = _activeState.relayers[_relayerIndex];
        uint256 transactionsProcessedByRelayer = ts.transactionsSubmitted[_epochEndTimestamp][relayerAddress];
        delete ts.transactionsSubmitted[_epochEndTimestamp][relayerAddress];

        uint256 relayerStakeNormalized = _activeState.cdf[_relayerIndex];

        if (_relayerIndex != 0) {
            relayerStakeNormalized -= _activeState.cdf[_relayerIndex - 1];
        }

        return _checkRelayerLiveness(
            relayerStakeNormalized,
            _activeState.cdf[_activeState.cdf.length - 1],
            transactionsProcessedByRelayer,
            _totalTransactionsInEpoch,
            _zScoreSquared
        );
    }

    /// @dev An optimized version of verifying whether _transactionsDoneByRelayer >= calculatedMinimumTranasctionsForLiveness()
    /// @param _relayerStake The stake of the relayer.
    /// @param _totalStake The total stake of all relayers.
    /// @param _tranasctionsDoneByRelayer The number of transactions done by the relayer.
    /// @param _totalTransactions The total number of transactions done by all relayers.
    /// @param _zScoreSquared The zScore parameter squared value.
    /// @return True if the relayer passes the liveness check for the current epoch, else false.
    function _checkRelayerLiveness(
        uint256 _relayerStake,
        uint256 _totalStake,
        uint256 _tranasctionsDoneByRelayer,
        uint256 _totalTransactions,
        FixedPointType _zScoreSquared
    ) internal pure returns (bool) {
        // Calculating square roots is expensive, so we modfiy the inequality to avoid it.
        //
        // Let t = _tranasctionsDoneByRelayer, T = _totalTransactions, p = _relayerStake / _totalStake
        // The original condition is:
        //   Expected Number of Transactions (e) = pT
        //   Standard Deviation (s) = √(p(1 - p)T) = √((1-p)e)
        //   Minimum Number of Transactions = e - z * s = e - z√((1-p)e)
        //   Therefore, t >= e - z√((1-p)e)
        //           or  z√((1-p)e) >= e - t

        // Optimized condition:
        // We skip the check if e - t <= 0
        FixedPointType p = _relayerStake.fp().div(_totalStake);
        FixedPointType e = p.mul(_totalTransactions);
        FixedPointType _tranasctionsDoneByRelayerFp = _tranasctionsDoneByRelayer.fp();
        if (e <= _tranasctionsDoneByRelayerFp) {
            return true;
        }

        // Square both sides of the inequality to avoid calculating the square root
        // z^2 * (1-p)e >= (e - t)^2
        FixedPointType lhs = _zScoreSquared * e * (FP_ONE - p);
        FixedPointType rhs = e - _tranasctionsDoneByRelayerFp;
        rhs = rhs * rhs;

        return lhs >= rhs;
    }

    /// @dev Helper function to calculate the penalty for a relayer.
    /// @param _stake The stake of the relayer.
    /// @return The penalty for the relayer.
    function _calculatePenalty(uint256 _stake) internal view returns (uint256) {
        return (_stake * getRMStorage().absencePenaltyPercentage) / (100 * PERCENTAGE_MULTIPLIER);
    }
}
