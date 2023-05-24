// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import "ta-common/TATypes.sol";

interface ITARelayerManagementEventsErrors {
    error NoAccountsProvided();
    error InsufficientStake(uint256 stake, uint256 minimumStake);
    error InvalidWithdrawal(uint256 amount, uint256 currentTimestamp, uint256 minValidTimestamp);
    error AbsenteeWasPresent(uint256 absenteewindowIndex);
    error ReporterTransferFailed(RelayerAccountAddress reporter, uint256 amount);
    error GasTokenAlreadySupported(TokenAddress token);
    error GasTokenNotSupported(TokenAddress token);
    error RelayerAlreadyRegistered();
    error RelayerNotActive();
    error RelayerNotExiting();
    error RelayerNotJailed();
    error RelayerJailNotExpired(uint256 jailedUntilTimestamp);

    event RelayerRegistered(
        RelayerAddress indexed relayer,
        string endpoint,
        RelayerAccountAddress[] accounts,
        uint256 indexed stake,
        uint256 delegatorPoolPremiumShare
    );
    event RelayerAccountsUpdated(RelayerAddress indexed relayer, RelayerAccountAddress[] indexed _accounts);
    event RelayerUnRegistered(RelayerAddress indexed relayer);
    event Withdraw(RelayerAddress indexed relayer, uint256 indexed amount);
    event AbsenceProofProcessed(
        uint256 indexed windowIndex,
        address indexed reporter,
        RelayerAddress indexed absentRelayer,
        uint256 absencewindowIndex,
        uint256 penalty
    );
    event GasTokensAdded(RelayerAddress indexed relayer, TokenAddress[] indexed tokens);
    event GasTokensRemoved(RelayerAddress indexed relayer, TokenAddress[] indexed tokens);
    event RelayerProtocolRewardsClaimed(RelayerAddress indexed relayer, uint256 indexed amount);
    event RelayerUnjailed(RelayerAddress indexed relayer);
}
