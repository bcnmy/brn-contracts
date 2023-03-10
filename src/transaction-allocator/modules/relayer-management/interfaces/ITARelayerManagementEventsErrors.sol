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
    error GasTokenAlreadySupported(TokenAddress token);
    error GasTokenNotSupported(TokenAddress token);

    event RelayerRegistered(
        RelayerId indexed relayer,
        RelayerAddress indexed relayerAddress,
        string endpoint,
        RelayerAccountAddress[] accounts,
        uint256 indexed stake
    );
    event RelayerAccountsUpdated(
        RelayerId indexed relayer, RelayerAccountAddress[] indexed _accounts, bool[] indexed _status
    );
    event RelayerUnRegistered(RelayerId indexed relayer);
    event Withdraw(RelayerId indexed relayer, uint256 amount);
    event AbsenceProofProcessed(
        uint256 indexed windowId,
        address indexed reporter,
        RelayerId indexed absentRelayer,
        uint256 absenceWindowId,
        uint256 penalty
    );
    event GasTokensAdded(RelayerId indexed relayer, TokenAddress[] indexed tokens);
    event GasTokensRemoved(RelayerId indexed relayer, TokenAddress[] indexed tokens);
}
