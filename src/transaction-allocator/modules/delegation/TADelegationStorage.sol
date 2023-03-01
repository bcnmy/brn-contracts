// SPDX-License-Identifier: MIT

pragma solidity 0.8.17;

abstract contract TADelegationStorage {
    bytes32 internal constant DELEGATION_STORAGE_SLOT = keccak256("Delegation.storage");

    struct DStorage {
        uint256 var1;
    }

    /* solhint-disable no-inline-assembly */
    function getDStorage() internal pure returns (DStorage storage ms) {
        bytes32 slot = DELEGATION_STORAGE_SLOT;
        assembly {
            ms.slot := slot
        }
    }
    /* solhint-enable no-inline-assembly */
}
