// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import {RelayerAddress, TokenAddress, DelegatorAddress} from "ta-common/TATypes.sol";
import {FixedPointType} from "src/library/FixedPointArithmetic.sol";

/// @title ITADelegationEventsErrors
interface ITADelegationEventsErrors {
    error NoSupportedGasTokens();
    error InvalidRelayerIndex();
    error InvalidTokenIndex();
    error NativeAmountMismatch();
    error WithdrawalNotReady(uint256 minWithdrawalTimestamp);

    event SharesMinted(
        RelayerAddress indexed relayerAddress,
        DelegatorAddress indexed delegatorAddress,
        TokenAddress indexed pool,
        uint256 delegatedAmount,
        FixedPointType sharesMinted,
        FixedPointType sharePrice
    );
    event DelegationAdded(
        RelayerAddress indexed relayerAddress, DelegatorAddress indexed delegatorAddress, uint256 amount
    );
    event RewardSent(
        RelayerAddress indexed relayerAddress,
        DelegatorAddress indexed delegatorAddress,
        TokenAddress indexed tokenAddress,
        uint256 amount
    );
    event DelegationRemoved(
        RelayerAddress indexed relayerAddress, DelegatorAddress indexed delegatorAddress, uint256 amount
    );
    event RelayerProtocolRewardsGenerated(RelayerAddress indexed relayerAddress, uint256 indexed amount);
    event DelegationWithdrawalCreated(
        RelayerAddress indexed relayerAddress,
        DelegatorAddress indexed delegatorAddress,
        TokenAddress indexed tokenAddress,
        uint256 amount,
        uint256 minWithdrawalTimestamp
    );
}
