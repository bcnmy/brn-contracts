// SPDX-License-Identifier: MIT

pragma solidity ^0.8.19;

import "./IMinimalApplicationEventsErrors.sol";
import "ta-base-application/interfaces/IApplicationBase.sol";

interface IMinimalApplication is IMinimalApplicationEventsErrors, IApplicationBase {
    function count() external view returns (uint256);
    function executeMinimalApplication(bytes32 _data) external payable;
    function allocateMinimalApplicationTransaction(
        RelayerAddress _relayerAddress,
        bytes[] calldata _requests,
        RelayerState calldata _currentState
    ) external returns (bytes[] memory, uint256, uint256);
}
