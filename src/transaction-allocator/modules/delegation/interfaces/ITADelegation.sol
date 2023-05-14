// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import "./ITADelegationEventsErrors.sol";
import "src/transaction-allocator/common/TATypes.sol";

interface ITADelegation is ITADelegationEventsErrors {
    function delegate(
        uint32[] calldata _currentStakeArray,
        uint32[] calldata _prevDelegationArray,
        RelayerAddress[] calldata _activeRelayers,
        uint256 _relayerLogIndex,
        uint256 _relayerIndex,
        uint256 _amount
    ) external;

    function unDelegate(
        uint32[] calldata _currentStakeArray,
        uint32[] calldata _prevDelegationArray,
        RelayerAddress[] calldata _activeRelayers,
        uint256 _relayerLogIndex,
        uint256 _relayerIndex
    ) external;

    function delegationSharePrice(RelayerAddress _relayerAddress, TokenAddress _tokenAddress)
        external
        view
        returns (FixedPointType);

    function delegationRewardsEarned(
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

    function supportedPools() external view returns (TokenAddress[] memory);

    function getDelegationArray(RelayerAddress[] calldata _activeRelayers, uint256 _relayerLogIndex)
        external
        view
        returns (uint32[] memory);
}
