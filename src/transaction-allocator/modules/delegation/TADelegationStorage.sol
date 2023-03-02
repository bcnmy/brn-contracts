// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import "src/transaction-allocator/common/TATypes.sol";

abstract contract TADelegationStorage {
    bytes32 internal constant DELEGATION_STORAGE_SLOT = keccak256("Delegation.storage");

    struct TADStorage {
        mapping(RelayerAddress => uint256) totalDelegation;
        mapping(RelayerAddress => mapping(DelegatorAddress => uint256)) delegations;
        mapping(RelayerAddress => mapping(address => uint256)) unclaimedRewards;
    }

    /* solhint-disable no-inline-assembly */
    function getTADStorage() internal pure returns (TADStorage storage ms) {
        bytes32 slot = DELEGATION_STORAGE_SLOT;
        assembly {
            ms.slot := slot
        }
    }
    /* solhint-enable no-inline-assembly */
}
