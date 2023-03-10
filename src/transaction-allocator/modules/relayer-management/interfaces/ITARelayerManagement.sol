// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import "src/transaction-allocator/common/TAConstants.sol";
import "src/interfaces/IDebug_GasConsumption.sol";
import "src/transaction-allocator/common/TAStructs.sol";
import "./ITARelayerManagementEventsErrors.sol";

interface ITARelayerManagement is IDebug_GasConsumption, ITARelayerManagementEventsErrors {
    function getStakeArray() external view returns (uint32[] memory);

    function getCdfArray() external view returns (uint16[] memory);

    function register(
        uint32[] calldata _previousStakeArray,
        uint32[] calldata _currentDelegationArray,
        uint256 _stake,
        RelayerAccountAddress[] calldata _accounts,
        string memory _endpoint
    ) external returns (RelayerId);

    function unRegister(
        uint32[] calldata _previousStakeArray,
        uint32[] calldata _currentDelegationArray,
        RelayerId _relayerId
    ) external;

    function withdraw(RelayerId _relayerId) external;

    function processAbsenceProof(
        AbsenceProofReporterData calldata _reporterData,
        AbsenceProofAbsenteeData calldata _absenteeData,
        uint32[] calldata _currentStakeArray,
        uint32[] calldata _currentDelegationArray
    ) external;

    function relayerCount() external view returns (uint256);

    function relayerInfo_Stake(RelayerId) external view returns (uint256);

    function relayerInfo_Endpoint(RelayerId) external view returns (string memory);

    function relayerInfo_Index(RelayerId) external view returns (uint256);

    function relayerInfo_isAccount(RelayerId, RelayerAccountAddress) external view returns (bool);

    function relayerInfo_isGasTokenSupported(RelayerId, TokenAddress) external view returns (bool);

    function relayerInfo_RelayerAddress(RelayerId) external view returns (RelayerAddress);

    function relayersPerWindow() external view returns (uint256);

    function blocksPerWindow() external view returns (uint256);

    function cdfHashUpdateLog(uint256) external view returns (CdfHashUpdateInfo memory);

    function stakeArrayHash() external view returns (bytes32);

    function penaltyDelayBlocks() external view returns (uint256);

    function withdrawalInfo(RelayerId) external view returns (WithdrawalInfo memory);

    function withdrawDelay() external view returns (uint256);

    function setRelayerAccountsStatus(
        RelayerId _relayerId,
        RelayerAccountAddress[] calldata _accounts,
        bool[] calldata _status
    ) external;

    function addSupportedGasTokens(RelayerId _relayerId, TokenAddress[] calldata _tokens) external;

    function removeSupportedGasTokens(RelayerId _relayerId, TokenAddress[] calldata _tokens) external;

    function bondTokenAddress() external view returns (TokenAddress);
}
