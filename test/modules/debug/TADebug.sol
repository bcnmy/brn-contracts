// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import "./interfaces/ITADebug.sol";

import "src/transaction-allocator/common/TAHelpers.sol";

contract TADebug is ITADebug, TAHelpers {
    function increaseRewards(RelayerId _relayerId, TokenAddress _pool, uint256 _amount) external override {
        TADStorage storage ds = getTADStorage();
        ds.unclaimedRewards[_relayerId][_pool] += _amount;
    }

    function getExpectedRelayerId(RelayerAddress relayerAddress) external view override returns (RelayerId) {
        return _generateNewRelayerId(relayerAddress);
    }
}
