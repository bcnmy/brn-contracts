// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import "./ITARelayerManagementEventsErrors.sol";
import "src/library/FixedPointArithmetic.sol";

interface ITARelayerManagement is ITARelayerManagementEventsErrors {
    function getLatestCdfArray(RelayerAddress[] calldata _activeRelayers) external view returns (uint16[] memory);

    ////////////////////////// Relayer Registration //////////////////////////
    function register(
        RelayerState calldata _latestState,
        uint256 _stake,
        RelayerAccountAddress[] calldata _accounts,
        string memory _endpoint,
        uint256 _delegatorPoolPremiumShare
    ) external;

    function unregister(RelayerState calldata _latestState, uint256 _relayerIndex) external;

    function registerFoundationRelayer(
        RelayerAddress _foundationRelayerAddress,
        uint256 _stake,
        RelayerAccountAddress[] calldata _accounts,
        string calldata _endpoint,
        uint256 _delegatorPoolPremiumShare
    ) external;

    function withdraw(RelayerAccountAddress[] calldata _relayerAccountsToRemove) external;

    function unjailAndReenter(RelayerState calldata _latestState, uint256 _stake) external;

    function setRelayerAccountsStatus(RelayerAccountAddress[] calldata _accounts, bool[] calldata _status) external;

    ////////////////////////// Protocol Rewards //////////////////////////
    function claimProtocolReward() external;

    function relayerClaimableProtocolRewards(RelayerAddress _relayerAddress) external view returns (uint256);

    function protocolRewardRate() external view returns (uint256);

    ////////////////////// Getters //////////////////////
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

    function isGasTokenSupported(TokenAddress) external view returns (bool);

    function relayersPerWindow() external view returns (uint256);

    function blocksPerWindow() external view returns (uint256);

    function bondTokenAddress() external view returns (TokenAddress);

    function jailTimeInSec() external view returns (uint256);

    function withdrawDelayInSec() external view returns (uint256);

    function absencePenaltyPercentage() external view returns (uint256);

    function minimumStakeAmount() external view returns (uint256);

    function relayerStateUpdateDelayInWindows() external view returns (uint256);

    function relayerStateHash() external view returns (bytes32, bytes32);

    function totalUnpaidProtocolRewards() external view returns (uint256);

    function lastUnpaidRewardUpdatedTimestamp() external view returns (uint256);

    function totalProtocolRewardShares() external view returns (FixedPointType);

    function baseRewardRatePerMinimumStakePerSec() external view returns (uint256);
}
