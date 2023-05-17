// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import "src/transaction-allocator/common/TAStructs.sol";

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
    error TransactionExecutionFailed(uint256 index);
    error InvalidFeeAttached(uint256 totalExpectedValue, uint256 actualValue);
    error CannotProcessLivenessCheckForCurrentOrFutureEpoch();
    error LivenessCheckAlreadyProcessed();
    error RelayerIndexMappingMismatch(uint256 oldIndex, uint256 newIndex);

    event PrepaymentReceived(uint256 indexed index, uint256 indexed amount, TokenAddress indexed tokenAddress);
    event GasFeeRefunded(
        uint256 indexed index, uint256 indexed gas, uint256 indexed tokenAmount, TokenAddress tokenAddress
    );
    event TransactionStatus(uint256 indexed index, bool indexed success, bytes indexed returndata);
    event RelayerPenalized(RelayerAddress indexed relayerAddress, uint256 indexed epoch, uint256 indexed penaltyAmount);
}
