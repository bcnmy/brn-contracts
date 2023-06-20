// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import "./ITADelegationEventsErrors.sol";
import "ta-common/TATypes.sol";

interface ITADelegation is ITADelegationEventsErrors {
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

    ////////////////////////// Getters //////////////////////////
    function totalDelegation(RelayerAddress _relayerAddress) external view returns (uint256);

    function delegation(RelayerAddress _relayerAddress, DelegatorAddress _delegatorAddress)
        external
        view
        returns (uint256);

    function shares(RelayerAddress _relayerAddress, DelegatorAddress _delegatorAddress, TokenAddress _tokenAddress)
        external
        view
        returns (FixedPointType);

    function totalShares(RelayerAddress _relayerAddress, TokenAddress _tokenAddress)
        external
        view
        returns (FixedPointType);

    function unclaimedDelegationRewards(RelayerAddress _relayerAddress, TokenAddress _tokenAddress)
        external
        view
        returns (uint256);

    function supportedPools() external view returns (TokenAddress[] memory);

    function minimumDelegationAmount() external view returns (uint256);
}
