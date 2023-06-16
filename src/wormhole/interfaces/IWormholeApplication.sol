// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import {IWormhole} from "wormhole-contracts/interfaces/IWormhole.sol";
import {IWormholeRelayerDelivery} from "wormhole-contracts/interfaces/relayer/IWormholeRelayerTyped.sol";

import "./IWormholeApplicationEventsErrors.sol";
import "./IBRNWormholeDeliveryProvider.sol";
import "./WormholeTypes.sol";
import "ta-base-application/interfaces/IApplicationBase.sol";

interface IWormholeApplication is IWormholeApplicationEventsErrors, IApplicationBase {
    function initializeWormholeApplication(IWormhole _wormhole, IWormholeRelayerDelivery _delivery) external;

    function executeWormhole(bytes[] memory encodedVMs, bytes memory encodedDeliveryVAA, bytes memory deliveryOverrides)
        external
        payable;

    function allocateWormholeDeliveryVAA(
        RelayerAddress _relayerAddress,
        bytes[] calldata _requests,
        RelayerState calldata _currentState
    ) external view returns (bytes[] memory, uint256, uint256);
}
