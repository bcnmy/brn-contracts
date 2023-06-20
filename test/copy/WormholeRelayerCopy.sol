// SPDX-License-Identifier: Apache 2

pragma solidity 0.8.19;

import "wormhole-contracts/relayer/wormholeRelayer/WormholeRelayer.sol";

contract WormholeRelayerCopy is WormholeRelayer {
    constructor(address wormhole) WormholeRelayer(wormhole) {}
}
