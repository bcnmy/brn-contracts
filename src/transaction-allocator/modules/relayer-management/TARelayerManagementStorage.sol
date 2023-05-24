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
        // Info
        uint256 stake;
        string endpoint;
        RelayerAccountAddress[] relayerAccountAddresses;
        mapping(RelayerAccountAddress => bool) isAccount;
        // Relayer Status
        RelayerStatus status;
        uint256 minExitTimestamp;
        uint256 jailedUntilTimestamp;
        // TODO: Reward share related data should be moved to it's own mapping
        // Delegation
        uint256 delegatorPoolPremiumShare; // *100
        uint256 unpaidProtocolRewards;
        FixedPointType rewardShares;
    }

    struct RMStorage {
        // Config
        IERC20 bondToken;
        mapping(RelayerAddress => RelayerInfo) relayerInfo;
        uint256 relayersPerWindow;
        uint256 blocksPerWindow;
        uint256 jailTimeInSec;
        uint256 withdrawDelayInSec;
        uint256 absencePenaltyPercentage;
        uint256 minimumStakeAmount;
        uint256 relayerStateUpdateDelayInWindows;
        // Relayer State Management
        VersionManager.VersionManagerState relayerStateVersionManager;
        // Maps relayer address to pending withdrawals
        mapping(TokenAddress => bool isGasTokenSupported) isGasTokenSupported;
        // Constant Rate Rewards
        uint256 unpaidProtocolRewards;
        uint256 lastUnpaidRewardUpdatedTimestamp;
        FixedPointType totalShares;
        // Latest State.
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
