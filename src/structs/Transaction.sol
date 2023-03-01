// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

// TODO: Check Stuct Packing
// TODO: Discuss structure
struct ForwardRequest {
    // address from;
    address to;
    // address paymaster;
    // uint256 value;
    // uint256 fixedGas;
    uint256 gasLimit;
    // uint256 nonce;
    bytes data;
}
// bytes signature;

// {
//     to: address(ENtrpointy)
//     data: encoded(UserOper)
// }

// relayer -> int -> tf -> to
