// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import {RelayerAddress, TokenAddress} from "ta-common/TATypes.sol";

/// @title ITATransactionAllocationEventsErrors
interface ITATransactionAllocationEventsErrors {
    error NoRelayersRegistered();
    error InsufficientRelayersRegistered();
    error InvalidRelayerWindow();
    error GasLimitExceeded(uint256 gasLimit, uint256 gasUsed);
    error InvalidSignature(bytes request);
    error UnknownError();
    error InsufficientPrepayment(uint256 required, uint256 actual);
    error GasFeeRefundFailed(bytes reason);
    error PrepaymentFailed(bytes reason);
    error GasTokenNotSuported(TokenAddress tokenAddress);
    error InvalidNonce(address sender, uint256 nonce, uint256 expectedNonce);
    error TransactionExecutionFailed(uint256 index, bytes returndata);
    error InvalidFeeAttached(uint256 totalExpectedValue, uint256 actualValue);
    error CannotProcessLivenessCheckForCurrentOrFutureEpoch();
    error RelayerIndexMappingMismatch(uint256 oldIndex, uint256 newIndex);
    error RelayerAddressMismatch(RelayerAddress expectedAddress, RelayerAddress actualAddress);
    error RelayerAlreadySubmittedTransaction(RelayerAddress relayerAddress, uint256 windowId);

    event PrepaymentReceived(uint256 indexed index, uint256 indexed amount, TokenAddress indexed tokenAddress);
    event GasFeeRefunded(
        uint256 indexed index, uint256 indexed gas, uint256 indexed tokenAmount, TokenAddress tokenAddress
    );
    event TransactionStatus(uint256 indexed index, bool indexed success, bytes indexed returndata);
    event RelayerPenalized(
        RelayerAddress indexed relayerAddress, uint256 indexed newStake, uint256 indexed penaltyAmount
    );
    event RelayerJailed(RelayerAddress indexed relayerAddress, uint256 jailedUntilTimestamp);
    event LivenessCheckAlreadyProcessed();
    event LivenessCheckProcessed(uint256 indexed epochEndTimestamp);
    event NoTransactionsSubmittedInEpoch();
    event EpochEndTimestampUpdated(uint256 indexed epochEndTimestamp);
}
