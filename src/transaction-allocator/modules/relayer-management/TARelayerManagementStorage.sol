// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

import "src/library/FixedPointArithmetic.sol";
import "src/library/VersionHistoryManager.sol";
import "src/transaction-allocator/common/TATypes.sol";
import "src/transaction-allocator/common/TAStructs.sol";

abstract contract TARelayerManagementStorage {
    bytes32 internal constant RELAYER_MANAGEMENT_STORAGE_SLOT = keccak256("RelayerManagement.storage");

    // TODO: Check packing
    struct RMStorage {
        // Config
        IERC20 bondToken;
        uint256 penaltyDelayBlocks;
        mapping(RelayerAddress => RelayerInfo) relayerInfo;
        // TODO: Dynamic?
        uint256 relayersPerWindow;
        uint256 blocksPerWindow;
        // cdf array hash
        VersionHistoryManager.Version[] cdfVersionHistoryManager;
        VersionHistoryManager.Version[] activeRelayerListVersionHistoryManager;
        bytes32 latestActiveRelayerStakeArrayHash;
        // Maps relayer address to pending withdrawals
        mapping(RelayerAddress => WithdrawalInfo) withdrawalInfo;
        mapping(TokenAddress => bool) isGasTokenSupported;
        // Constant Rate Rewards
        uint256 unpaidProtocolRewards;
        uint256 lastUnpaidRewardUpdatedTimestamp;
        FixedPointType totalShares;
        // Latest State. TODO: Verify if using these are safe or not.
        uint256 relayerCount;
        uint256 totalStake;
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
