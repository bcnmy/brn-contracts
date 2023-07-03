// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import {RelayerAddress, RelayerAccountAddress} from "ta-common/TATypes.sol";

/// @title ITARelayerManagementEventsErrors
interface ITARelayerManagementEventsErrors {
    error NoAccountsProvided();
    error InsufficientStake(uint256 stake, uint256 minimumStake);
    error ExitCooldownNotExpired(uint256 amount, uint256 currentTimestamp, uint256 minValidTimestamp);
    error RelayerAlreadyRegistered();
    error RelayerNotExiting();
    error RelayerNotJailed();
    error RelayerJailNotExpired(uint256 jailedUntilTimestamp);
    error CannotUnregisterLastRelayer();
    error FoundationRelayerAlreadyRegistered();

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
    event RelayerProtocolRewardsClaimed(RelayerAddress indexed relayer, uint256 indexed amount);
    event RelayerUnjailedAndReentered(RelayerAddress indexed relayer);
}
