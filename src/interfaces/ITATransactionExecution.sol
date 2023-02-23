// SPDX-License-Identifier: MIT

pragma solidity 0.8.17;

import "./IDebug_GasConsumption.sol";

interface ITATransactionExecution is IDebug_GasConsumption {
    error InvalidRelayerWindow();
    error GasLimitExceeded(uint256 gasLimit, uint256 gasUsed);

    event RelayersPerWindowUpdated(uint256 relayersPerWindow);
}
