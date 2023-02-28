// SPDX-License-Identifier: MIT

pragma solidity 0.8.17;

interface ITATransactionAllocationEventsErrors {
    error NoRelayersRegistered();
    error InsufficientRelayersRegistered();
    error RelayerAllocationResultLengthMismatch(uint256 expectedLength, uint256 actualLength);
    error InvalidRelayerWindow();
    error GasLimitExceeded(uint256 gasLimit, uint256 gasUsed);

    event RelayersPerWindowUpdated(uint256 relayersPerWindow);
}
