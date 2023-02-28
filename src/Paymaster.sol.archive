// SPDX-License-Identifier: MIT

pragma solidity 0.8.17;

import "openzeppelin-contracts/contracts/access/Ownable.sol";
import "./interfaces/IPaymaster.sol";

contract Paymaster is IPaymaster, Ownable {
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

    function reimburseRelayer(address _relayer, address _sponsor, uint256 _amount)
        external
        override
        onlyTransactionAllocator
    {
        if (balances[_sponsor] < _amount) {
            revert InsufficientBalance(_sponsor, balances[_sponsor], _amount);
        }
        unchecked {
            balances[_sponsor] -= _amount;
        }
        (bool success,) = _relayer.call{value: _amount}("");
        if (!success) {
            revert NativeTransferFailed(_relayer, _amount);
        }

        emit RelayerReimbursed(_relayer, _sponsor, _amount);
    }

    function addFunds(address _sponsor) external payable override {
        balances[_sponsor] += msg.value;

        emit FundsAdded(_sponsor, msg.value);
    }

    function updateTransactionAllocator(address _newTransactionAllocator) external onlyOwner {
        transactionAllocator = _newTransactionAllocator;
        emit TransactionAllocator(_newTransactionAllocator);
    }
}
