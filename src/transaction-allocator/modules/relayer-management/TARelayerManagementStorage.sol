// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

import "src/library/FixedPointArithmetic.sol";
import "src/transaction-allocator/common/TATypes.sol";
import "src/transaction-allocator/common/TAStructs.sol";

abstract contract TARelayerManagementStorage {
    bytes32 internal constant RELAYER_MANAGEMENT_STORAGE_SLOT = keccak256("RelayerManagement.storage");

    // TODO: Check packing
    struct RMStorage {
        // Config
        IERC20 bondToken;
        uint256 penaltyDelayBlocks;
        // No of registered relayers
        uint256 relayerCount;
        mapping(RelayerAddress => RelayerInfo) relayerInfo;
        mapping(uint256 => RelayerAddress) relayerIndexToRelayerAddress;
        uint256 totalStake;
        // TODO: Dynamic?
        uint256 relayersPerWindow;
        uint256 blocksPerWindow;
        // cdf array hash
        CdfHashUpdateInfo[] cdfHashUpdateLog;
        bytes32 stakeArrayHash;
        /// Maps relayer address to pending withdrawals
        mapping(RelayerAddress => WithdrawalInfo) withdrawalInfo;
        mapping(TokenAddress => bool) isGasTokenSupported;
        // Constant Rate Rewards
        uint256 unpaidProtocolRewards;
        uint256 lastUnpaidRewardUpdatedTimestamp;
        FixedPointType totalShares;
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
