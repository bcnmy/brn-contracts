// SPDX-License-Identifier: MIT

pragma solidity 0.8.17;

contract SmartWalletConstants {
    bytes32 public constant TYPEHASH =
        keccak256(
            "SmartContractExecutionRequest(address from,address to,address paymaster,uint256 value,uint256 gas,uint256 fixedgas,uint256 nonce,bytes data)"
        );

    string public constant EIP712_NAME = "SmartWallet";
    string public constant EIP712_VERSION = "1";
}
