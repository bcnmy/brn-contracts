// SPDX-License-Identifier: MIT

pragma solidity 0.8.17;

interface ITARelayerManagementEventsErrors {
    error NoAccountsProvided();
    error InsufficientStake(uint256 stake, uint256 minimumStake);
    // TODO: Verify these parameters
    error InvalidWithdrawal(uint256 amount, uint256 currentTime, uint256 minValidTime, uint256 maxValidTime);
    error InvalidRelayerWindowForReporter();
    error InvalidAbsenteeBlockNumber();
    error InvalidAbsenteeCdfArrayHash();
    error InvalidRelayerWindowForAbsentee();
    error AbsenteeWasPresent(uint256 absenteeWindowId);
    error ReporterTransferFailed(address reporter, uint256 amount);
    error ParameterLengthMismatch();
    error InvalidRelayer(address relayer);

    event StakeArrayUpdated(bytes32 indexed stakePercArrayHash);
    event CdfArrayUpdated(bytes32 indexed cdfArrayHash);
    event RelayerRegistered(
        address indexed relayer, string indexed endpoint, address[] accounts, uint256 indexed stake
    );
    event RelayerAccountsUpdated(address indexed relayer, address[] indexed _accounts, bool[] indexed _status);
    event RelayerUnRegistered(address indexed relayer);
    event Withdraw(address indexed relayer, uint256 amount);
    event AbsenceProofProcessed(
        uint256 indexed windowId,
        address indexed reporter,
        address indexed absentRelayer,
        uint256 absenceWindowId,
        uint256 penalty
    );
}
