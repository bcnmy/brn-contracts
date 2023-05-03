// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import "./interfaces/IApplicationBase.sol";
import "src/transaction-allocator/common/TAStructs.sol";
import "src/transaction-allocator/modules/transaction-allocation/interfaces/ITATransactionAllocation.sol";
import "src/transaction-allocator/modules/relayer-management/TARelayerManagementStorage.sol";

abstract contract ApplicationBase is IApplicationBase, TARelayerManagementStorage {
    modifier onlySelf() {
        if (msg.sender != address(this)) revert ExternalCallsNotAllowed();
        _;
    }

    function _getCalldataParams()
        internal
        pure
        virtual
        returns (uint256 relayerGenerationIterationBitmap, uint256 relayerCount)
    {
        /*
         * Calldata Map
         * |-------?? bytes--------|------32 bytes-------|---------32 bytes -------|
         * |---Original Calldata---|------RGI Bitmap-----|------Relayer Count------|
         */
        assembly {
            relayerGenerationIterationBitmap := calldataload(sub(calldatasize(), 64))
            relayerCount := calldataload(sub(calldatasize(), 32))
        }
    }

    function _getTransactionHash(bytes calldata _tx) internal pure virtual returns (bytes32);

    function _getAllotedRelayerIndex(bytes calldata _tx, uint256 _relayersPerWindow)
        internal
        pure
        virtual
        returns (uint256)
    {
        return uint256(_getTransactionHash(_tx)) % _relayersPerWindow;
    }

    function _verifyTransactionAllocation(
        bytes calldata _tx,
        uint256 _relayerGenerationIterationBitmap,
        uint256 _relayersPerWindow
    ) internal pure virtual returns (bool) {
        return (_relayerGenerationIterationBitmap >> _getAllotedRelayerIndex(_tx, _relayersPerWindow)) & 1 == 1;
    }

    function _allocateTransaction(AllocateTransactionParams calldata _data)
        external
        view
        returns (bytes[] memory, uint256[] memory, uint256)
    {
        (RelayerAddress[] memory relayersAllocated, uint256[] memory relayerStakePrefixSumIndex) =
            ITATransactionAllocation(address(this)).allocateRelayers(_data.cdf, _data.currentCdfLogIndex);
        if (relayersAllocated.length != getRMStorage().relayersPerWindow) {
            revert RelayerAllocationResultLengthMismatch(getRMStorage().relayersPerWindow, relayersAllocated.length);
        }

        // Filter the transactions
        uint256 selectedRelayerCdfIndex;
        bytes[] memory txnAllocated = new bytes[](_data.requests.length);
        uint256[] memory relayerGenerationIteration = new uint256[](
            _data.requests.length
        );
        uint256 j;
        for (uint256 i = 0; i < _data.requests.length;) {
            // If the transaction can be processed by this relayer, store it's info
            uint256 relayerIndex = _getAllotedRelayerIndex(_data.requests[i], getRMStorage().relayersPerWindow);
            if (relayersAllocated[relayerIndex] == _data.relayerAddress) {
                relayerGenerationIteration[j] = relayerIndex;
                txnAllocated[j] = _data.requests[i];
                selectedRelayerCdfIndex = relayerStakePrefixSumIndex[relayerIndex];
                unchecked {
                    ++j;
                }
            }

            unchecked {
                ++i;
            }
        }

        // Reduce the array sizes if needed
        uint256 extraLength = _data.requests.length - j;
        assembly {
            mstore(txnAllocated, sub(mload(txnAllocated), extraLength))
            mstore(relayerGenerationIteration, sub(mload(relayerGenerationIteration), extraLength))
        }

        return (txnAllocated, relayerGenerationIteration, selectedRelayerCdfIndex);
    }
}
