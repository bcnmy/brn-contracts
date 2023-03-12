// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import "./interfaces/ITADebug.sol";

import "src/transaction-allocator/common/TAHelpers.sol";

contract TADebug is ITADebug, TAHelpers {
    function increaseRewards(RelayerAddress _relayerAddress, TokenAddress _pool, uint256 _amount) external override {
        TADStorage storage ds = getTADStorage();
        ds.unclaimedRewards[_relayerAddress][_pool] += _amount;
    }
}
