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
    function _verifyRelayerWasSelectedForTransaction(bool _success, bytes memory _returndata)
        internal
        pure
        returns (bool result)
    {
        result = _success || (bytes4(_returndata) == IApplicationBase.RelayerNotAssignedToTransaction.selector);
    }

    function _execute(
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

    /// @notice allows relayer to execute a tx on behalf of a client
    // TODO: can we decrease calldata cost by using merkle proofs or square root decomposition?
    // TODO: Non Reentrant?
    function execute(
        bytes[] calldata _reqs,
        uint256[] calldata _forwardedNativeAmounts,
        uint16[] calldata _cdf,
        uint256 _currentCdfLogIndex,
        RelayerAddress[] calldata _activeRelayers,
        uint256 _currentRelayerListLogIndex,
        uint256 _relayerIndex,
        uint256 _relayerGenerationIterationBitmap
    ) public payable override returns (bool[] memory successes) {
        // Verify whether sufficient fee has been attached or not
        uint256 length = _reqs.length;
        if (length != _forwardedNativeAmounts.length) {
            revert ParameterLengthMismatch();
        }
        uint256 totalExpectedValue;
        for (uint256 i; i < length;) {
            totalExpectedValue += _forwardedNativeAmounts[i];
            unchecked {
                ++i;
            }
        }
        if (msg.value != totalExpectedValue) {
            revert InvalidFeeAttached(totalExpectedValue, msg.value);
        }

        // Verify Relayer Selection
        if (
            !_verifyRelayerSelection(
                msg.sender,
                _cdf,
                _currentCdfLogIndex,
                _activeRelayers,
                _currentRelayerListLogIndex,
                _relayerIndex,
                _relayerGenerationIterationBitmap,
                block.number
            )
        ) {
            revert InvalidRelayerWindow();
        }

        successes = new bool[](length);
        uint256 relayerCount = _activeRelayers.length;
        RelayerAddress relayerAddress = _activeRelayers[_relayerIndex];

        // Execute all transactions
        uint256 transactionsAllotedAndSubmittedByRelayer;
        for (uint256 i; i < length;) {
            (bool success, bytes memory returndata) = _execute(
                _reqs[i], _forwardedNativeAmounts[i], _relayerGenerationIterationBitmap, relayerCount, relayerAddress
            );

            if (_verifyRelayerWasSelectedForTransaction(success, returndata)) {
                ++transactionsAllotedAndSubmittedByRelayer;
            }

            emit TransactionStatus(i, success);

            successes[i] = success;

            if (!success) {
                revert TransactionExecutionFailed(i);
            }

            unchecked {
                ++i;
            }
        }

        // Record the number of transactions submitted by the relayer
        TAStorage storage ts = getTAStorage();
        uint256 epochIndex = _epochIndexFromBlock(block.number);
        // TODO: Is extra update for total transactions TRULY required?
        ts.transactionsSubmitted[epochIndex][relayerAddress] += transactionsAllotedAndSubmittedByRelayer;
        ts.totalTransactionsSubmitted[epochIndex] += transactionsAllotedAndSubmittedByRelayer;

        // TODO: Check how to update this logic
        // Validate that the relayer has sent enough gas for the call.
        // if (gasleft() <= totalGas / 63) {
        //     assembly {
        //         invalid()
        //     }
        // }

        return successes;
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
    )
        public
        view
        override
        verifyActiveRelayerList(_activeRelayers, _relayerLogIndex, block.number)
        returns (RelayerAddress[] memory, uint256[] memory)
    {
        RMStorage storage ds = getRMStorage();

        uint256 windowIndex = _windowIndex(block.number);

        // TODO: Modifier
        // Verify CDF
        if (
            !ds.cdfVersionHistoryManager.verifyContentHashAtTimestamp(
                _hashUint16ArrayCalldata(_cdf), _currentCdfLogIndex, windowIndex
            )
        ) {
            revert InvalidCdfArrayHash();
        }

        if (_cdf.length == 0) {
            revert NoRelayersRegistered();
        }

        // Generate `relayersPerWindow` pseudo-random distinct relayers
        RelayerAddress[] memory selectedRelayers = new RelayerAddress[](ds.relayersPerWindow);
        uint256[] memory cdfIndex = new uint256[](ds.relayersPerWindow);

        uint256 cdfLength = _cdf.length;
        if (_cdf[cdfLength - 1] == 0) {
            revert NoRelayersRegistered();
        }

        for (uint256 i = 0; i < ds.relayersPerWindow;) {
            uint256 randomCdfNumber = _randomNumberForCdfSelection(block.number, i, _cdf[cdfLength - 1]);
            cdfIndex[i] = _lowerBound(_cdf, randomCdfNumber);
            selectedRelayers[i] = _activeRelayers[cdfIndex[i]];
            unchecked {
                ++i;
            }
        }
        return (selectedRelayers, cdfIndex);
    }

    ///////////////////////////////// Liveness ///////////////////////////////
    function _calculateMinimumTranasctionsForLiveness(
        uint256 _relayerStake,
        uint256 _totalStake,
        FixedPointType _totalTransactions,
        FixedPointType _zScore
    ) internal pure returns (FixedPointType) {
        FixedPointType p = _relayerStake.fp() / _totalStake.fp();
        FixedPointType s = (p * (FP_ONE - p) / _totalTransactions).sqrt();
        FixedPointType d = _zScore * s;
        if (p > d) {
            return p - d;
        }

        return FP_ZERO;
    }

    function _verifyRelayerLiveness(
        uint16[] calldata _cdf,
        RelayerAddress[] calldata _activeRelayers,
        uint256 _relayerIndex,
        FixedPointType _totalTransactionsInEpoch
    ) internal view returns (bool) {
        uint256 relayerStakeNormalized = _cdf[_relayerIndex];
        uint256 transactionsProcessedByRelayer =
            getTAStorage().transactionsSubmitted[_epochIndexFromBlock(block.number)][_activeRelayers[_relayerIndex]];

        if (_relayerIndex != 0) {
            relayerStakeNormalized -= _cdf[_relayerIndex - 1];
        }

        FixedPointType expectedLow = _calculateMinimumTranasctionsForLiveness(
            relayerStakeNormalized, _cdf[_cdf.length - 1], _totalTransactionsInEpoch, LIVENESS_Z_PARAMETER
        );

        FixedPointType actualProportion = transactionsProcessedByRelayer.fp() / _totalTransactionsInEpoch;

        return actualProportion >= expectedLow;
    }

    function _calculatePenalty(uint256 _stake) internal pure returns (uint256) {
        return (_stake * ABSENCE_PENALTY) / (100 * PERCENTAGE_MULTIPLIER);
    }

    function _penalizeRelayer(
        RelayerAddress _relayerAddress,
        uint256 _relayerIndex,
        uint32[] calldata _currentStakeArray,
        uint32[] calldata _currentDelegationArray
    ) internal {
        uint256 penalty;

        // TODO: What happens if relayer stake is less than minimum stake after penalty?
        if (_isStakedRelayer(_relayerAddress)) {
            // If the relayer is still registered at this point of time, then we need to update the stake array and CDF
            RelayerInfo storage relayerInfo = getRMStorage().relayerInfo[_relayerAddress];
            penalty = _calculatePenalty(relayerInfo.stake);
            relayerInfo.stake -= penalty;
            uint32[] memory newStakeArray = _currentStakeArray.update(_relayerIndex, _scaleStake(relayerInfo.stake));
            _updateCdf(newStakeArray, true, _currentDelegationArray, false);
        } else {
            // If the relayer un-registered itself, then we just subtract from their withdrawl info
            WithdrawalInfo storage withdrawalInfo_ = getRMStorage().withdrawalInfo[_relayerAddress];
            penalty = _calculatePenalty(withdrawalInfo_.amount);
            withdrawalInfo_.amount -= penalty;
        }

        // TODO: What should be done with the penalty amount?

        emit RelayerPenalized(_relayerAddress, _epochIndexFromBlock(block.number), penalty);
    }

    function _processLivenessCheck(
        uint16[] calldata _cdf,
        uint256 _cdfLogIndex,
        RelayerAddress[] calldata _activeRelayers,
        uint256 _relayerLogIndex,
        uint32[] calldata _currentStakeArray,
        uint32[] calldata _currentDelegationArray,
        uint256 _epochIndex
    )
        internal
        verifyActiveRelayerList(_activeRelayers, _relayerLogIndex, _epochIndexToStartingBlock(_epochIndex))
        verifyCDF(_cdf, _cdfLogIndex, _epochIndexToStartingBlock(_epochIndex))
        verifyStakeArrayHash(_currentStakeArray)
        verifyDelegationArrayHash(_currentDelegationArray)
    {
        FixedPointType totalTransactionsInEpoch = getTAStorage().totalTransactionsSubmitted[_epochIndex].fp();

        for (uint256 i; i < _activeRelayers.length;) {
            if (!_verifyRelayerLiveness(_cdf, _activeRelayers, i, totalTransactionsInEpoch)) {
                _penalizeRelayer(_activeRelayers[i], i, _currentStakeArray, _currentDelegationArray);
            }
            unchecked {
                ++i;
            }
        }
    }
}
