// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import "./interfaces/ITADebug.sol";

import "src/transaction-allocator/modules/delegation/TADelegationStorage.sol";
import "src/transaction-allocator/modules/relayer-management/TARelayerManagementStorage.sol";
import "src/transaction-allocator/modules/transaction-allocation/TATransactionAllocationStorage.sol";

contract TADebug is ITADebug, TADelegationStorage, TARelayerManagementStorage, TATransactionAllocationStorage {
    function increaseRewards(RelayerAddress _relayerAddress, TokenAddress _pool, uint256 _amount) external override {
        TADStorage storage ds = getTADStorage();
        ds.unclaimedRewards[_relayerAddress][_pool] += _amount;
    }
}
