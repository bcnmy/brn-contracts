// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import "src/library/FixedPointArithmetic.sol";
import "./TATypes.sol";

// TODO: Packing

// Relayer Information
struct RelayerInfo {
    uint256 stake;
    string endpoint;
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

struct InitalizerParams {
    uint256 blocksPerWindow;
    uint256 relayersPerWindow;
    uint256 penaltyDelayBlocks;
    TokenAddress bondTokenAddress;
    TokenAddress[] supportedTokens;
}

struct AllocateTransactionParams {
    RelayerAddress relayerAddress;
    bytes[] requests;
    uint16[] cdf;
    uint256 currentCdfLogIndex;
    RelayerAddress[] activeRelayers;
    uint256 relayerLogIndex;
}

struct LatestActiveRelayersStakeAndDelegationState {
    uint32[] currentStakeArray;
    uint32[] currentDelegationArray;
    RelayerAddress[] activeRelayers;
}

struct TargetEpochData {
    uint256 epochIndex;
    uint256 cdfLogIndex;
    uint256 relayerLogIndex;
    uint16[] cdf;
    RelayerAddress[] activeRelayers;
}
