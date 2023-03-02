// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import "src/transaction-allocator/common/TATypes.sol";

interface ITARelayerManagementEventsErrors {
    error NoAccountsProvided();
    error InsufficientStake(uint256 stake, uint256 minimumStake);
    error InvalidWithdrawal(uint256 amount, uint256 currentTime, uint256 minValidTime);
    error InvalidRelayerWindowForReporter();
    error InvalidAbsenteeBlockNumber();
    error InvalidAbsenteeCdfArrayHash();
    error InvalidRelayerWindowForAbsentee();
    error AbsenteeWasPresent(uint256 absenteeWindowId);
    error ReporterTransferFailed(RelayerAccountAddress reporter, uint256 amount);
    error ParameterLengthMismatch();
    error InvalidRelayer(RelayerAddress relayer);
    error GasTokenAlreadySupported(TokenAddress token);
    error GasTokenNotSupported(TokenAddress token);

    event StakeArrayUpdated(bytes32 indexed stakePercArrayHash);
    event CdfArrayUpdated(bytes32 indexed cdfArrayHash);
    event RelayerRegistered(
        RelayerAddress indexed relayer, string indexed endpoint, RelayerAccountAddress[] accounts, uint256 indexed stake
    );
    event RelayerAccountsUpdated(
        RelayerAddress indexed relayer, RelayerAccountAddress[] indexed _accounts, bool[] indexed _status
    );
    event RelayerUnRegistered(RelayerAddress indexed relayer);
    event Withdraw(RelayerAddress indexed relayer, uint256 amount);
    event AbsenceProofProcessed(
        uint256 indexed windowId,
        address indexed reporter,
        RelayerAddress indexed absentRelayer,
        uint256 absenceWindowId,
        uint256 penalty
    );
    event GasTokensAdded(RelayerAddress indexed relayer, TokenAddress[] indexed tokens);
    event GasTokensRemoved(RelayerAddress indexed relayer, TokenAddress[] indexed tokens);
}
