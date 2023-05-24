// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import "src/transaction-allocator/common/TAHelpers.sol";
import "src/transaction-allocator/common/TATypes.sol";

import "./interfaces/ITATransactionAllocation.sol";
import "./TATransactionAllocationStorage.sol";
import "../application/base-application/interfaces/IApplicationBase.sol";
import "../relayer-management/TARelayerManagementStorage.sol";

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
    // TODO: Non Reentrant?
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

        TAStorage storage ts = getTAStorage();

        // Record Liveness Metrics
        unchecked {
            ++ts.transactionsSubmitted[ts.epochEndTimestamp][relayerAddress];
            ++ts.totalTransactionsSubmitted[ts.epochEndTimestamp];
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
    // TODO: Use oz
    function _lowerBound(uint16[] calldata arr, uint256 target) internal pure returns (uint256) {
        uint256 low = 0;
        uint256 high = arr.length;
        unchecked {
            while (low < high) {
                uint256 mid = (low + high) / 2;
                if (arr[mid] < target) {
                    low = mid + 1;
                } else {
                    high = mid;
                }
            }
        }
        return low;
    }

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
            uint256 randomCdfNumber = _randomNumberForCdfSelection(block.number, i, _activeState.cdf[relayerCount - 1]);
            cdfIndex[i] = _lowerBound(_activeState.cdf, randomCdfNumber);
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
    function _processLivenessCheck(RelayerState calldata _activeState, RelayerState calldata _pendingState) internal {
        TAStorage storage ts = getTAStorage();
        RMStorage storage rms = getRMStorage();

        uint256 epochEndTimestamp_ = ts.epochEndTimestamp;

        if (ts.epochEndTimestamp < block.timestamp) {
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

        uint256 relayerCount = _activeState.relayers.length;
        bool shouldUpdateCdf;

        for (uint256 i; i != relayerCount;) {
            if (_processLivnessCheckForRelayer(_activeState, i, epochEndTimestamp_, totalTransactionsInEpoch)) {
                shouldUpdateCdf = true;
            }

            unchecked {
                ++i;
            }
        }

        // Schedule CDF Update if Necessary
        if (shouldUpdateCdf) {
            _verifyExternalStateForCdfUpdation(_pendingState.cdf.cd_hash(), _pendingState.relayers.cd_hash());
            _updateCdf_c(_pendingState.relayers);
        }

        // Process any pending Updates
        uint256 updateWindowIndex = _nextWindowForUpdate(block.number);
        rms.relayerStateVersionManager.setPendingStateForActivation(updateWindowIndex);

        // Update the epoch end time
        ts.epochEndTimestamp = block.timestamp + ts.epochLengthInSec;
        emit EpochEndTimestampUpdated(ts.epochEndTimestamp);
    }

    function _processLivnessCheckForRelayer(
        RelayerState calldata _activeState,
        uint256 _relayerIndex,
        uint256 _epochEndTimestamp,
        FixedPointType _totalTransactionsInEpoch
    ) internal returns (bool) {
        if (_verifyRelayerLiveness(_activeState, _relayerIndex, _epochEndTimestamp, _totalTransactionsInEpoch)) {
            return false;
        }

        RelayerAddress relayerAddress = _activeState.relayers[_relayerIndex];

        // Penalize the relayer
        (uint256 newStake, uint256 penalty) = _penalizeRelayer(relayerAddress);

        if (newStake < MINIMUM_STAKE_AMOUNT) {
            // TODO: Jail the relayer
        }

        // TODO: What should be done with the penalty amount?
        emit RelayerPenalized(relayerAddress, newStake, penalty);

        return true;
    }

    function _penalizeRelayer(RelayerAddress _relayerAddress) internal returns (uint256, uint256) {
        RelayerInfo storage relayerInfo = getRMStorage().relayerInfo[_relayerAddress];
        uint256 penalty = _calculatePenalty(relayerInfo.stake);
        relayerInfo.stake -= penalty;
        return (relayerInfo.stake, penalty);
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
