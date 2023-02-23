// SPDX-License-Identifier: MIT

pragma solidity 0.8.17;

struct PStorage {
    mapping(bytes4 => address) implementations;
    mapping(address => bytes32) selectorsHash;
}
