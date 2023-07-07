// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import {ITADelegationEventsErrors} from "./ITADelegationEventsErrors.sol";
import {ITADelegationGetters} from "./ITADelegationGetters.sol";
import {RelayerAddress, DelegatorAddress, TokenAddress} from "ta-common/TATypes.sol";
import {RelayerStateManager} from "ta-common/RelayerStateManager.sol";

/// @title ITADelegation
/// @dev Interface for the delegation module.
interface ITADelegation is ITADelegationEventsErrors, ITADelegationGetters {
    /// @notice Delegate tokens to a relayer.
    /// @param _latestState The latest relayer state, used to calculate the new state post delegation.
    /// @param _relayerIndex The index of the relayer to delegate to in the latest relayer state.
    /// @param _amount The amount of tokens to delegate.
    function delegate(RelayerStateManager.RelayerState calldata _latestState, uint256 _relayerIndex, uint256 _amount)
        external;

    /// @notice Undelegate tokens from a relayer and calculates rewards. The rewards are not transferred, and must be
    ///         claimed by calling withdrawDelegation after a delay.
    /// @param _latestState The latest relayer state, used to calculate the new state post undelegation.
    /// @param _relayerAddress The address of the relayer to undelegate from.
    /// @param _relayerIndex The index of the relayer to undelegate from in the latest relayer state. If the relayer is unregistered
    ///                      or exiting, this can be set to 0.
    function undelegate(
        RelayerStateManager.RelayerState calldata _latestState,
        RelayerAddress _relayerAddress,
        uint256 _relayerIndex
    ) external;

    /// @notice Allows the withdrawal of a delegation after a delay.
    /// @param _relayerAddress The address of the relayer to which funds were originally delegated to.
    function withdrawDelegation(RelayerAddress _relayerAddress) external;

    /// @notice Calculate the amount of rewards claimable by a delegator.
    /// @param _relayerAddress The address of the relayer to which the delegator has delegated to.
    /// @param _tokenAddress The address of the token to calculate rewards for.
    /// @param _delegatorAddress The address of the delegator to calculate rewards for.
    function claimableDelegationRewards(
        RelayerAddress _relayerAddress,
        TokenAddress _tokenAddress,
        DelegatorAddress _delegatorAddress
    ) external view returns (uint256);

    /// @notice Allows an arbitrary called to supply additional rewards to a relayer's delegators.
    /// @param _relayerAddress The address of the relayer to add rewards to.
    /// @param _tokenIndex The index of the token (in supportedTokens array) to add rewards.
    /// @param _amount The amount of tokens to add as rewards.
    function addDelegationRewards(RelayerAddress _relayerAddress, uint256 _tokenIndex, uint256 _amount)
        external
        payable;
}
