// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import "./ITADelegationEventsErrors.sol";
import "./ITADelegationGetters.sol";
import "ta-common/TATypes.sol";

interface ITADelegation is ITADelegationEventsErrors, ITADelegationGetters {
    function delegate(RelayerState calldata _latestState, uint256 _relayerIndex, uint256 _amount) external;

    function undelegate(RelayerState calldata _latestState, RelayerAddress _relayerAddress) external;

    function claimableDelegationRewards(
        RelayerAddress _relayerAddress,
        TokenAddress _tokenAddres,
        DelegatorAddress _delegatorAddress
    ) external view returns (uint256);

    function addDelegationRewards(RelayerAddress _relayerAddress, uint256 _tokenIndex, uint256 _amount)
        external
        payable;
}
