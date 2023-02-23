// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

// Forward request structure
struct ForwardRequest {
    address from;
    address to;
    address paymaster;
    uint256 value;
    uint256 gas;
    uint256 nonce;
    uint256 fixedgas;
    bytes data;
    bytes signature;
}
