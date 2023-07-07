// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import {RelayerAddress, RelayerAccountAddress} from "ta-common/TATypes.sol";
import {RelayerStateManager} from "ta-common/RelayerStateManager.sol";
import {ITARelayerManagementEventsErrors} from "./ITARelayerManagementEventsErrors.sol";
import {ITARelayerManagementGetters} from "./ITARelayerManagementGetters.sol";

/// @title ITARelayerManagement
interface ITARelayerManagement is ITARelayerManagementEventsErrors, ITARelayerManagementGetters {
    ////////////////////////// Relayer Registration //////////////////////////

    /// @notice Registers a relayer
    /// @param _latestState The latest relayer state, used to calculate the new state post relayer registration.
    /// @param _stake The amount of tokens to stake in the bond token (bico).
    /// @param _accounts The accounts to register for the relayer.
    /// @param _endpoint The rpc endpoint of the relayer.
    /// @param _delegatorPoolPremiumShare The percentage of the delegator pool rewards to be shared with the relayer.
    function register(
        RelayerStateManager.RelayerState calldata _latestState,
        uint256 _stake,
        RelayerAccountAddress[] calldata _accounts,
        string memory _endpoint,
        uint256 _delegatorPoolPremiumShare
    ) external;

    /// @notice Unregisters a relayer. Puts the relayer in "exiting" state.
    /// @param _latestState The latest relayer state, used to calculate the new state post relayer unregistration.
    /// @param _relayerIndex The index of the relayer to unregister in the latest relayer state.
    function unregister(RelayerStateManager.RelayerState calldata _latestState, uint256 _relayerIndex) external;

    /// @notice Registers the first relayer in the system, which is the foundation relayer. This must be called only once,
    ///         during setup.
    ///         This is needed because new relayers can enter the system only once the liveness check passes for the current epoch.
    ///         and the liveness check can only be triggered by an existing relayer.
    /// @param _foundationRelayerAddress The address of the foundation relayer.
    /// @param _stake  The amount of tokens to stake in the bond token (bico).
    /// @param _accounts The accounts to register for the relayer.
    /// @param _endpoint The rpc endpoint of the relayer.
    /// @param _delegatorPoolPremiumShare The percentage of the delegator pool rewards to be shared with the relayer.
    function registerFoundationRelayer(
        RelayerAddress _foundationRelayerAddress,
        uint256 _stake,
        RelayerAccountAddress[] calldata _accounts,
        string calldata _endpoint,
        uint256 _delegatorPoolPremiumShare
    ) external;

    /// @notice Allows a realyer in the "exiting" state to withdraw their stake (and any unclaimed rewards) once the cooldown period ends.
    /// @param _relayerAccountsToRemove The relayer can specify the account addresses to delete from on-chain storage, which should result
    ///                                 in a gas refund.
    function withdraw(RelayerAccountAddress[] calldata _relayerAccountsToRemove) external;

    /// @notice Allows a jailed relayer to unjail themselves and reenter the system after the jail period ends.
    /// @param _latestState The latest relayer state, used to calculate the new state post unjail.
    /// @param _stake The relayer needs to add more stake so that their total stake is greater than the minimum stake.
    function unjailAndReenter(RelayerStateManager.RelayerState calldata _latestState, uint256 _stake) external;

    /// @notice Allows a relayer to update it's accounts
    /// @param _accounts The accounts to add/remove for the relayer.
    /// @param _status Array of booleans indicating whether the corresponding account in _accounts should be added or removed.
    function setRelayerAccountsStatus(RelayerAccountAddress[] calldata _accounts, bool[] calldata _status) external;

    ////////////////////////// Protocol Rewards //////////////////////////

    /// @notice Allows a relayer to claim their protocol rewards.
    function claimProtocolReward() external;

    /// @notice Calculates the amount of protocol rewards claimable by a relayer.
    /// @param _relayerAddress The address of the relayer.
    /// @return The amount of protocol rewards claimable by the relayer.
    function relayerClaimableProtocolRewards(RelayerAddress _relayerAddress) external view returns (uint256);
}
