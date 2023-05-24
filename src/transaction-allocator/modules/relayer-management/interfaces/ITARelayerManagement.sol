// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import "src/library/FixedPointArithmetic.sol";
import "src/transaction-allocator/common/TAConstants.sol";
import "src/interfaces/IDebug_GasConsumption.sol";

import "./ITARelayerManagementEventsErrors.sol";

interface ITARelayerManagement is IDebug_GasConsumption, ITARelayerManagementEventsErrors {
    function getLatestCdfArray(RelayerAddress[] calldata _activeRelayers) external view returns (uint16[] memory);

    ////////////////////////// Relayer Registration //////////////////////////
    function register(
        RelayerState calldata _latestState,
        uint256 _stake,
        RelayerAccountAddress[] calldata _accounts,
        string memory _endpoint,
        uint256 _delegatorPoolPremiumShare
    ) external;

    function unRegister(RelayerState calldata _latestState, uint256 _relayerIndex) external;

    function withdraw() external;

    function setRelayerAccounts(RelayerAccountAddress[] calldata _accounts) external;

    ////////////////////////// Constant Rate Rewards //////////////////////////
    function claimProtocolReward() external;

    ////////////////////// Getters //////////////////////
    function relayerCount() external view returns (uint256);

    struct RelayerInfoView {
        uint256 stake;
        string endpoint;
        uint256 delegatorPoolPremiumShare;
        RelayerAccountAddress[] relayerAccountAddresses;
        RelayerStatus status;
        uint256 minExitBlockNumber;
        uint256 unpaidProtocolRewards;
        FixedPointType rewardShares;
    }

    function relayerInfo(RelayerAddress) external view returns (RelayerInfoView memory);

    function relayerInfo_isAccount(RelayerAddress, RelayerAccountAddress) external view returns (bool);

    function isGasTokenSupported(TokenAddress) external view returns (bool);

    function relayersPerWindow() external view returns (uint256);

    function blocksPerWindow() external view returns (uint256);

    function bondTokenAddress() external view returns (TokenAddress);
}
