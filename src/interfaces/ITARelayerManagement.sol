// SPDX-License-Identifier: MIT

pragma solidity 0.8.17;

import "./IDebug_GasConsumption.sol";

interface ITARelayerManagement is IDebug_GasConsumption {
    error NoAccountsProvided();
    error InsufficientStake(uint256 stake, uint256 minimumStake);
    error InvalidWithdrawal(uint256 amount, uint256 currentTime, uint256 minValidTime, uint256 maxValidTime);
    error InvalidRelayerWindowForReporter();
    error InvalidAbsenteeBlockNumber();
    error InvalidAbsenteeCdfArrayHash();
    error InvalidRelayeWindowForAbsentee();
    error AbsenteeWasPresent(uint256 absenteeWindowId);
    error ReporterTransferFailed(address reporter, uint256 amount);

    event StakeArrayUpdated(bytes32 indexed stakePercArrayHash);
    event CdfArrayUpdated(bytes32 indexed cdfArrayHash);
    event RelayerRegistered(address indexed relayer, string endpoint, address[] accounts, uint256 stake);
    event RelayerUnRegistered(address indexed relayer);
    event Withdraw(address indexed relayer, uint256 amount);
    event AbsenceProofProcessed(
        uint256 indexed windowId,
        address indexed reporter,
        address indexed absentRelayer,
        uint256 absenceWindowId,
        uint256 penalty
    );

    function getStakeArray() external view returns (uint32[] memory);

    function getCdf() external view returns (uint16[] memory);

    function register(
        uint32[] calldata _previousStakeArray,
        uint256 _stake,
        address[] calldata _accounts,
        string memory _endpoint
    ) external;

    function unRegister(uint32[] calldata _previousStakeArray) external;

    function withdraw(address relayer) external;

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
}
