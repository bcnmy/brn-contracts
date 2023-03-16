// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import "src/transaction-allocator/common/TAStructs.sol";

interface ITATransactionAllocationEventsErrors {
    error NoRelayersRegistered();
    error InsufficientRelayersRegistered();
    error RelayerAllocationResultLengthMismatch(uint256 expectedLength, uint256 actualLength);
    error InvalidRelayerWindow();
    error GasLimitExceeded(uint256 gasLimit, uint256 gasUsed);
    error InvalidSignature(Transaction request);
    error UnknownError();
    error InsufficientPrepayment(uint256 required, uint256 actual);
    error GasFeeRefundFailed(bytes reason);
    error PrepaymentFailed(bytes reason);
    error GasTokenNotSuported(TokenAddress tokenAddress);

    event PrepaymentReceived(uint256 indexed index, uint256 indexed amount, TokenAddress indexed tokenAddress);
    event GasFeeRefunded(
        uint256 indexed index, uint256 indexed gas, uint256 indexed tokenAmount, TokenAddress tokenAddress
    );
}
