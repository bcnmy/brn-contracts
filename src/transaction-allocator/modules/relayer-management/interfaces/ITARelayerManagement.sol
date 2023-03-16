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
        string memory _endpoint,
        uint256 _delegatorPoolPremiumShare
    ) external returns (RelayerAddress);

    function unRegister(uint32[] calldata _previousStakeArray, uint32[] calldata _currentDelegationArray) external;

    function withdraw() external;

    function processAbsenceProof(
        AbsenceProofReporterData calldata _reporterData,
        AbsenceProofAbsenteeData calldata _absenteeData,
        uint32[] calldata _currentStakeArray,
        uint32[] calldata _currentDelegationArray
    ) external;

    function setRelayerAccountsStatus(RelayerAccountAddress[] calldata _accounts) external;

    ////////////////////// Getters //////////////////////

    function relayerCount() external view returns (uint256);

    function relayerInfo_Stake(RelayerAddress) external view returns (uint256);

    function relayerInfo_Endpoint(RelayerAddress) external view returns (string memory);

    function relayerInfo_Index(RelayerAddress) external view returns (uint256);

    function relayerInfo_isAccount(RelayerAddress, RelayerAccountAddress) external view returns (bool);

    function relayerInfo_delegatorPoolPremiumShare(RelayerAddress) external view returns (uint256);

    function isGasTokenSupported(TokenAddress) external view returns (bool);

    function relayersPerWindow() external view returns (uint256);

    function blocksPerWindow() external view returns (uint256);

    function cdfHashUpdateLog(uint256) external view returns (CdfHashUpdateInfo memory);

    function stakeArrayHash() external view returns (bytes32);

    function penaltyDelayBlocks() external view returns (uint256);

    function withdrawalInfo(RelayerAddress) external view returns (WithdrawalInfo memory);

    function bondTokenAddress() external view returns (TokenAddress);

    function getRelayerIndexUpdationLog(uint256 _index)
        external
        view
        returns (RelayerIndexToRelayerUpdateInfo[] memory);
}
