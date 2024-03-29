// SPDX-License-Identifier: MIT

pragma solidity ^0.8.19;

import {RelayerAddress} from "ta-common/TATypes.sol";
import {RelayerStateManager} from "ta-common/RelayerStateManager.sol";
import "./IMinimalApplicationEventsErrors.sol";
import "ta-base-application/interfaces/IApplicationBase.sol";

interface IMinimalApplication is IMinimalApplicationEventsErrors, IApplicationBase {
    function count() external view returns (uint256);
    function executeMinimalApplication(bytes32 _data) external payable;
    function allocateMinimalApplicationTransaction(
        RelayerAddress _relayerAddress,
        bytes[] calldata _requests,
        RelayerStateManager.RelayerState calldata _currentState
    ) external view returns (bytes[] memory, uint256, uint256);
}
