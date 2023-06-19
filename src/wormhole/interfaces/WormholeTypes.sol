// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import "wormhole-contracts/interfaces/relayer/TypedUnits.sol";
import {IWormholeRelayer, VaaKey} from "wormhole-contracts/interfaces/relayer/IWormholeRelayerTyped.sol";

import "ta-common/TATypes.sol";

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
