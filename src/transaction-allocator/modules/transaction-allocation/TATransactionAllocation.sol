// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import "./interfaces/ITATransactionAllocation.sol";
import "./TATransactionAllocationStorage.sol";
import "ta-base-application/interfaces/IApplicationBase.sol";
import "ta-relayer-management/TARelayerManagementStorage.sol";
import "ta-common/TAHelpers.sol";
import "ta-common/TATypes.sol";

contract TATransactionAllocation is ITATransactionAllocation, TAHelpers, TATransactionAllocationStorage {
    using FixedPointTypeHelper for FixedPointType;
    using Uint256WrapperHelper for uint256;
    using VersionManager for VersionManager.VersionManagerState;
    using U16ArrayHelper for uint16[];
    using U32ArrayHelper for uint32[];
    using RAArrayHelper for RelayerAddress[];

    ///////////////////////////////// Transaction Execution ///////////////////////////////
    /// @notice allows relayer to execute a tx on behalf of a client
    // TODO: can we decrease calldata cost by using merkle proofs or square root decomposition?
    function execute(ExecuteParams calldata _params) public payable {
        uint256 length = _params.reqs.length;
        if (length != _params.forwardedNativeAmounts.length) {
            revert ParameterLengthMismatch();
        }

        _verifySufficientValueAttached(_params.forwardedNativeAmounts);

        // Verify Relayer Selection
        if (
            !_verifyRelayerSelection(
                msg.sender,
                _params.activeState,
                _params.relayerIndex,
                _params.relayerGenerationIterationBitmap,
                block.number
            )
        ) {
            revert InvalidRelayerWindow();
        }

        RelayerAddress relayerAddress = _params.activeState.relayers[_params.relayerIndex];

        // Execute Transactions
        _executeTransactions(
            _params.reqs,
            _params.forwardedNativeAmounts,
            _params.activeState.relayers.length,
            relayerAddress,
            _params.relayerGenerationIterationBitmap
        );

        // Run liveness checks for last epoch, if neeeded
        _processLivenessCheck(_params.activeState, _params.latestState, _params.activeStateToPendingStateMap);

        // Process any pending Updates
        uint256 updateWindowIndex = _nextWindowForUpdate(block.number);
        getRMStorage().relayerStateVersionManager.setPendingStateForActivation(updateWindowIndex);

        TAStorage storage ts = getTAStorage();

        // Update the epoch end time
        uint256 newEpochEndTimestamp = block.timestamp + ts.epochLengthInSec;
        ts.epochEndTimestamp = newEpochEndTimestamp;
        emit EpochEndTimestampUpdated(newEpochEndTimestamp);

        // Record Liveness Metrics
        unchecked {
            ++ts.transactionsSubmitted[newEpochEndTimestamp][relayerAddress];
            ++ts.totalTransactionsSubmitted[newEpochEndTimestamp];
        }

        // TODO: Check how to update this logic
        // Validate that the relayer has sent enough gas for the call.
        // if (gasleft() <= totalGas / 63) {
        //     assembly {
        //         invalid()
        //     }
        // }
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
                revert TransactionExecutionFailed(i);
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
            _activeState.cdf.cd_hash(), _activeState.relayers.m_hash(), block.number
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
    // TODO: Split the penalty b/w DAO and relayer
    // TODO: Jail the relayer, the relayer needs to topup or leave with their money

    struct ProcessLivenessCheckMemoryState {
        uint256 activeRelayersJailedCount;
        uint256 totalPenalty;
        RelayerAddress[] newRelayerList;
    }

    function _processLivenessCheck(
        RelayerState calldata _activeState,
        RelayerState calldata _pendingState,
        uint256[] calldata _activeStateToPendingStateMap
    ) internal {
        TAStorage storage ts = getTAStorage();
        RMStorage storage rms = getRMStorage();

        uint256 epochEndTimestamp_ = ts.epochEndTimestamp;

        if (epochEndTimestamp_ < block.timestamp) {
            emit LivenessCheckAlreadyProcessed();
            return;
        }

        FixedPointType totalTransactionsInEpoch = ts.totalTransactionsSubmitted[epochEndTimestamp_].fp();
        delete ts.totalTransactionsSubmitted[epochEndTimestamp_];

        // If no transactions were submitted in the epoch, then no need to process liveness check
        if (totalTransactionsInEpoch == FP_ZERO) {
            emit NoTransactionsSubmittedInEpoch();
            return;
        }

        // Save stuff to memory to help with stack too deep error
        ProcessLivenessCheckMemoryState memory state;

        uint256 activeRelayerCount = _activeState.relayers.length;
        for (uint256 i; i != activeRelayerCount;) {
            RelayerStatus statusBeforeLivenessCheck = rms.relayerInfo[_activeState.relayers[i]].status;

            (bool relayerWasJailed, uint256 penalty) =
                _processLivenessCheckForRelayer(_activeState, i, epochEndTimestamp_, totalTransactionsInEpoch);

            state.totalPenalty += penalty;

            // If the relayer was active and jailed, we need to remove it from the list of active relayers
            if (relayerWasJailed && statusBeforeLivenessCheck == RelayerStatus.Active) {
                // Initialize jailedRelayers array if it is not initialized
                if (state.activeRelayersJailedCount == 0) {
                    state.newRelayerList = _pendingState.relayers;
                }
                _removeRelayerFromRelayerList(
                    state.newRelayerList, _activeState.relayers[i], _activeStateToPendingStateMap[i]
                );
                unchecked {
                    ++state.activeRelayersJailedCount;
                }
            }

            unchecked {
                ++i;
            }
        }

        _postLivnessCheck(_pendingState, state.totalPenalty, state.activeRelayersJailedCount, state.newRelayerList);

        emit LivenessCheckProcessed(epochEndTimestamp_);
    }

    function _processLivenessCheckForRelayer(
        RelayerState calldata _activeState,
        uint256 _relayerIndex,
        uint256 _epochEndTimestamp,
        FixedPointType _totalTransactionsInEpoch
    ) internal returns (bool relayerWasJailed, uint256 penalty) {
        if (_verifyRelayerLiveness(_activeState, _relayerIndex, _epochEndTimestamp, _totalTransactionsInEpoch)) {
            return (false, penalty);
        }

        RelayerAddress relayerAddress = _activeState.relayers[_relayerIndex];

        // Penalize the relayer
        (uint256 stakeAfterPenalization, uint256 penalty_) = _penalizeRelayer(relayerAddress);
        penalty = penalty_;

        if (stakeAfterPenalization < MINIMUM_STAKE_AMOUNT) {
            _jailRelayer(relayerAddress);
            relayerWasJailed = true;
        }
    }

    function _postLivnessCheck(
        RelayerState calldata _pendingState,
        uint256 _totalPenalty,
        uint256 _activeRelayersJailedCount,
        RelayerAddress[] memory _postJailRelayerList
    ) internal {
        RMStorage storage rms = getRMStorage();

        // Update Global Counters
        if (_totalPenalty != 0) {
            rms.totalStake -= _totalPenalty;
        }
        if (_activeRelayersJailedCount != 0) {
            rms.relayerCount -= _activeRelayersJailedCount;
        }

        // Schedule CDF Update if Necessary
        if (_totalPenalty != 0 || _activeRelayersJailedCount != 0) {
            _verifyExternalStateForCdfUpdation(_pendingState.cdf.cd_hash(), _pendingState.relayers.cd_hash());
            if (_activeRelayersJailedCount == 0) {
                _updateCdf_c(_pendingState.relayers);
            } else {
                _updateCdf_m(_postJailRelayerList);
            }
        }

        // Transfer the penalty to the caller
        if (_totalPenalty != 0) {
            _transfer(TokenAddress.wrap(address(rms.bondToken)), msg.sender, _totalPenalty);
        }
    }

    function _jailRelayer(RelayerAddress _relayerAddress) internal {
        getRMStorage().relayerInfo[_relayerAddress].status = RelayerStatus.Jailed;
        emit RelayerJailed(_relayerAddress);
    }

    function _penalizeRelayer(RelayerAddress _relayerAddress) internal returns (uint256, uint256) {
        RelayerInfo storage relayerInfo = getRMStorage().relayerInfo[_relayerAddress];
        uint256 penalty = _calculatePenalty(relayerInfo.stake);
        relayerInfo.stake -= penalty;

        emit RelayerPenalized(_relayerAddress, relayerInfo.stake, penalty);

        return (relayerInfo.stake, penalty);
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
        FixedPointType _totalTransactions,
        FixedPointType _zScore
    ) public pure override returns (FixedPointType) {
        if (_totalTransactions == FP_ZERO) {
            return FP_ZERO;
        }

        if (_totalStake == 0) {
            revert NoRelayersRegistered();
        }

        FixedPointType p = _relayerStake.fp() / _totalStake.fp();
        FixedPointType s = ((p * (FP_ONE - p)) / _totalTransactions).sqrt();
        FixedPointType d = _zScore * s;
        FixedPointType e = p * _totalTransactions;
        if (e > d) {
            return e - d;
        }

        return FP_ZERO;
    }

    function _verifyRelayerLiveness(
        RelayerState calldata _activeState,
        uint256 _relayerIndex,
        uint256 _epochEndTimestamp,
        FixedPointType _totalTransactionsInEpoch
    ) internal returns (bool) {
        TAStorage storage ts = getTAStorage();
        FixedPointType minimumTransactions;
        {
            uint256 relayerStakeNormalized = _activeState.cdf[_relayerIndex];

            if (_relayerIndex != 0) {
                relayerStakeNormalized -= _activeState.cdf[_relayerIndex - 1];
            }

            minimumTransactions = calculateMinimumTranasctionsForLiveness(
                relayerStakeNormalized,
                _activeState.cdf[_activeState.cdf.length - 1],
                _totalTransactionsInEpoch,
                LIVENESS_Z_PARAMETER
            );
        }

        RelayerAddress relayerAddress = _activeState.relayers[_relayerIndex];
        uint256 transactionsProcessedByRelayer = ts.transactionsSubmitted[_epochEndTimestamp][relayerAddress];
        delete ts.transactionsSubmitted[_epochEndTimestamp][relayerAddress];
        return transactionsProcessedByRelayer.fp() >= minimumTransactions;
    }

    function _calculatePenalty(uint256 _stake) internal pure returns (uint256) {
        return (_stake * ABSENCE_PENALTY) / (100 * PERCENTAGE_MULTIPLIER);
    }

    ///////////////////////////////// Getters ///////////////////////////////
    function transactionsSubmittedRelayer(RelayerAddress _relayerAddress) external view override returns (uint256) {
        return getTAStorage().transactionsSubmitted[getTAStorage().epochEndTimestamp][_relayerAddress];
    }

    function totalTransactionsSubmitted() external view override returns (uint256) {
        return getTAStorage().totalTransactionsSubmitted[getTAStorage().epochEndTimestamp];
    }

    function epochLengthInSec() external view override returns (uint256) {
        return getTAStorage().epochLengthInSec;
    }

    function epochEndTimestamp() external view override returns (uint256) {
        return getTAStorage().epochEndTimestamp;
    }
}
