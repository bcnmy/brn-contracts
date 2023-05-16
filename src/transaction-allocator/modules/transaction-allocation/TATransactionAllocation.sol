// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import "src/transaction-allocator/common/TAStructs.sol";
import "src/transaction-allocator/common/TAHelpers.sol";
import "src/transaction-allocator/common/TATypes.sol";
import "src/library/ArrayHelpers.sol";
import "./interfaces/ITATransactionAllocation.sol";
import "./TATransactionAllocationStorage.sol";
import "../application/base-application/interfaces/IApplicationBase.sol";
import "../relayer-management/TARelayerManagementStorage.sol";

contract TATransactionAllocation is ITATransactionAllocation, TAHelpers, TATransactionAllocationStorage {
    using VersionHistoryManager for VersionHistoryManager.Version[];
    using FixedPointTypeHelper for FixedPointType;
    using Uint256WrapperHelper for uint256;
    using U32CalldataArrayHelpers for uint32[];

    ///////////////////////////////// Transaction Execution ///////////////////////////////
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

    /// @notice allows relayer to execute a tx on behalf of a client
    // TODO: can we decrease calldata cost by using merkle proofs or square root decomposition?
    // TODO: Non Reentrant?
    function execute(
        bytes[] calldata _reqs,
        uint256[] calldata _forwardedNativeAmounts,
        uint16[] calldata _cdf,
        uint256 _currentCdfLogIndex,
        RelayerAddress[] calldata _activeRelayers,
        uint256 _relayerLogIndex,
        uint256 _relayerIndex,
        uint256 _relayerGenerationIterationBitmap
    ) public payable override {
        uint256 length = _reqs.length;
        if (length != _forwardedNativeAmounts.length) {
            revert ParameterLengthMismatch();
        }

        _verifySufficientValueAttached(_forwardedNativeAmounts);

        // Verify Relayer Selection
        if (
            !_verifyRelayerSelection(
                msg.sender,
                _cdf,
                _currentCdfLogIndex,
                _activeRelayers,
                _relayerLogIndex,
                _relayerIndex,
                _relayerGenerationIterationBitmap,
                block.number
            )
        ) {
            revert InvalidRelayerWindow();
        }

        // Execute Transactions
        _executeTransactions(
            _reqs,
            _forwardedNativeAmounts,
            _activeRelayers.length,
            _activeRelayers[_relayerIndex],
            _relayerGenerationIterationBitmap
        );

        // Record Liveness Metrics
        TAStorage storage ts = getTAStorage();
        uint256 epochIndex = _epochIndexFromBlock(block.number);
        // TODO: Is extra store for total transactions TRULY required?
        unchecked {
            ++ts.transactionsSubmitted[epochIndex][_activeRelayers[_relayerIndex]];
            ++ts.totalTransactionsSubmitted[epochIndex];
        }

        // TODO: Check how to update this logic
        // Validate that the relayer has sent enough gas for the call.
        // if (gasleft() <= totalGas / 63) {
        //     assembly {
        //         invalid()
        //     }
        // }
    }

    /////////////////////////////// Allocation Helpers ///////////////////////////////
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
    function allocateRelayers(
        uint16[] calldata _cdf,
        uint256 _currentCdfLogIndex,
        RelayerAddress[] calldata _activeRelayers,
        uint256 _relayerLogIndex
    ) external view override returns (RelayerAddress[] memory selectedRelayers, uint256[] memory cdfIndex) {
        _verifyExternalStateForTransactionAllocation(
            _cdf, _currentCdfLogIndex, _activeRelayers, _relayerLogIndex, block.number
        );

        if (_cdf.length == 0) {
            revert NoRelayersRegistered();
        }

        if (_cdf[_cdf.length - 1] == 0) {
            revert NoRelayersRegistered();
        }

        {
            RMStorage storage ds = getRMStorage();
            selectedRelayers = new RelayerAddress[](ds.relayersPerWindow);
            cdfIndex = new uint256[](ds.relayersPerWindow);
        }

        for (uint256 i = 0; i != getRMStorage().relayersPerWindow;) {
            uint256 randomCdfNumber = _randomNumberForCdfSelection(block.number, i, _cdf[_cdf.length - 1]);
            cdfIndex[i] = _lowerBound(_cdf, randomCdfNumber);
            selectedRelayers[i] = _activeRelayers[cdfIndex[i]];
            unchecked {
                ++i;
            }
        }
        return (selectedRelayers, cdfIndex);
    }

    ///////////////////////////////// Liveness ///////////////////////////////
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
        TargetEpochData calldata _targetEpochData,
        uint256 _relayerIndex,
        FixedPointType _totalTransactionsInEpoch
    ) internal view returns (bool) {
        uint256 relayerStakeNormalized = _targetEpochData.cdf[_relayerIndex];
        uint256 transactionsProcessedByRelayer = getTAStorage().transactionsSubmitted[_targetEpochData.epochIndex][_targetEpochData
            .activeRelayers[_relayerIndex]];

        if (_relayerIndex != 0) {
            relayerStakeNormalized -= _targetEpochData.cdf[_relayerIndex - 1];
        }

        FixedPointType minimumTransactions = calculateMinimumTranasctionsForLiveness(
            relayerStakeNormalized,
            _targetEpochData.cdf[_targetEpochData.cdf.length - 1],
            _totalTransactionsInEpoch,
            LIVENESS_Z_PARAMETER
        );

        return transactionsProcessedByRelayer.fp() >= minimumTransactions;
    }

    function _calculatePenalty(uint256 _stake) internal pure returns (uint256) {
        return (_stake * ABSENCE_PENALTY) / (100 * PERCENTAGE_MULTIPLIER);
    }

    function _checkRelayerIndexInNewMapping(
        RelayerAddress[] calldata _oldRelayerIndexToRelayerMapping,
        RelayerAddress[] calldata _newRelayerIndexToRelayerMapping,
        uint256 _oldIndex,
        uint256 _proposedNewIndex
    ) internal pure {
        if (_oldRelayerIndexToRelayerMapping[_oldIndex] != _newRelayerIndexToRelayerMapping[_proposedNewIndex]) {
            revert RelayerIndexMappingMismatch(_oldIndex, _proposedNewIndex);
        }
    }

    function processLivenessCheck(
        TargetEpochData calldata _targetEpochData,
        LatestActiveRelayersStakeAndDelegationState calldata _latestState,
        uint256[] calldata _targetEpochRelayerIndexToLatestRelayerIndexMapping
    ) external override {
        // Verify the state against which the new CDF would be calculated
        _verifyExternalStateForCdfUpdation(
            _latestState.currentStakeArray, _latestState.currentDelegationArray, _latestState.activeRelayers
        );

        // Verify the state of the Epoch for which the liveness check is being processed
        _verifyExternalStateForTransactionAllocation(
            _targetEpochData.cdf,
            _targetEpochData.cdfLogIndex,
            _targetEpochData.activeRelayers,
            _targetEpochData.relayerLogIndex,
            _epochIndexToStartingBlock(_targetEpochData.epochIndex)
        );

        // Verify that the liveness check is being processed for a past epoch
        if (_targetEpochData.epochIndex >= _epochIndexFromBlock(block.number)) {
            revert CannotProcessLivenessCheckForCurrentOrFutureEpoch();
        }

        FixedPointType totalTransactionsInEpoch;
        {
            // Check if the liveness check has already been processed for the epoch
            TAStorage storage ts = getTAStorage();
            if (ts.livenessCheckProcessed[_targetEpochData.epochIndex]) {
                revert LivenessCheckAlreadyProcessed();
            }
            ts.livenessCheckProcessed[_targetEpochData.epochIndex] = true;

            totalTransactionsInEpoch = ts.totalTransactionsSubmitted[_targetEpochData.epochIndex].fp();
        }
        uint256 relayerCountInTargetEpoch = _targetEpochData.activeRelayers.length;

        uint32[] memory newStakeArray = _latestState.currentStakeArray;
        bool shouldUpdateCdf = false;

        for (uint256 i; i != relayerCountInTargetEpoch;) {
            if (_verifyRelayerLiveness(_targetEpochData, i, totalTransactionsInEpoch)) {
                unchecked {
                    ++i;
                }
                continue;
            }

            // Penalize the relayer
            uint256 penalty;
            RelayerAddress relayerAddress = _targetEpochData.activeRelayers[i];

            // TODO: What happens if relayer stake is less than minimum stake after penalty?
            if (_isStakedRelayer(relayerAddress)) {
                // If the relayer is still registered at this point of time, then we need to update the stake array and CDF
                RelayerInfo storage relayerInfo = getRMStorage().relayerInfo[relayerAddress];
                penalty = _calculatePenalty(relayerInfo.stake);
                relayerInfo.stake -= penalty;

                // Update the stake array, we need to get the new relayer index based on the provided mapping
                uint256 newRelayerIndex = _targetEpochRelayerIndexToLatestRelayerIndexMapping[i];
                _checkRelayerIndexInNewMapping(
                    _targetEpochData.activeRelayers, _latestState.activeRelayers, i, newRelayerIndex
                );
                newStakeArray[newRelayerIndex] = _scaleStake(relayerInfo.stake);
                shouldUpdateCdf = true;
            } else {
                // If the relayer un-registered itself, then we just subtract from their withdrawl info
                WithdrawalInfo storage withdrawalInfo_ = getRMStorage().withdrawalInfo[relayerAddress];
                penalty = _calculatePenalty(withdrawalInfo_.amount);
                withdrawalInfo_.amount -= penalty;
            }

            // TODO: What should be done with the penalty amount?

            emit RelayerPenalized(relayerAddress, _targetEpochData.epochIndex, penalty);

            unchecked {
                ++i;
            }
        }

        // Process All CDF Updates if Necessary
        if (shouldUpdateCdf) {
            _updateCdf(newStakeArray, true, _latestState.currentDelegationArray, false);
        }
    }

    ///////////////////////////////// Getters ///////////////////////////////
    function transactionsSubmittedInEpochByRelayer(uint256 _epoch, RelayerAddress _relayerAddress)
        external
        view
        override
        returns (uint256)
    {
        return getTAStorage().transactionsSubmitted[_epoch][_relayerAddress];
    }

    function totalTransactionsSubmittedInEpoch(uint256 _epoch) external view override returns (uint256) {
        return getTAStorage().totalTransactionsSubmitted[_epoch];
    }

    function livenessCheckProcessedForEpoch(uint256 _epoch) external view override returns (bool) {
        return getTAStorage().livenessCheckProcessed[_epoch];
    }
}
