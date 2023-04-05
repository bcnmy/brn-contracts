// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import "openzeppelin-contracts/contracts/utils/cryptography/ECDSA.sol";
import "openzeppelin-contracts/contracts/utils/math/Math.sol";

import "src/transaction-allocator/common/TAStructs.sol";
import "src/paymaster/interfaces/IPaymaster.sol";

library TransactionLib {
    using ECDSA for bytes32;
    using TransactionLib for Transaction;

    function hash(Transaction calldata _tx) internal pure returns (bytes32) {
        return keccak256(
            abi.encode(
                _tx.to,
                _tx.nonce,
                _tx.callData,
                _tx.callGasLimit,
                _tx.baseGas,
                _tx.maxFeePerGas,
                _tx.maxPriorityFeePerGas,
                _tx.paymaster
            )
        );
    }

    function hashMemory(Transaction memory _tx) internal pure returns (bytes32) {
        return keccak256(
            abi.encode(
                _tx.to,
                _tx.nonce,
                _tx.callData,
                _tx.callGasLimit,
                _tx.baseGas,
                _tx.maxFeePerGas,
                _tx.maxPriorityFeePerGas,
                _tx.paymaster
            )
        );
    }

    function getSender(Transaction calldata _tx) internal pure returns (address) {
        return _tx.hash().toEthSignedMessageHash().recover(_tx.signature);
    }

    function effectiveGasPrice(Transaction calldata _tx) internal view returns (uint256) {
        unchecked {
            if (_tx.maxFeePerGas == _tx.maxPriorityFeePerGas) {
                //legacy mode (for networks that don't support basefee opcode)
                return _tx.maxFeePerGas;
            }
            return Math.min(_tx.maxFeePerGas, _tx.maxPriorityFeePerGas + block.basefee);
        }
    }

    function getPaymasterAndData(Transaction calldata _tx) internal pure returns (IPaymaster, bytes memory) {
        (IPaymaster paymaster, bytes memory data) = abi.decode(_tx.paymaster, (IPaymaster, bytes));
        return (paymaster, data);
    }
}
