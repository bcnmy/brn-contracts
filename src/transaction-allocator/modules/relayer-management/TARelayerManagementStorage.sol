// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import "src/transaction-allocator/common/TATypes.sol";
import "src/transaction-allocator/common/TAStructs.sol";

abstract contract TARelayerManagementStorage {
    bytes32 internal constant RELAYER_MANAGEMENT_STORAGE_SLOT = keccak256("RelayerManagement.storage");

    // TODO: Check packing
    struct RMStorage {
        // Config
        IERC20 bondToken;
        uint256 penaltyDelayBlocks;
        uint256 withdrawDelay;
        // No of registered relayers
        uint256 relayerCount;
        mapping(RelayerId => RelayerInfo) relayerInfo;
        mapping(uint256 => RelayerId) relayerIndexToRelayer;
        // TODO: Dynamic?
        uint256 relayersPerWindow;
        uint256 blocksPerWindow;
        // cdf array hash
        CdfHashUpdateInfo[] cdfHashUpdateLog;
        bytes32 stakeArrayHash;
        /// Maps relayer address to pending withdrawals
        mapping(RelayerId => WithdrawalInfo) withdrawalInfo;
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
