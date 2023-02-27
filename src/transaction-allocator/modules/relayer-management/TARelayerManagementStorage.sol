// SPDX-License-Identifier: MIT

pragma solidity 0.8.17;

import "src/structs/TAStructs.sol";

contract TARelayerManagementStorage {
    bytes32 internal constant RELAYER_MANAGEMENT_STORAGE_SLOT = keccak256("RelayerManagement.storage");

    struct RMStorage {
        // No of registered relayers
        uint256 relayerCount;
        /// Maps relayer main address to info
        mapping(address => RelayerInfo) relayerInfo;
        // Relayer Index to Relayer
        mapping(uint256 => address) relayerIndexToRelayer;
        // random number of realyers selected per window
        uint256 relayersPerWindow;
        /// blocks per node
        uint256 blocksPerWindow;
        // cdf array hash
        CdfHashUpdateInfo[] cdfHashUpdateLog;
        // stake array hash
        bytes32 stakeArrayHash;
        // -------Transaction Allocator State-------
        uint256 penaltyDelayBlocks;
        /// Maps relayer address to pending withdrawals
        mapping(address => WithdrawalInfo) withdrawalInfo;
        // unbounding period
        uint256 withdrawDelay;
    }

    /* solhint-disable no-inline-assembly */
    function getRMStorage() internal pure returns (RMStorage storage ms) {
        bytes32 slot = RELAYER_MANAGEMENT_STORAGE_SLOT;
        assembly {
            ms.slot := slot
        }
    }

    /* solhint-enable no-inline-assembly */
}
