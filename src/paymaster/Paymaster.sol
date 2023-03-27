// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import "openzeppelin-contracts/contracts/access/Ownable.sol";

import "./interfaces/IPaymaster.sol";
import "src/library/Transaction.sol";
import "src/transaction-allocator/common/TAConstants.sol";

contract Paymaster is IPaymaster, Ownable {
    using TransactionLib for Transaction;

    address public transactionAllocator;
    mapping(address => uint256) balances;

    modifier onlyTransactionAllocator() {
        if (msg.sender != transactionAllocator) {
            revert OnlyTransactionAllocator(transactionAllocator, msg.sender);
        }
        _;
    }

    constructor(address _transactionAllocator) Ownable() {
        transactionAllocator = _transactionAllocator;
    }

    function prepayGas(Transaction calldata _tx, uint256 _expectedGas, bytes calldata)
        external
        override
        onlyTransactionAllocator
        returns (TokenAddress)
    {
        address sender = _tx.getSender();
        uint256 amount = _tx.effectiveGasPrice() * _expectedGas;

        if (balances[sender] < amount) {
            revert InsufficientBalance(sender, balances[sender], amount);
        }
        unchecked {
            balances[sender] -= amount;
        }
        (bool success,) = msg.sender.call{value: amount}("");
        if (!success) {
            revert NativeTransferFailed(msg.sender, amount);
        }

        emit PrepayementSuccesful(sender, amount, _expectedGas);

        return NATIVE_TOKEN;
    }

    function addFunds(address _sender) external payable override {
        balances[_sender] += msg.value;

        emit FundsAdded(_sender, msg.value);
    }

    function updateTransactionAllocator(address _newTransactionAllocator) external onlyOwner {
        transactionAllocator = _newTransactionAllocator;
        emit TransactionAllocator(_newTransactionAllocator);
    }
}
