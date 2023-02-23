// SPDX-License-Identifier: MIT

pragma solidity 0.8.17;

import "./IDebug_GasConsumption.sol";
import "../structs/Transaction.sol";

interface ITATransactionExecution is IDebug_GasConsumption {
    error InvalidRelayerWindow();
    error GasLimitExceeded(uint256 gasLimit, uint256 gasUsed);

    event RelayersPerWindowUpdated(uint256 relayersPerWindow);

    function execute(
        ForwardRequest[] calldata _reqs,
        uint16[] calldata _cdf,
        uint256[] calldata _relayerGenerationIterations,
        uint256 _cdfIndex
    ) external payable returns (bool[] memory, bytes[] memory);
}
