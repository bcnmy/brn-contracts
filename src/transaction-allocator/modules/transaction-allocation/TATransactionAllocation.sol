// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import "./interfaces/ITATransactionAllocation.sol";
import "./TATransactionAllocationStorage.sol";
import "ta-common/TAHelpers.sol";
import "src/library/arrays/U32ArrayHelper.sol";

contract TATransactionAllocation is ITATransactionAllocation, TAHelpers, TATransactionAllocationStorage {
    using SafeCast for uint256;
    using FixedPointTypeHelper for FixedPointType;
    using Uint256WrapperHelper for uint256;
    using VersionManager for VersionManager.VersionManagerState;
    using U16ArrayHelper for uint16[];
    using U32ArrayHelper for uint32[];
    using RAArrayHelper for RelayerAddress[];

    ///////////////////////////////// Transaction Execution ///////////////////////////////
    /// @notice allows relayer to execute a tx on behalf of a client
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
            // Verify Each Iteration against _cdfIndex in _cdf
            uint16 maxCdfElement = _activeState.cdf[_activeState.cdf.length - 1];
            uint256 relayerGenerationIteration;
            uint256 relayersPerWindow = ds.relayersPerWindow;

            // I wonder if an efficient implementation of __builtin_ctzl exists in solidity.
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

    /// @notice Given a block number, the function generates a list of pseudo-random relayers
    ///         for the window of which the block in a part of. The generated list of relayers
    ///         is pseudo-random but deterministic
    /// @return selectedRelayers list of relayers selected of length relayersPerWindow, but
    ///                          there can be duplicates
    /// @return cdfIndex list of indices of the selected relayers in the cdf, used for verification
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
        // Cache
        uint256 epochEndTimestamp;
        uint256 updatedUnpaidProtocolRewards;
        uint256 stakeThresholdForJailing;
        uint256 totalTransactionsInEpoch;
        FixedPointType zScoreSquared;
        FixedPointType updatedSharePrice;
        // State
        uint256 activeRelayersJailedCount;
        uint256 totalPenalty;
        uint256 totalActiveRelayerPenalty;
        uint256 totalActiveRelayerJailedStake;
        FixedPointType totalProtocolRewardSharesBurnt;
        uint256 totalProtocolRewardsPaid;
        RelayerAddress[] newRelayerList;
    }

    function _processLivenessCheck(
        RelayerState calldata _activeRelayerState,
        RelayerState calldata _pendingRelayerState,
        uint256[] calldata _activeStateToLatestStateMap
    ) internal {
        ProcessLivenessCheckMemoryState memory state;

        TAStorage storage ta = getTAStorage();
        state.epochEndTimestamp = ta.epochEndTimestamp;
        state.updatedUnpaidProtocolRewards = _getLatestTotalUnpaidProtocolRewardsAndUpdateUpdatedTimestamp();
        state.updatedSharePrice = _protocolRewardRelayerSharePrice(state.updatedUnpaidProtocolRewards);
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
        if (newUnpaidRewards != rms.totalUnpaidProtocolRewards) {
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

    function calculateMinimumTranasctionsForLiveness(
        uint256 _relayerStake,
        uint256 _totalStake,
        uint256 _totalTransactions,
        FixedPointType _zScore
    ) external pure override returns (FixedPointType) {
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

    function _checkRelayerLiveness(
        uint256 _relayerStake,
        uint256 _totalStake,
        uint256 _tranasctionsDoneByRelayer,
        uint256 _totalTransactions,
        FixedPointType _zScoreSquared
    ) internal pure returns (bool) {
        FixedPointType p = _relayerStake.fp().div(_totalStake);
        FixedPointType e = p.mul(_totalTransactions);
        FixedPointType _tranasctionsDoneByRelayerFp = _tranasctionsDoneByRelayer.fp();
        if (e <= _tranasctionsDoneByRelayerFp) {
            return true;
        }

        FixedPointType lhs = _zScoreSquared * e * (FP_ONE - p);
        FixedPointType rhs = e - _tranasctionsDoneByRelayerFp;
        rhs = rhs * rhs;

        return lhs >= rhs;
    }

    function _calculatePenalty(uint256 _stake) internal view returns (uint256) {
        return (_stake * getRMStorage().absencePenaltyPercentage) / (100 * PERCENTAGE_MULTIPLIER);
    }

    ///////////////////////////////// Getters ///////////////////////////////
    function transactionsSubmittedByRelayer(RelayerAddress _relayerAddress)
        external
        view
        override
        noSelfCall
        returns (uint256)
    {
        return getTAStorage().transactionsSubmitted[getTAStorage().epochEndTimestamp][_relayerAddress];
    }

    function totalTransactionsSubmitted() external view override noSelfCall returns (uint256) {
        return getTAStorage().totalTransactionsSubmitted[getTAStorage().epochEndTimestamp];
    }

    function epochLengthInSec() external view override noSelfCall returns (uint256) {
        return getTAStorage().epochLengthInSec;
    }

    function epochEndTimestamp() external view override noSelfCall returns (uint256) {
        return getTAStorage().epochEndTimestamp;
    }

    function livenessZParameter() external view override noSelfCall returns (FixedPointType) {
        return getTAStorage().livenessZParameter;
    }

    function stakeThresholdForJailing() external view override noSelfCall returns (uint256) {
        return getTAStorage().stakeThresholdForJailing;
    }
}
