// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import "src/transaction-allocator/common/TATypes.sol";

interface IPaymasterEventsErrors {
    error OnlyTransactionAllocator(address expected, address actual);
    error NativeTransferFailed(address to, uint256 amount);
    error InsufficientBalance(address account, uint256 balance, uint256 amount);

    event FundsAdded(address indexed sponsor, uint256 indexed amount);
    event TransactionAllocator(address indexed transactionAllocator);
    event PrepayementSuccesful(address indexed sender, uint256 indexed amount, uint256 indexed _expectedGas);
}
