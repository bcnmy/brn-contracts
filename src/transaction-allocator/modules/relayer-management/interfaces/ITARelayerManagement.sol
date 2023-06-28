// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import {RelayerAddress, RelayerAccountAddress, RelayerState} from "ta-common/TATypes.sol";
import {ITARelayerManagementEventsErrors} from "./ITARelayerManagementEventsErrors.sol";
import {ITARelayerManagementGetters} from "./ITARelayerManagementGetters.sol";

interface ITARelayerManagement is ITARelayerManagementEventsErrors, ITARelayerManagementGetters {
    ////////////////////////// Relayer Registration //////////////////////////
    function register(
        RelayerState calldata _latestState,
        uint256 _stake,
        RelayerAccountAddress[] calldata _accounts,
        string memory _endpoint,
        uint256 _delegatorPoolPremiumShare
    ) external;

    function unregister(RelayerState calldata _latestState, uint256 _relayerIndex) external;

    function registerFoundationRelayer(
        RelayerAddress _foundationRelayerAddress,
        uint256 _stake,
        RelayerAccountAddress[] calldata _accounts,
        string calldata _endpoint,
        uint256 _delegatorPoolPremiumShare
    ) external;

    function withdraw(RelayerAccountAddress[] calldata _relayerAccountsToRemove) external;

    function unjailAndReenter(RelayerState calldata _latestState, uint256 _stake) external;

    function setRelayerAccountsStatus(RelayerAccountAddress[] calldata _accounts, bool[] calldata _status) external;

    ////////////////////////// Protocol Rewards //////////////////////////
    function claimProtocolReward() external;

    function relayerClaimableProtocolRewards(RelayerAddress _relayerAddress) external view returns (uint256);
}
