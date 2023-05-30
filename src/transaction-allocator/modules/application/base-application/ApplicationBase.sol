// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import "./interfaces/IApplicationBase.sol";

import "ta-transaction-allocation/interfaces/ITATransactionAllocation.sol";
import "ta-relayer-management/TARelayerManagementStorage.sol";

abstract contract ApplicationBase is IApplicationBase, TARelayerManagementStorage {
    modifier applicationHandler(bytes calldata _dataToHash) {
        if (msg.sender != address(this)) revert ExternalCallsNotAllowed();

        (, uint256 relayerGenerationIterationBitmap, uint256 relayersPerWindow) = _getCalldataParams();

        if (!_verifyTransactionAllocation(_dataToHash, relayerGenerationIterationBitmap, relayersPerWindow)) {
            revert RelayerNotAssignedToTransaction();
        }

        _;
    }

    function _getCalldataParams()
        internal
        pure
        virtual
        returns (RelayerAddress relayerAddress, uint256 relayerGenerationIterationBitmap, uint256 relayersPerWindow)
    {
        /*
         * Calldata Map
         * |-------?? bytes--------|------32 bytes-------|---------32 bytes -------------|---------20 bytes -------|
         * |---Original Calldata---|------RGI Bitmap-----|------Relayers Per Window------|-----Relayer Address-----|
         */
        assembly {
            relayerAddress := shr(96, calldataload(sub(calldatasize(), 20)))
            relayersPerWindow := calldataload(sub(calldatasize(), 52))
            relayerGenerationIterationBitmap := calldataload(sub(calldatasize(), 84))
        }
    }

    function _getTransactionHash(bytes calldata _txCalldata) internal pure virtual returns (bytes32);

    function _getAllotedRelayerIndex(bytes calldata _txCalldata, uint256 _relayersPerWindow)
        internal
        pure
        virtual
        returns (uint256)
    {
        bytes32 txHash = _getTransactionHash(_txCalldata);
        return uint256(txHash) % _relayersPerWindow;
    }

    function _verifyTransactionAllocation(
        bytes calldata _txCalldata,
        uint256 _relayerGenerationIterationBitmap,
        uint256 _relayersPerWindow
    ) internal pure virtual returns (bool) {
        uint256 relayerIndex = _getAllotedRelayerIndex(_txCalldata, _relayersPerWindow);
        return (_relayerGenerationIterationBitmap >> relayerIndex) & 1 == 1;
    }

    function _allocateTransaction(
        RelayerAddress _relayerAddress,
        bytes[] calldata _requests,
        RelayerState calldata _currentState
    )
        internal
        view
        returns (bytes[] memory txnAllocated, uint256 relayerGenerationIterations, uint256 selectedRelayerCdfIndex)
    {
        (RelayerAddress[] memory relayersAllocated, uint256[] memory relayerStakePrefixSumIndex) =
            ITATransactionAllocation(address(this)).allocateRelayers(_currentState);
        if (relayersAllocated.length != getRMStorage().relayersPerWindow) {
            revert RelayerAllocationResultLengthMismatch(getRMStorage().relayersPerWindow, relayersAllocated.length);
        }

        // Filter the transactions
        uint256 length = _requests.length;
        txnAllocated = new bytes[](length);
        uint256 j;
        for (uint256 i; i != length;) {
            // If the transaction can be processed by this relayer, store it's info
            uint256 relayerIndex = _getAllotedRelayerIndex(_requests[i], relayersAllocated.length);
            if (relayersAllocated[relayerIndex] == _relayerAddress) {
                relayerGenerationIterations |= (1 << relayerIndex);
                txnAllocated[j] = _requests[i];
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
        uint256 extraLength = _requests.length - j;
        assembly {
            mstore(txnAllocated, sub(mload(txnAllocated), extraLength))
        }
    }
}
