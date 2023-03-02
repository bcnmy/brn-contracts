// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import "src/transaction-allocator/common/TATypes.sol";
import "src/library/FixedPointArithmetic.sol";

interface ITADelegationEventsErrors {
    error PoolNotSupported(RelayerAddress relayerAddress, TokenAddress tokenAddress);

    event SharesMinted(
        RelayerAddress indexed relayerAddress,
        DelegatorAddress indexed delegatorAddress,
        TokenAddress indexed pool,
        uint256 delegatedAmount,
        FixedPointType sharesMinted,
        FixedPointType sharePrice
    );
    event DelegationAdded(
        RelayerAddress indexed relayerAddress, DelegatorAddress indexed delegatorAddress, uint256 amount
    );
    event RewardSent(
        RelayerAddress indexed relayerAddress,
        DelegatorAddress indexed delegatorAddress,
        TokenAddress indexed tokenAddress,
        uint256 amount
    );
    event DelegationRemoved(
        RelayerAddress indexed relayerAddress, DelegatorAddress indexed delegatorAddress, uint256 amount
    );
}
