// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

import "src/library/FixedPointArithmetic.sol";
import "src/library/VersionManager.sol";
import "ta-common/TATypes.sol";

abstract contract TARelayerManagementStorage {
    bytes32 internal constant RELAYER_MANAGEMENT_STORAGE_SLOT = keccak256("RelayerManagement.storage");

    // Relayer Information
    struct RelayerInfo {
        uint256 stake;
        string endpoint;
        uint256 delegatorPoolPremiumShare; // *100
        RelayerAccountAddress[] relayerAccountAddresses;
        mapping(RelayerAccountAddress => bool) isAccount;
        RelayerStatus status;
        uint256 minExitBlockNumber;
        // TODO: Reward share related data should be moved to it's own mapping
        uint256 unpaidProtocolRewards;
        FixedPointType rewardShares;
    }

    // TODO: Check packing
    struct RMStorage {
        // Config
        IERC20 bondToken;
        mapping(RelayerAddress => RelayerInfo) relayerInfo;
        // TODO: Dynamic?
        uint256 relayersPerWindow;
        uint256 blocksPerWindow;
        VersionManager.VersionManagerState relayerStateVersionManager;
        // Maps relayer address to pending withdrawals
        mapping(TokenAddress => bool isGasTokenSupported) isGasTokenSupported;
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
