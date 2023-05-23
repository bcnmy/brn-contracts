// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import "src/library/FixedPointArithmetic.sol";
import "src/transaction-allocator/common/TAConstants.sol";
import "src/interfaces/IDebug_GasConsumption.sol";
import "src/transaction-allocator/common/TAStructs.sol";
import "./ITARelayerManagementEventsErrors.sol";

interface ITARelayerManagement is IDebug_GasConsumption, ITARelayerManagementEventsErrors {
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

    function getStakeArray(RelayerAddress[] calldata _activeRelayers) external view returns (uint32[] memory);

    function getCdfArray(RelayerAddress[] calldata _activeRelayers) external view returns (uint16[] memory);

    ////////////////////////// Relayer Registration //////////////////////////
    function register(
        uint32[] calldata _previousStakeArray,
        uint32[] calldata _currentDelegationArray,
        RelayerAddress[] calldata _activeRelayers,
        uint256 _stake,
        RelayerAccountAddress[] calldata _accounts,
        string memory _endpoint,
        uint256 _delegatorPoolPremiumShare
    ) external;

    function unRegister(
        uint32[] calldata _previousStakeArray,
        uint32[] calldata _currentDelegationArray,
        RelayerAddress[] calldata _activeRelayers,
        uint256 _relayerIndex
    ) external;

    function withdraw() external;

    function setRelayerAccounts(RelayerAccountAddress[] calldata _accounts) external;

    ////////////////////////// Constant Rate Rewards //////////////////////////
    function claimProtocolReward() external;

    ////////////////////// Getters //////////////////////
    function relayerCount() external view returns (uint256);

    function relayerInfo(RelayerAddress) external view returns (RelayerInfoView memory);

    function isGasTokenSupported(TokenAddress) external view returns (bool);

    function relayersPerWindow() external view returns (uint256);

    function blocksPerWindow() external view returns (uint256);

    function latestActiveRelayerStakeArrayHash() external view returns (bytes32);

    function bondTokenAddress() external view returns (TokenAddress);
}
