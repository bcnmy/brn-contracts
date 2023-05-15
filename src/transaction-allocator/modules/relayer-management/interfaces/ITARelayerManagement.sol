// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import "src/library/FixedPointArithmetic.sol";
import "src/transaction-allocator/common/TAConstants.sol";
import "src/interfaces/IDebug_GasConsumption.sol";
import "src/transaction-allocator/common/TAStructs.sol";
import "./ITARelayerManagementEventsErrors.sol";

interface ITARelayerManagement is IDebug_GasConsumption, ITARelayerManagementEventsErrors {
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

    function relayerInfo_Stake(RelayerAddress) external view returns (uint256);

    function relayerInfo_Endpoint(RelayerAddress) external view returns (string memory);

    function relayerInfo_isAccount(RelayerAddress, RelayerAccountAddress) external view returns (bool);

    function relayerInfo_delegatorPoolPremiumShare(RelayerAddress) external view returns (uint256);

    function isGasTokenSupported(TokenAddress) external view returns (bool);

    function relayersPerWindow() external view returns (uint256);

    function blocksPerWindow() external view returns (uint256);

    function latestActiveRelayerStakeArrayHash() external view returns (bytes32);

    function penaltyDelayBlocks() external view returns (uint256);

    function withdrawalInfo(RelayerAddress) external view returns (WithdrawalInfo memory);

    function bondTokenAddress() external view returns (TokenAddress);
}
