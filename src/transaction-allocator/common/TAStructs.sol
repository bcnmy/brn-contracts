// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import "src/interfaces/IApplication.sol";
import "./TATypes.sol";

// Relayer Information
struct RelayerInfo {
    uint256 stake;
    string endpoint;
    uint256 index;
    uint256 delegatorPoolPremiumShare; // *100
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
    IApplication to;
    uint256 fixedGas; // Application has to somehow agree to this, otherwise relayer can specify arbitrarily large value to drain funds
    uint256 prePaymentGasLimit;
    uint256 gasLimit; // TODO: Relayer can manipulate this value, for ex set it to 0
    uint256 refundGasLimit; // Application has to somehow agree to this, otherwise relayer can specify arbitrarily small value to prevent refund
    bytes data;
}
