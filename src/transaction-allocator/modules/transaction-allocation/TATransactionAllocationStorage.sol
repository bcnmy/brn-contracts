// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import {RelayerAddress} from "ta-common/TATypes.sol";
import {FixedPointType} from "src/library/FixedPointArithmetic.sol";

/// @title TATransactionAllocationStorage
abstract contract TATransactionAllocationStorage {
    bytes32 internal constant TRANSACTION_ALLOCATION_STORAGE_SLOT = keccak256("TransactionAllocation.storage");

    struct TAStorage {
        ////////////////////////// Configuration Parameters //////////////////////////
        uint256 epochLengthInSec;
        uint256 epochEndTimestamp;
        FixedPointType livenessZParameter;
        uint256 stakeThresholdForJailing;
        ////////////////////////// Liveness Records //////////////////////////
        mapping(uint256 epochEndTimestamp => mapping(RelayerAddress => uint256 transactionsSubmitted))
            transactionsSubmitted;
        ////////////////////////// Misc //////////////////////////
        mapping(RelayerAddress => uint256 lastTransactionSubmissionWindow) lastTransactionSubmissionWindow;
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
