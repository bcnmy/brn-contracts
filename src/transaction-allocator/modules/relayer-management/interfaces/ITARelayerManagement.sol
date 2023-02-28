// SPDX-License-Identifier: MIT

pragma solidity 0.8.17;

import "src/interfaces/IDebug_GasConsumption.sol";
import "./ITARelayerManagementEventsErrors.sol";
import "src/structs/TAStructs.sol";

interface ITARelayerManagement is IDebug_GasConsumption, ITARelayerManagementEventsErrors {
    function getStakeArray() external view returns (uint32[] memory);

    function getCdf() external view returns (uint16[] memory);

    function register(
        uint32[] calldata _previousStakeArray,
        uint256 _stake,
        address[] calldata _accounts,
        string memory _endpoint
    ) external;

    function unRegister(uint32[] calldata _previousStakeArray) external;

    function withdraw() external;

    function processAbsenceProof(
        uint16[] calldata _reporter_cdf,
        uint256 _reporter_cdfIndex,
        uint256[] calldata _reporter_relayerGenerationIterations,
        address _absentee_relayerAddress,
        uint256 _absentee_blockNumber,
        uint256 _absentee_latestStakeUpdationCdfLogIndex,
        uint16[] calldata _absentee_cdf,
        uint256[] calldata _absentee_relayerGenerationIterations,
        uint256 _absentee_cdfIndex,
        uint32[] calldata _currentStakeArray
    ) external;

    function relayerCount() external view returns (uint256);

    function relayerInfo_Stake(address) external view returns (uint256);

    function relayerInfo_Endpoint(address) external view returns (string memory);

    function relayerInfo_Index(address) external view returns (uint256);

    function relayerInfo_isAccount(address, address) external view returns (bool);

    function relayersPerWindow() external view returns (uint256);

    function blocksPerWindow() external view returns (uint256);

    function cdfHashUpdateLog(uint256) external view returns (CdfHashUpdateInfo memory);

    function stakeArrayHash() external view returns (bytes32);

    function penaltyDelayBlocks() external view returns (uint256);

    function withdrawalInfo(address) external view returns (WithdrawalInfo memory);

    function withdrawDelay() external view returns (uint256);

    function setRelayerAccountsStatus(address[] calldata _accounts, bool[] calldata _status) external;
}
