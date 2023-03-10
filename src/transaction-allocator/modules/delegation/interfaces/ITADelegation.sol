// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import "./ITADelegationEventsErrors.sol";
import "src/transaction-allocator/common/TATypes.sol";

interface ITADelegation is ITADelegationEventsErrors {
    function delegate(
        uint32[] calldata _currentStakeArray,
        uint32[] calldata _prevDelegationArray,
        RelayerId _relayerId,
        uint256 _amount
    ) external;

    function unDelegate(
        uint32[] calldata _currentStakeArray,
        uint32[] calldata _prevDelegationArray,
        RelayerId _relayerId
    ) external;

    function sharePrice(RelayerId _relayerId, TokenAddress _tokenAddress) external view returns (FixedPointType);

    function rewardsEarned(RelayerId _relayerId, TokenAddress _tokenAddres, DelegatorAddress _delegatorAddress)
        external
        view
        returns (uint256);

    ////////////////////////// Getters //////////////////////////
    function totalDelegation(RelayerId _relayerId) external view returns (uint256);

    function delegation(RelayerId _relayerId, DelegatorAddress _delegatorAddress) external view returns (uint256);

    function shares(RelayerId _relayerId, DelegatorAddress _delegatorAddress, TokenAddress _tokenAddress)
        external
        view
        returns (FixedPointType);

    function totalShares(RelayerId _relayerId, TokenAddress _tokenAddress) external view returns (FixedPointType);

    function unclaimedRewards(RelayerId _relayerId, TokenAddress _tokenAddress) external view returns (uint256);

    function getDelegationArray() external view returns (uint32[] memory);
}
