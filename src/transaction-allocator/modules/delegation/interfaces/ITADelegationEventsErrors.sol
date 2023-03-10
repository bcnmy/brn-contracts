// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import "src/transaction-allocator/common/TATypes.sol";
import "src/library/FixedPointArithmetic.sol";

interface ITADelegationEventsErrors {
    error PoolNotSupported(RelayerId relayerId, TokenAddress tokenAddress);
    error NoSupportedGasTokens(RelayerId relayerId);

    event SharesMinted(
        RelayerId indexed relayerId,
        DelegatorAddress indexed delegatorAddress,
        TokenAddress indexed pool,
        uint256 delegatedAmount,
        FixedPointType sharesMinted,
        FixedPointType sharePrice
    );
    event DelegationAdded(RelayerId indexed relayerId, DelegatorAddress indexed delegatorAddress, uint256 amount);
    event RewardSent(
        RelayerId indexed relayerId,
        DelegatorAddress indexed delegatorAddress,
        TokenAddress indexed tokenAddress,
        uint256 amount
    );
    event DelegationRemoved(RelayerId indexed relayerId, DelegatorAddress indexed delegatorAddress, uint256 amount);
}
