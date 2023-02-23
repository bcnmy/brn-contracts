// SPDX-License-Identifier: MIT

pragma solidity 0.8.17;

import "../structs/TAStructs.sol";

// TODO: Should each module have it's own storage struct?
struct TAStorage {
    // -------Proxy State-------
    mapping(bytes4 => address) implementations;
    mapping(address => bytes32) selectorsHash;
    bool initialized;
    // -------Transaction Allocator State-------
    uint256 MIN_PENATLY_BLOCK_NUMBER;
    /// Maps relayer main address to info
    mapping(address => RelayerInfo) relayerInfo;
    /// Maps relayer address to pending withdrawals
    mapping(address => WithdrawalInfo) withdrawalInfo;
    uint256 relayerCount;
    /// blocks per node
    uint256 blocksWindow;
    // unbounding period
    uint256 withdrawDelay;
    // random number of realyers selected per window
    uint256 relayersPerWindow;
    // stake array hash
    bytes32 stakeArrayHash;
    // cdf array hash
    CdfHashUpdateInfo[] cdfHashUpdateLog;
    // Relayer Index to Relayer
    mapping(uint256 => address) relayerIndexToRelayer;
    // attendance: windowIndex -> relayer -> wasPresent?
    mapping(uint256 => mapping(address => bool)) attendance;
}
