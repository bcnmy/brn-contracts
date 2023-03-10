// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import "./TATypes.sol";

// Relayer Information
struct RelayerInfo {
    uint256 stake;
    string endpoint;
    uint256 index;
    RelayerAddress relayerAddress;
    TokenAddress[] supportedGasTokens;
    mapping(TokenAddress => bool) isGasTokenSupported;
    mapping(RelayerAccountAddress => bool) isAccount;
}

struct WithdrawalInfo {
    RelayerAddress withdrawlAddress;
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
    TokenAddress bondTokenAddress;
}

struct AbsenceProofReporterData {
    uint16[] cdf;
    uint256 cdfIndex;
    uint256[] relayerGenerationIterations;
}

struct AbsenceProofAbsenteeData {
    RelayerId relayerId;
    uint256 blockNumber;
    uint256 latestStakeUpdationCdfLogIndex;
    uint16[] cdf;
    uint256[] relayerGenerationIterations;
    uint256 cdfIndex;
}

struct AllocateTransactionParams {
    RelayerId relayerId;
    ForwardRequest[] requests;
    uint16[] cdf;
}

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
