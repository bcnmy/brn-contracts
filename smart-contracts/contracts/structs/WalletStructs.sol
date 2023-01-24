// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

// Forward request structure
struct ForwardRequest {
    address from;
    address to;
    uint256 value;
    uint256 gas;
    uint256 nonce;
    bytes data;
    bytes signature;
}