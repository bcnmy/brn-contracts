// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import "openzeppelin-contracts/contracts/utils/math/SafeMath.sol";
import "src/library/FixedPointArithmetic.sol";
import "src/transaction-allocator/common/TATypes.sol";

abstract contract TADelegationStorage {
    bytes32 internal constant DELEGATION_STORAGE_SLOT = keccak256("Delegation.storage");

    struct TADStorage {
        mapping(RelayerId => uint256) totalDelegation;
        mapping(RelayerId => mapping(DelegatorAddress => uint256)) delegation;
        mapping(RelayerId => mapping(DelegatorAddress => mapping(TokenAddress => FixedPointType))) shares;
        mapping(RelayerId => mapping(TokenAddress => FixedPointType)) totalShares;
        // TODO: Add C*Time
        mapping(RelayerId => mapping(TokenAddress => uint256)) unclaimedRewards;
        bytes32 delegationArrayHash;
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
