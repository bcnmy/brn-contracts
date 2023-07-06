// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import {TokenAddress, RelayerAddress, RelayerAccountAddress} from "ta-common/TATypes.sol";
import {FixedPointType} from "src/library/FixedPointArithmetic.sol";

/// @title ITAProxy
/// @notice The entrypoint for the Transaction Allocator contract.
interface ITAProxy {
    error ParameterLengthMismatch();
    error SelectorAlreadyRegistered(address oldModule, address newModule, bytes4 selector);

    event ModuleAdded(address indexed moduleAddr, bytes4[] selectors);

    /// @dev Data structure for the parameters used to initialize the Transaction Allocator contract.
    struct InitializerParams {
        ////////////////////////// Transaction Allocation Configuration Parameters //////////////////////////
        uint256 blocksPerWindow;
        uint256 epochLengthInSec;
        uint256 relayersPerWindow;
        ////////////////////////// Liveness Configuration Parameters //////////////////////////
        uint256 jailTimeInSec;
        FixedPointType livenessZParameter;
        uint256 absencePenaltyPercentage;
        uint256 stakeThresholdForJailing;
        ////////////////////////// Relayer Management Configuration Parameters //////////////////////////
        uint256 withdrawDelayInSec;
        uint256 minimumStakeAmount;
        uint256 minimumDelegationAmount;
        uint256 relayerStateUpdateDelayInWindows;
        TokenAddress bondTokenAddress;
        ////////////////////////// Protocol Rewards Configuration Parameters //////////////////////////
        uint256 baseRewardRatePerMinimumStakePerSec;
        TokenAddress[] supportedTokens;
        ////////////////////////// Delegation Configuration Parameters //////////////////////////
        uint256 delegationWithdrawDelayInSec;
        ////////////////////////// Foundation Relayer Parameters //////////////////////////
        RelayerAddress foundationRelayerAddress;
        RelayerAccountAddress[] foundationRelayerAccountAddresses;
        uint256 foundationRelayerStake;
        string foundationRelayerEndpoint;
        uint256 foundationDelegatorPoolPremiumShare;
    }
}
