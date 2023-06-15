// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import "./WormholeTypes.sol";

interface IBRNWormholeDeliveryProviderEventsErrors {
    error CallerMustBeWormholeRelayer();
    error WormholeDeliveryVAAVerificationFailed(uint256 index, string reason);
    error WormholeDeliveryVAAEmitterMismatch(uint256 index, bytes32 expected, bytes32 actual);
    error WormholeDeliveryVAASourceChainMismatch(uint256 index, WormholeChainId expected, WormholeChainId actual);
    error NotAuthorized(uint256 index);
    error NoFunds();
    error NativeTransferFailed();

    event FundsDepositedForRelaying(uint256 indexed deliveryVAASequenceNumber, uint256 indexed amount);
    event FeeClaimed(uint256 indexed deliveryVAASequenceNumber, RelayerAddress indexed relayer, uint256 indexed amount);
}
