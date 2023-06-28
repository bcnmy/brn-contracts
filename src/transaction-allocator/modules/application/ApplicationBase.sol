// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import "./interfaces/IApplicationBase.sol";

import "ta-transaction-allocation/interfaces/ITATransactionAllocation.sol";
import "ta-relayer-management/TARelayerManagementStorage.sol";

/// @title ApplicationBase
/// @dev This contract can be inherited by applications wishing to use BRN's services.
///      In general, an application module is responsible for implementing:
///      1. Transaction Alloction: Given a transaction, which "selected" relayer should process it?
///      2. Payments and refunds: The application should compensate the relayers for their work.
///      3. Provide a way for relayers to know which transactions they should process.
abstract contract ApplicationBase is IApplicationBase, TARelayerManagementStorage {
    /// @dev Verifies that the transaction was allocated to the relayer and other validations.
    ///      This function should be called by the application before processing the transaction.
    ///      Reverts if the transaction was not allocated to the relayer.
    /// @param _txHash Transaction hash of the transaction
    function _verifyTransaction(bytes32 _txHash) internal view {
        if (msg.sender != address(this)) {
            revert ExternalCallsNotAllowed();
        }

        (, uint256 relayerGenerationIterationBitmap, uint256 relayersPerWindow) = _getCalldataParams();

        if (!_verifyTransactionAllocation(_txHash, relayerGenerationIterationBitmap, relayersPerWindow)) {
            revert RelayerNotAssignedToTransaction();
        }
    }

    /// @dev The TransactionAllocator contract will append the some useful data at the end of the calldata. This function
    ///      extracts that data and returns it.
    /// @return relayerAddress Main Address of the relayer processing the transaction (not necessarily tx.origin)
    /// @return relayerGenerationIterationBitmap Bitmap with a set bit indicating a relayer is able to process the transaction
    ///         if the hashmod of the transaction hash falls at that index.
    /// @return relayersPerWindow The number of relayers that were selected to process transactions in the window
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

    /// @dev Distributes the transactions evenly b/w 'relayersPerWindow' selected relayers.
    /// @param _txHash Transaction hash of the transaction
    /// @param _relayersPerWindow The number of relayers that were selected to process transactions in the window
    /// @return The index of the relayer that should process the transaction
    function _getAllotedRelayerIndex(bytes32 _txHash, uint256 _relayersPerWindow) private pure returns (uint256) {
        return uint256(_txHash) % _relayersPerWindow;
    }

    /// @dev Verifies that the transaction was allocated to the relayer.
    /// @param _txHash Transaction hash of the transaction
    /// @param _relayerGenerationIterationBitmap see _getCalldataParams
    /// @param _relayersPerWindow see _getCalldataParams
    /// @return True if the transaction was allocated to the relayer, false otherwise
    function _verifyTransactionAllocation(
        bytes32 _txHash,
        uint256 _relayerGenerationIterationBitmap,
        uint256 _relayersPerWindow
    ) private pure returns (bool) {
        uint256 relayerIndex = _getAllotedRelayerIndex(_txHash, _relayersPerWindow);
        return (_relayerGenerationIterationBitmap >> relayerIndex) & 1 == 1;
    }

    /// @dev Given a list of transaction requests and a relayer address, returns the list of transactions that should be
    ///      processed by the relayer in the current window.
    ///      The function is expected to be called off-chain, and as such is not gas optimal
    /// @param _relayerAddress The address of the relayer
    /// @param _requests The list of transaction requests encoded as bytes each
    /// @param _currentState The active relayer state of the TA contract
    /// @return txnAllocated The list of transactions that should be processed by the relayer in the current window
    /// @return relayerGenerationIterations see _getCalldataParams
    /// @return selectedRelayerCdfIndex The index of the relayer in activeState.relayers
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

        // Filter the transactions
        uint256 length = _requests.length;
        txnAllocated = new bytes[](length);
        uint256 j;
        for (uint256 i; i != length;) {
            bytes32 txHash = _getTransactionHash(_requests[i]);
            uint256 relayerIndex = _getAllotedRelayerIndex(txHash, relayersAllocated.length);

            // If the transaction can be processed by this relayer, store it's info
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

        // Reduce the array size if needed
        uint256 extraLength = _requests.length - j;
        assembly {
            mstore(txnAllocated, sub(mload(txnAllocated), extraLength))
        }
    }

    /// @dev Application specific logic to get the transaction hash from the calldata.
    /// @param _calldata Calldata of the transaction
    /// @return Transaction hash
    function _getTransactionHash(bytes calldata _calldata) internal pure virtual returns (bytes32);
}
