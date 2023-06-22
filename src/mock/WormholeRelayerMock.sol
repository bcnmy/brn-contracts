// SPDX-License-Identifier: Apache 2

pragma solidity 0.8.19;

import "wormhole-contracts/relayer/wormholeRelayer/WormholeRelayer.sol";

contract WormholeRelayerMock is WormholeRelayer {
    constructor(address wormhole) WormholeRelayer(wormhole) {}
}
