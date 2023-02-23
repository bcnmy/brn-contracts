// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

// relayer information
struct RelayerInfo {
    uint256 stake;
    mapping(address => bool) isAccount;
    string endpoint;
    uint256 index;
}

// relayer information
struct WithdrawalInfo {
    uint256 amount;
    uint256 time;
}

struct CdfHashUpdateInfo {
    uint256 windowId;
    bytes32 cdfHash;
}

struct InitalizerParams {
    uint256 blocksPerWindow;
    uint256 withdrawDelay;
    uint256 relayersPerWindow;
    uint256 penaltyDelayBlocks;
}
