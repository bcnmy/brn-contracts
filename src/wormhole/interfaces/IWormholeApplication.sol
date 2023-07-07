// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import {IWormhole} from "wormhole-contracts/interfaces/IWormhole.sol";
import {IWormholeRelayerDelivery} from "wormhole-contracts/interfaces/relayer/IWormholeRelayerTyped.sol";

import {IWormholeApplicationEventsErrors} from "./IWormholeApplicationEventsErrors.sol";
import {RelayerAddress} from "ta-common/TATypes.sol";
import {RelayerStateManager} from "ta-common/RelayerStateManager.sol";
import {IApplicationBase} from "ta-base-application/interfaces/IApplicationBase.sol";

/// @title IWormholeApplication
interface IWormholeApplication is IWormholeApplicationEventsErrors, IApplicationBase {
    /// @notice Initialize the configuration on the wormhole application module.
    /// @param _wormhole The Wormhole Core Bridge contract.
    /// @param _delivery The Wormhole Relayer Delivery contract.
    function initializeWormholeApplication(IWormhole _wormhole, IWormholeRelayerDelivery _delivery) external;

    /// @notice Execute a wormhole relayer delivery. This is the primary entrypoint for all wormhole message execution.
    /// @param encodedVMs The encoded VMs corresponding to the DeliveryVAA.
    /// @param encodedDeliveryVAA The DeliveryVAA which contains the delivery instructions to execute.
    /// @param deliveryOverrides The delivery overrides to apply to the delivery.
    function executeWormhole(bytes[] memory encodedVMs, bytes memory encodedDeliveryVAA, bytes memory deliveryOverrides)
        external
        payable;

    /// @notice A helper function to return a list of calldata(executeWormhole()) that can be executed by the relayer.
    /// @param _relayerAddress The relayer address executing the delivery.
    /// @param _requests The list of calldata(executeWormhole()) that can be executed by the relayer.
    /// @param _currentState The current relayer state against which relayer selection is done.
    /// @return The list of calldata(executeWormhole()) that can be executed by the relayer.
    /// @return relayerGenerationIterationBitmap
    /// @return relayerIndex
    function allocateWormholeDeliveryVAA(
        RelayerAddress _relayerAddress,
        bytes[] calldata _requests,
        RelayerStateManager.RelayerState calldata _currentState
    ) external view returns (bytes[] memory, uint256, uint256);
}
