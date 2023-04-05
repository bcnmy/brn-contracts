// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import "src/library/FixedPointArithmetic.sol";
import "./TATypes.sol";

// Relayer Information
struct RelayerInfo {
    uint256 stake;
    string endpoint;
    uint256 index;
    uint256 delegatorPoolPremiumShare; // *100
    uint256 unpaidProtocolRewards;
    FixedPointType rewardShares;
    RelayerAccountAddress[] relayerAccountAddresses;
    mapping(RelayerAccountAddress => bool) isAccount;
}

struct WithdrawalInfo {
    uint256 amount;
    uint256 minBlockNumber;
}

struct CdfHashUpdateInfo {
    uint256 windowIndex;
    bytes32 cdfHash;
}

struct RelayerIndexToRelayerUpdateInfo {
    uint256 windowIndex;
    RelayerAddress relayerAddress;
}

struct InitalizerParams {
    uint256 blocksPerWindow;
    uint256 relayersPerWindow;
    uint256 penaltyDelayBlocks;
    TokenAddress bondTokenAddress;
    TokenAddress[] supportedTokens;
}

struct AbsenceProofReporterData {
    uint16[] cdf;
    uint256 cdfIndex;
    uint256[] relayerGenerationIterations;
    uint256 currentCdfLogIndex;
    uint256 relayerIndexToRelayerLogIndex;
}

struct AbsenceProofAbsenteeData {
    RelayerAddress relayerAddress;
    uint256 blockNumber;
    uint256 latestStakeUpdationCdfLogIndex;
    uint16[] cdf;
    uint256[] relayerGenerationIterations;
    uint256 cdfIndex;
    uint256 relayerIndexToRelayerLogIndex;
}

struct AllocateTransactionParams {
    RelayerAddress relayerAddress;
    Transaction[] requests;
    uint16[] cdf;
    uint256 currentCdfLogIndex;
}

struct Transaction {
    address to;
    uint256 nonce;
    bytes callData;
    uint256 callGasLimit;
    uint256 baseGas;
    uint256 maxFeePerGas;
    uint256 maxPriorityFeePerGas;
    bytes paymaster;
    bytes signature;
}
