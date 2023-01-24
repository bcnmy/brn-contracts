// SPDX-License-Identifier: MIT

pragma solidity 0.8.17;

interface IPaymaster {
    error OnlyTransactionAllocator(address expected, address actual);
    error NativeTransferFailed(address to, uint256 amount);
    error InsufficientBalance(address account, uint256 balance, uint256 amount);

    event RelayerReimbursed(
        address indexed relayer,
        address indexed sponsor,
        uint256 indexed amount
    );
    event FundsAdded(address indexed sponsor, uint256 indexed amount);
    event TransactionAllocator(address indexed transactionAllocator);

    function reimburseRelayer(
        address _relayer,
        address _sponsor,
        uint256 _amount
    ) external;

    function addFunds(address _sponsor) external payable;
}
