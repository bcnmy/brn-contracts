// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import "src/transaction-allocator/common/TATypes.sol";

abstract contract TATransactionAllocationStorage {
    bytes32 internal constant TRANSACTION_ALLOCATION_STORAGE_SLOT = keccak256("TransactionAllocation.storage");

    struct TAStorage {
        mapping(uint256 epoch => mapping(RelayerAddress => uint256 transactionsSubmitted)) transactionsSubmitted;
        mapping(uint256 epoch => uint256 totalTransactionsSubmitted) totalTransactionsSubmitted;
        mapping(uint256 epoch => bool processed) livenessCheckProcessed;
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
