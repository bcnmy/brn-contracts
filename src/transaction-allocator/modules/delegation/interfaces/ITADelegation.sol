// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import "./ITADelegationEventsErrors.sol";
import "src/transaction-allocator/common/TATypes.sol";

interface ITADelegation is ITADelegationEventsErrors {
    function delegate(RelayerAddress _relayerAddress, uint256 _amount) external;

    function unDelegate(RelayerAddress _relayerAddress) external;
    function sharePrice(RelayerAddress _relayerAddress, TokenAddress _tokenAddress)
        external
        view
        returns (FixedPointType);

    function rewardsEarned(
        RelayerAddress _relayerAddress,
        TokenAddress _tokenAddres,
        DelegatorAddress _delegatorAddress
    ) external view returns (uint256);
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

    function unclaimedRewards(RelayerAddress _relayerAddress, TokenAddress _tokenAddress)
        external
        view
        returns (uint256);
}
