// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import {
    Gas,
    TargetNative,
    LocalNative,
    GasPrice,
    WeiPrice,
    Wei
} from "wormhole-contracts/interfaces/relayer/TypedUnits.sol";
import {IWormholeRelayer, VaaKey} from "wormhole-contracts/interfaces/relayer/IWormholeRelayerTyped.sol";

import {RelayerAddress} from "ta-common/TATypes.sol";

/// @dev The structure defining the payload used to prove "the execution of a delivery request on the destination chain" on the source chain.
/// @custom:member relayerAddress The address of the relayer that executed the delivery request.
/// @custom:member deliveryVAAKey The VAA key of the delivery VAA that was executed.
struct ReceiptVAAPayload {
    RelayerAddress relayerAddress;
    VaaKey deliveryVAAKey;
}

type WormholeChainId is uint16;

function wormholeChainIdEquality(WormholeChainId a, WormholeChainId b) pure returns (bool) {
    return WormholeChainId.unwrap(a) == WormholeChainId.unwrap(b);
}

function wormholeChainIdInequality(WormholeChainId a, WormholeChainId b) pure returns (bool) {
    return WormholeChainId.unwrap(a) != WormholeChainId.unwrap(b);
}

using {wormholeChainIdInequality as !=, wormholeChainIdEquality as ==} for WormholeChainId global;
