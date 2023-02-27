// SPDX-License-Identifier: MIT

pragma solidity 0.8.17;

import "src/structs/TAStructs.sol";

contract TATransactionAllocationStorage {
    bytes32 internal constant TRANSACTION_ALLOCATION_STORAGE_SLOT = keccak256("TransactionAllocation.storage");

    struct TAStorage {
        // attendance: windowIndex -> relayer -> wasPresent?
        mapping(uint256 => mapping(address => bool)) attendance;
    }

    /* solhint-disable no-inline-assembly */
    function getTAStorage() internal pure returns (TAStorage storage ms) {
        bytes32 slot = TRANSACTION_ALLOCATION_STORAGE_SLOT;
        assembly {
            ms.slot := slot
        }
    }
    /* solhint-enable no-inline-assembly */
}
