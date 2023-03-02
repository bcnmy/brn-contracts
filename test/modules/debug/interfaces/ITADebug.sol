// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import "src/transaction-allocator/common/TATypes.sol";

interface ITADebug {
    function increaseRewards(RelayerAddress _relayerAddress, TokenAddress _pool, uint256 _amount) external;
}
