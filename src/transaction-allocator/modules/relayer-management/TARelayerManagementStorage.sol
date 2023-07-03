// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import {IERC20} from "openzeppelin-contracts/token/ERC20/IERC20.sol";

import {FixedPointType} from "src/library/FixedPointArithmetic.sol";
import {VersionManager} from "src/library/VersionManager.sol";
import {RelayerAddress, RelayerAccountAddress, RelayerStatus, TokenAddress} from "ta-common/TATypes.sol";

/// @title TARelayerManagementStorage
abstract contract TARelayerManagementStorage {
    bytes32 internal constant RELAYER_MANAGEMENT_STORAGE_SLOT = keccak256("RelayerManagement.storage");

    /// @dev Struct for storing relayer information.
    /// @custom:member stake The amount of stake the relayer has in bond token (BICO).
    /// @custom:member endpoint The rpc endpoint of the relayer.
    /// @custom:member isAccount A mapping of relayer account addresses to whether they are a relayer account.
    ///                          A relayer account can submit transactions on behalf of the relayer.
    /// @custom:member status The status of the relayer.
    /// @custom:member minExitTimestamp If status == Jailed, the minimum timestamp after which the relayer can exit jail.
    ///                                 If status == Exiting, the timestamp after which the relayer can withdraw their stake.
    /// @custom:member delegatorPoolPremiumShare The percentage of the relayer protocol rewards the delegators receive.
    /// @custom:member unpaidProtocolRewards The amount of protocol rewards for the relayer that have been accounted for but not yet claimed.
    /// @custom:member rewardShares The amount of protocol rewards shares that have been minted for the relayer.
    struct RelayerInfo {
        uint256 stake;
        string endpoint;
        mapping(RelayerAccountAddress => bool) isAccount;
        RelayerStatus status;
        uint256 minExitTimestamp;
        uint256 delegatorPoolPremiumShare;
        uint256 unpaidProtocolRewards;
        FixedPointType rewardShares;
    }

    /// @dev The storage struct for the RelayerManagement module.
    struct RMStorage {
        ////////////////////////// Configuration Parameters //////////////////////////
        IERC20 bondToken;
        mapping(RelayerAddress => RelayerInfo) relayerInfo;
        uint256 relayersPerWindow;
        uint256 blocksPerWindow;
        uint256 jailTimeInSec;
        uint256 withdrawDelayInSec;
        uint256 absencePenaltyPercentage;
        uint256 minimumStakeAmount;
        uint256 relayerStateUpdateDelayInWindows;
        uint256 baseRewardRatePerMinimumStakePerSec;
        ////////////////////////// Relayer State Management //////////////////////////
        VersionManager.VersionManagerState relayerStateVersionManager;
        ////////////////////////// Constant Rate Rewards //////////////////////////
        uint256 totalUnpaidProtocolRewards;
        uint256 lastUnpaidRewardUpdatedTimestamp;
        FixedPointType totalProtocolRewardShares;
        ////////////////////////// Global counters for the "latest" state //////////////////////////
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
