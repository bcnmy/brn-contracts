// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import "src/transaction-allocator/common/TAStructs.sol";
import "src/transaction-allocator/common/TAHelpers.sol";
import "src/transaction-allocator/common/TATypes.sol";
import "src/paymaster/interfaces/IPaymaster.sol";
import "./interfaces/ITATransactionAllocation.sol";
import "./TATransactionAllocationStorage.sol";
import "../application/base-application/interfaces/IApplicationBase.sol";
import "../relayer-management/TARelayerManagementStorage.sol";

contract TATransactionAllocation is ITATransactionAllocation, TAHelpers, TATransactionAllocationStorage {
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
        uint256 _relayerGenerationIterationBitmap,
        uint256 _relayerIndex,
        uint256 _currentCdfLogIndex
    ) public payable override returns (bool[] memory successes) {
        uint256 gasLeft = gasleft();

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
                msg.sender, _cdf, _currentCdfLogIndex, _relayerIndex, _relayerGenerationIterationBitmap, block.number
            )
        ) {
            revert InvalidRelayerWindow();
        }
        emit GenericGasConsumed("VerificationGas", gasLeft - gasleft());
        gasLeft = gasleft();

        successes = new bool[](length);
        RMStorage storage ds = getRMStorage();
        uint256 relayerCount = ds.relayersPerWindow;
        RelayerAddress relayerAddress = ds.relayerIndexToRelayerAddress[_relayerIndex];

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

        gasLeft = gasleft();
        // TODO: Account for caes where the relayer list changes between epochs or if a relayer is exiting in the current epoch
        getTAStorage().transactionsSubmitted[_epochIndexFromBlock(block.number)][relayerAddress] +=
            transactionsAllotedAndSubmittedByRelayer;
        emit GenericGasConsumed("OtherOverhead", gasLeft - gasleft());

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
    function allocateRelayers(uint16[] calldata _cdf, uint256 _currentCdfLogIndex)
        public
        view
        override
        returns (RelayerAddress[] memory, uint256[] memory)
    {
        RMStorage storage ds = getRMStorage();

        if (!_verifyCdfHashAtWindow(_cdf, _windowIndex(block.number), _currentCdfLogIndex)) {
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
            uint256 randomCdfNumber = _randomCdfNumber(block.number, i, _cdf[cdfLength - 1]);
            cdfIndex[i] = _lowerBound(_cdf, randomCdfNumber);
            selectedRelayers[i] = ds.relayerIndexToRelayerAddress[cdfIndex[i]];
            unchecked {
                ++i;
            }
        }
        return (selectedRelayers, cdfIndex);
    }
}
