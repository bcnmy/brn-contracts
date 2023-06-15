// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import "wormhole-contracts/interfaces/relayer/TypedUnits.sol";
import "ta-common/TATypes.sol";

struct ReceiptVAAPayload {
    uint256 deliveryVAASequenceNumber;
    WormholeChainId deliveryVAASourceChainId;
    RelayerAddress relayer;
}

type WormholeChainId is uint16;

function wormholeChainIdInequality(WormholeChainId a, WormholeChainId b) pure returns (bool) {
    return WormholeChainId.unwrap(a) != WormholeChainId.unwrap(b);
}

using {wormholeChainIdInequality as !=} for WormholeChainId global;
