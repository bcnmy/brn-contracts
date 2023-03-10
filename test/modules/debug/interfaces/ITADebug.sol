// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import "src/transaction-allocator/common/TATypes.sol";

interface ITADebug {
    function increaseRewards(RelayerId _relayerId, TokenAddress _pool, uint256 _amount) external;

    function getExpectedRelayerId(RelayerAddress relayerAddress) external view returns (RelayerId);
}
