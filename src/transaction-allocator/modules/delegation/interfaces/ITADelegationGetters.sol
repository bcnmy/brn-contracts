// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import {RelayerAddress, DelegatorAddress, TokenAddress} from "ta-common/TATypes.sol";
import {FixedPointType} from "src/library/FixedPointArithmetic.sol";

/// @title ITADelegationGetters
interface ITADelegationGetters {
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
