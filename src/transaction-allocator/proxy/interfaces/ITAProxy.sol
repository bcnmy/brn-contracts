// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import "ta-common/TATypes.sol";

interface ITAProxy {
    error ParameterLengthMismatch();
    error SelectorAlreadyRegistered(address oldModule, address newModule, bytes4 selector);

    event ModuleAdded(address indexed moduleAddr, bytes4[] selectors);

    struct InitalizerParams {
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
        uint256 livenessZParameter;
        TokenAddress bondTokenAddress;
        TokenAddress[] supportedTokens;
    }
}
