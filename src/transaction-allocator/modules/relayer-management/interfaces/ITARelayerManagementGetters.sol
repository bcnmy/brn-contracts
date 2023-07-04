// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import {RelayerAddress, RelayerAccountAddress, TokenAddress, RelayerStatus} from "ta-common/TATypes.sol";
import {FixedPointType} from "src/library/FixedPointArithmetic.sol";

/// @title ITARelayerManagementGetters
interface ITARelayerManagementGetters {
    function relayerCount() external view returns (uint256);

    function totalStake() external view returns (uint256);

    struct RelayerInfoView {
        uint256 stake;
        string endpoint;
        uint256 delegatorPoolPremiumShare;
        RelayerStatus status;
        uint256 minExitTimestamp;
        uint256 unpaidProtocolRewards;
        FixedPointType rewardShares;
    }

    function relayerInfo(RelayerAddress) external view returns (RelayerInfoView memory);

    function relayerInfo_isAccount(RelayerAddress, RelayerAccountAddress) external view returns (bool);

    function relayersPerWindow() external view returns (uint256);

    function blocksPerWindow() external view returns (uint256);

    function bondTokenAddress() external view returns (TokenAddress);

    function jailTimeInSec() external view returns (uint256);

    function withdrawDelayInSec() external view returns (uint256);

    function absencePenaltyPercentage() external view returns (uint256);

    function minimumStakeAmount() external view returns (uint256);

    function relayerStateUpdateDelayInWindows() external view returns (uint256);

    function totalUnpaidProtocolRewards() external view returns (uint256);

    function lastUnpaidRewardUpdatedTimestamp() external view returns (uint256);

    function totalProtocolRewardShares() external view returns (FixedPointType);

    function baseRewardRatePerMinimumStakePerSec() external view returns (uint256);

    function getLatestCdfArray(RelayerAddress[] calldata _activeRelayers) external view returns (uint256[] memory);

    function relayerStateHash() external view returns (bytes32, bytes32);

    function protocolRewardRate() external view returns (uint256);
}
