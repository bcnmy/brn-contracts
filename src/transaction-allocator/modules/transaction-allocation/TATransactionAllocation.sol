// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import {ITATransactionAllocation} from "./interfaces/ITATransactionAllocation.sol";
import {TATransactionAllocationGetters} from "./TATransactionAllocationGetters.sol";
import {TAHelpers} from "ta-common/TAHelpers.sol";
import {U256ArrayHelper} from "src/library/arrays/U256ArrayHelper.sol";
import {RAArrayHelper} from "src/library/arrays/RAArrayHelper.sol";
import {
    FixedPointTypeHelper,
    FixedPointType,
    Uint256WrapperHelper,
    FP_ZERO,
    FP_ONE
} from "src/library/FixedPointArithmetic.sol";
import {VersionManager} from "src/library/VersionManager.sol";
import {RelayerAddress, TokenAddress, RelayerAccountAddress, RelayerStatus} from "ta-common/TATypes.sol";
import {RelayerStateManager} from "ta-common/RelayerStateManager.sol";
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
    using FixedPointTypeHelper for FixedPointType;
    using Uint256WrapperHelper for uint256;
    using VersionManager for VersionManager.VersionManagerState;
    using U256ArrayHelper for uint256[];
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

        // If the transaction is the first transaction of the epoch, then perform the liveness check and other operations
        if (block.timestamp >= epochEndTimestamp_) {
            epochEndTimestamp_ = _performFirstTransactionOfEpochDuties(_params.activeState, _params.latestState);
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

    /// @dev Runs the liveness check, activates any pending state and emits the latest relayer state.
    /// @param _activeState The active relayer state.
    /// @param _latestState The latest relayer state.
    function _performFirstTransactionOfEpochDuties(
        RelayerStateManager.RelayerState calldata _activeState,
        RelayerStateManager.RelayerState calldata _latestState
    ) internal returns (uint256) {
        _verifyExternalStateForRelayerStateUpdation(_latestState);

        // Run liveness checks for last epoch
        (
            bool isRelayerStateUpdatedDuringLivnessCheck,
            bytes32 newRelayerStateHash,
            RelayerStateManager.RelayerState memory newRelayerState
        ) = _processLivenessCheck(_activeState, _latestState);

        // Process any pending Updates
        uint256 updateWindowIndex = _nextWindowForUpdate(block.number);
        VersionManager.VersionManagerState storage vms = getRMStorage().relayerStateVersionManager;
        vms.setLatestStateForActivation(updateWindowIndex);

        // Emit the latest relayer state
        if (isRelayerStateUpdatedDuringLivnessCheck) {
            emit NewRelayerState(newRelayerStateHash, updateWindowIndex, newRelayerState);
        } else {
            emit NewRelayerState(vms.latestStateHash(), updateWindowIndex, _latestState);
        }

        // Update the epoch end time
        TAStorage storage ts = getTAStorage();
        uint256 newEpochEndTimestamp = block.timestamp + ts.epochLengthInSec;
        ts.epochEndTimestamp = newEpochEndTimestamp;
        emit EpochEndTimestampUpdated(newEpochEndTimestamp);

        return newEpochEndTimestamp;
    }

    /// @dev Verifies that the relayer has been selected for the current window.
    /// @param _relayer The relayer address.
    /// @param _activeState The active realyer state, against which the relayer selection is verified.
    /// @param _relayerIndex The index of the relayer in the active state.
    /// @param _relayerGenerationIterationBitmap The bitmap of relayer generation iterations for which the relayer has been selected.
    /// @param _blockNumber The block number at which the verification logic needs to be run.
    function _verifyRelayerSelection(
        address _relayer,
        RelayerStateManager.RelayerState calldata _activeState,
        uint256 _relayerIndex,
        uint256 _relayerGenerationIterationBitmap,
        uint256 _blockNumber
    ) internal view returns (uint256 selectionCount) {
        _verifyExternalStateForTransactionAllocation(_activeState, _blockNumber);

        RMStorage storage ds = getRMStorage();

        {
            // If the ith bit of _relayerGenerationIterationBitmap is set, then the relayer has been selected as the ith relayer
            // where 0 <= i < relayersPerWindow.
            // This also means that the relayer is allowed to submit all transactions which satisfy the following condition:
            //   hash(txn) % relayersPerWindow == i

            // Verify Each Iteration against _cdfIndex in _cdf
            uint256 maxCdfElement = _activeState.cdf[_activeState.cdf.length - 1];
            uint256 relayerGenerationIteration;
            uint256 relayersPerWindow = ds.relayersPerWindow;

            while (_relayerGenerationIterationBitmap != 0) {
                if (_relayerGenerationIterationBitmap & 1 == 1) {
                    if (relayerGenerationIteration >= relayersPerWindow) {
                        revert InvalidRelayerGenerationIteration();
                    }

                    // Verify if correct cdf index has been provided
                    uint256 r = _randomNumberForCdfSelection(_blockNumber, relayerGenerationIteration, maxCdfElement);

                    if (
                        !(
                            (_relayerIndex == 0 || _activeState.cdf[_relayerIndex - 1] < r)
                                && r <= _activeState.cdf[_relayerIndex]
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
    function _randomNumberForCdfSelection(uint256 _blockNumber, uint256 _iter, uint256 _max)
        internal
        view
        returns (uint256)
    {
        // The seed for jth iteration is a function of the base seed and j
        uint256 baseSeed = uint256(keccak256(abi.encodePacked(_windowIndex(_blockNumber))));
        uint256 seed = uint256(keccak256(abi.encodePacked(baseSeed, _iter)));
        return seed % _max + 1;
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
    function allocateRelayers(RelayerStateManager.RelayerState calldata _activeState)
        external
        view
        override
        returns (RelayerAddress[] memory selectedRelayers, uint256[] memory cdfIndex)
    {
        _verifyExternalStateForTransactionAllocation(_activeState, block.number);

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
            uint256 randomCdfNumber = _randomNumberForCdfSelection(block.number, i, _activeState.cdf[relayerCount - 1]);
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
        uint256[] newWeightsList; // The changes to weights (stake+delegation) are accumulated in this array
    }

    /// @dev Processes the liveness check for the current epoch for all active relayers.
    /// @param _activeRelayerState The active relayer state.
    /// @param _pendingRelayerState The pending relayer state.
    function _processLivenessCheck(
        RelayerStateManager.RelayerState calldata _activeRelayerState,
        RelayerStateManager.RelayerState calldata _pendingRelayerState
    )
        internal
        returns (
            bool isRelayerStateUpdated,
            bytes32 newRelayerStateHash,
            RelayerStateManager.RelayerState memory newRelayerState
        )
    {
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
            return (isRelayerStateUpdated, newRelayerStateHash, newRelayerState);
        }

        uint256 activeRelayerCount = _activeRelayerState.relayers.length;
        for (uint256 i; i != activeRelayerCount;) {
            _processLivenessCheckForRelayer(_activeRelayerState, _pendingRelayerState, i, state);

            unchecked {
                ++i;
            }
        }

        (isRelayerStateUpdated, newRelayerStateHash, newRelayerState) = _postLivenessCheck(state);

        emit LivenessCheckProcessed(state.epochEndTimestamp);
    }

    /// @dev Processes the liveness check for the current epoch for a single relayer.
    /// @param _activeRelayerState The active relayer state.
    /// @param _pendingRelayerState Teh pending relayer state.
    /// @param _relayerIndex The index of the relayer to process.
    /// @param _state In memory struct to store intermediate state.
    function _processLivenessCheckForRelayer(
        RelayerStateManager.RelayerState calldata _activeRelayerState,
        RelayerStateManager.RelayerState calldata _pendingRelayerState,
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
        if (_state.updatedSharePrice == FP_ZERO) {
            _state.updatedUnpaidProtocolRewards = _getLatestTotalUnpaidProtocolRewardsAndUpdateUpdatedTimestamp();
            _state.updatedSharePrice = _protocolRewardRelayerSharePrice(_state.updatedUnpaidProtocolRewards);
        }

        // Initialize the relayer lists if they are not initialized
        if (_state.newWeightsList.length == 0) {
            _state.newWeightsList = RelayerStateManager.cdfToWeights(_pendingRelayerState.cdf);
            _state.newRelayerList = _pendingRelayerState.relayers;
        }

        if (stake - penalty >= _state.stakeThresholdForJailing) {
            _penalizeRelayer(relayerAddress, relayerInfo, stake, penalty, _state);
        } else {
            _penalizeAndJailRelayer(relayerAddress, relayerInfo, stake, penalty, _state);
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

            _decreaseRelayerWeightInState(_state, _relayerAddress, _penalty);

            emit RelayerProtocolSharesBurnt(_relayerAddress, protocolRewardSharesBurnt);
        }

        emit RelayerPenalized(_relayerAddress, updatedStake, _penalty);
    }

    /// @dev Assuming that the relayer failed the liveness check AND qualifies for jailing, penalize it's stake and jail it.
    ///      Process any pending rewards and then destroy all of the relayer's protocol reward shares, to prevent it from earning
    ///      any more rewards.
    /// @param _relayerAddress The address of the relayer to jail.
    /// @param _relayerInfo The relayer info of the relayer to jail.
    /// @param _stake The current stake of the relayer.
    /// @param _penalty The penalty to be deducted from the relayer's stake.
    /// @param _state In memory struct to store intermediate state.
    function _penalizeAndJailRelayer(
        RelayerAddress _relayerAddress,
        RelayerInfo storage _relayerInfo,
        uint256 _stake,
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

            emit RelayerProtocolSharesBurnt(_relayerAddress, protocolRewardSharesBurnt);
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

            _removeRelayerFromState(_state, _relayerAddress);
            unchecked {
                ++_state.activeRelayersJailedCount;
            }
        }

        emit RelayerPenalized(_relayerAddress, updatedStake, _penalty);
        emit RelayerJailed(_relayerAddress, jailedUntilTimestamp);
    }

    /// @dev Writes the update state to storage after liveness check has been performed.
    /// @param _state The in memory struct to store intermediate state.
    /// @return isRelayerStateUpdated True if the relayer state has been updated, else false.
    /// @return newRelayerStateHash The hash of the new relayer state.
    /// @return newRelayerState The new relayer state.
    function _postLivenessCheck(ProcessLivenessCheckMemoryState memory _state)
        internal
        returns (
            bool isRelayerStateUpdated,
            bytes32 newRelayerStateHash,
            RelayerStateManager.RelayerState memory newRelayerState
        )
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

        // Schedule RelayerState Update if Necessary
        isRelayerStateUpdated = _state.totalActiveRelayerPenalty != 0 || _state.activeRelayersJailedCount != 0;
        if (isRelayerStateUpdated) {
            uint256[] memory newCdf = RelayerStateManager.weightsToCdf(_state.newWeightsList);
            newRelayerState = RelayerStateManager.RelayerState({relayers: _state.newRelayerList, cdf: newCdf});
            newRelayerStateHash = RelayerStateManager.hash(newCdf.m_hash(), _state.newRelayerList.m_hash());
            _updateLatestRelayerState(newRelayerStateHash);
        }

        // Transfer the penalty to the caller
        if (_state.totalPenalty != 0) {
            _transfer(TokenAddress.wrap(address(rms.bondToken)), msg.sender, _state.totalPenalty);
        }
    }

    /// @dev Utillity function to remove a relayer from the memory state.
    function _removeRelayerFromState(ProcessLivenessCheckMemoryState memory _state, RelayerAddress _relayerAddress)
        internal
        pure
    {
        uint256 relayerIndexInMemoryState = _findRelayerIndexInMemoryState(_state, _relayerAddress);
        _state.newRelayerList.m_remove(relayerIndexInMemoryState);
        _state.newWeightsList.m_remove(relayerIndexInMemoryState);
    }

    /// @dev Utillity function to decrease a relayer's weight from the memory state.
    function _decreaseRelayerWeightInState(
        ProcessLivenessCheckMemoryState memory _state,
        RelayerAddress _relayerAddress,
        uint256 _valueToDecrease
    ) internal pure {
        uint256 relayerIndexInMemoryState = _findRelayerIndexInMemoryState(_state, _relayerAddress);
        _state.newWeightsList[relayerIndexInMemoryState] -= _valueToDecrease;
    }

    /// @dev Utillity function to find a relayer's index in the memory state, in O(relayerCount).
    ///      This will be called rarely (once per epoch, AND once per relayer that is penalized or jailed)
    /// @param _state The in memory struct to store intermediate state.
    /// @param _relayerAddress The address of the relayer to find.
    function _findRelayerIndexInMemoryState(
        ProcessLivenessCheckMemoryState memory _state,
        RelayerAddress _relayerAddress
    ) internal pure returns (uint256) {
        uint256 length = _state.newRelayerList.length;
        for (uint256 i; i != length;) {
            if (_state.newRelayerList[i] == _relayerAddress) {
                return i;
            }
            unchecked {
                ++i;
            }
        }

        // It should not be possible to reach here
        revert RelayerAddressNotFoundInMemoryState(_relayerAddress);
    }

    /// @inheritdoc ITATransactionAllocation
    function calculateMinimumTranasctionsForLiveness(
        uint256 _relayerStake,
        uint256 _totalStake,
        uint256 _totalTransactions,
        FixedPointType _zScore
    ) external pure override returns (FixedPointType) {
        // Let t = _transactionsDoneByRelayer
        //     T = _totalTransactions
        //
        //                  _relayerStake
        // Probability: p = ─────────────
        //                   _totalStake
        //
        // Expected Number of Transactions: e = pT
        //
        //                          ┌─────────┐   ┌──────┐
        // Standard Deviation: s = ╲│p(1 - p)T = ╲│(1-p)e
        //                                                 ┌─────┐
        // Minimum Number of Transactions = e - zs = e - z╲│(1-p)e

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
        RelayerStateManager.RelayerState calldata _activeState,
        uint256 _relayerIndex,
        uint256 _epochEndTimestamp,
        uint256 _totalTransactionsInEpoch,
        FixedPointType _zScoreSquared
    ) internal returns (bool) {
        TAStorage storage ts = getTAStorage();

        RelayerAddress relayerAddress = _activeState.relayers[_relayerIndex];
        uint256 transactionsProcessedByRelayer = ts.transactionsSubmitted[_epochEndTimestamp][relayerAddress];
        delete ts.transactionsSubmitted[_epochEndTimestamp][relayerAddress];

        uint256 relayerWeight = _activeState.cdf[_relayerIndex];

        if (_relayerIndex != 0) {
            relayerWeight -= _activeState.cdf[_relayerIndex - 1];
        }

        return _checkRelayerLiveness(
            relayerWeight,
            _activeState.cdf[_activeState.cdf.length - 1],
            transactionsProcessedByRelayer,
            _totalTransactionsInEpoch,
            _zScoreSquared
        );
    }

    /// @dev An optimized version of verifying whether _transactionsDoneByRelayer >= calculatedMinimumTranasctionsForLiveness()
    /// @param _relayerStake The stake of the relayer.
    /// @param _totalStake The total stake of all relayers.
    /// @param _transactionsDoneByRelayer The number of transactions done by the relayer.
    /// @param _totalTransactions The total number of transactions done by all relayers.
    /// @param _zScoreSquared The zScore parameter squared value.
    /// @return True if the relayer passes the liveness check for the current epoch, else false.
    function _checkRelayerLiveness(
        uint256 _relayerStake,
        uint256 _totalStake,
        uint256 _transactionsDoneByRelayer,
        uint256 _totalTransactions,
        FixedPointType _zScoreSquared
    ) internal pure returns (bool) {
        // Calculating square roots is expensive, so we modify the inequality to avoid it.
        //
        // Let t = _transactionsDoneByRelayer
        //     T = _totalTransactions
        //
        //                  _relayerStake
        // Probability: p = ─────────────
        //                   _totalStake
        //
        // The original condition is:
        //
        // Expected Number of Transactions: e = pT
        //
        //                          ┌─────────┐   ┌──────┐
        // Standard Deviation: s = ╲│p(1 - p)T = ╲│(1-p)e
        //                                                 ┌─────┐
        // Minimum Number of Transactions = e - zs = e - z╲│(1-p)e
        //
        // Therefore,
        //              ┌──────┐
        // => t ≥ e - z╲│(1-p)e
        //
        //      ┌──────┐
        // => z╲│e(1-p)  ≥ e - t
        //
        // => e ≤ t ∨ z²e(1-p) ≥ (e-t)²

        // We skip the check if e ≤ t
        FixedPointType p = _relayerStake.fp().div(_totalStake);
        FixedPointType e = p.mul(_totalTransactions);
        FixedPointType _transactionsDoneByRelayerFp = _transactionsDoneByRelayer.fp();
        if (e <= _transactionsDoneByRelayerFp) {
            return true;
        }

        // Proceed with the check if e > t
        FixedPointType lhs = _zScoreSquared * e * (FP_ONE - p);
        FixedPointType rhs = e - _transactionsDoneByRelayerFp;
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
