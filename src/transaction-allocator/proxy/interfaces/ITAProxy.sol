// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import {TokenAddress, RelayerAddress, RelayerAccountAddress} from "ta-common/TATypes.sol";
import {FixedPointType} from "src/library/FixedPointArithmetic.sol";

interface ITAProxy {
    error ParameterLengthMismatch();
    error SelectorAlreadyRegistered(address oldModule, address newModule, bytes4 selector);

    event ModuleAdded(address indexed moduleAddr, bytes4[] selectors);

    struct InitializerParams {
        uint256 blocksPerWindow;
        uint256 epochLengthInSec;
        uint256 relayersPerWindow;
        uint256 jailTimeInSec;
        uint256 withdrawDelayInSec;
        uint256 absencePenaltyPercentage;
        uint256 minimumStakeAmount;
        uint256 minimumDelegationAmount;
        uint256 baseRewardRatePerMinimumStakePerSec;
        uint256 relayerStateUpdateDelayInWindows;
        FixedPointType livenessZParameter;
        uint256 stakeThresholdForJailing;
        TokenAddress bondTokenAddress;
        TokenAddress[] supportedTokens;
        // Foundation Relayer Parameters
        RelayerAddress foundationRelayerAddress;
        RelayerAccountAddress[] foundationRelayerAccountAddresses;
        uint256 foundationRelayerStake;
        string foundationRelayerEndpoint;
        uint256 foundationDelegatorPoolPremiumShare;
    }
}
