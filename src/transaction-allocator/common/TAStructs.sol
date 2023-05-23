// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import "src/library/FixedPointArithmetic.sol";
import "./TATypes.sol";

// TODO: Packing

enum RelayerStatus {
    Uninitialized,
    Active,
    Exiting,
    Jailed
}

// Relayer Information
struct RelayerInfo {
    uint256 stake;
    string endpoint;
    uint256 delegatorPoolPremiumShare; // *100
    RelayerAccountAddress[] relayerAccountAddresses;
    mapping(RelayerAccountAddress => bool) isAccount;
    RelayerStatus status;
    uint256 minExitBlockNumber;
    // TODO: Reward share related data should be moved to it's own mapping
    uint256 unpaidProtocolRewards;
    FixedPointType rewardShares;
}

struct InitalizerParams {
    uint256 blocksPerWindow;
    uint256 epochLengthInSec;
    uint256 relayersPerWindow;
    TokenAddress bondTokenAddress;
    TokenAddress[] supportedTokens;
}

struct AllocateTransactionParams {
    RelayerAddress relayerAddress;
    bytes[] requests;
    uint16[] cdf;
    RelayerAddress[] activeRelayers;
}

struct LatestActiveRelayersStakeAndDelegationState {
    uint32[] currentStakeArray;
    uint32[] currentDelegationArray;
    RelayerAddress[] activeRelayers;
}

struct TargetEpochData {
    uint16[] cdf;
    RelayerAddress[] activeRelayers;
}
