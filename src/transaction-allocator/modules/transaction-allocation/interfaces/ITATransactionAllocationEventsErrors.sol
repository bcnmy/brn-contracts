// SPDX-License-Identifier: MIT

pragma solidity 0.8.17;

import "src/structs/Transaction.sol";

interface ITATransactionAllocationEventsErrors {
    error NoRelayersRegistered();
    error InsufficientRelayersRegistered();
    error RelayerAllocationResultLengthMismatch(uint256 expectedLength, uint256 actualLength);
    error InvalidRelayerWindow();
    error GasLimitExceeded(uint256 gasLimit, uint256 gasUsed);
    error InvalidSignature(ForwardRequest request);
}