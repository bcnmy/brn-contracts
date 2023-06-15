// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import "./WormholeTypes.sol";

interface IBRNWormholeDeliveryProviderEventsErrors {
    error CallerMustBeWormholeRelayer();
    error WormholeVAAVerificationFailed(string reason);
    error WormholeDeliveryVAAEmitterMismatch(bytes32 expected, bytes32 actual);
    error WormholeDeliveryVAASourceChainMismatch(WormholeChainId expected, WormholeChainId actual);
    error WormholeReceiptVAAEmitterChainMismatch(WormholeChainId expected, WormholeChainId actual);
    error WormholeReceiptVAAEmitterMismatch(bytes32 expected, bytes32 actual);
    error WormholeRedeliveryVAAKeyMismatch(VaaKey expected, VaaKey actual);
    error WormholeRedeliveryVAATargetChainMismatch(WormholeChainId expected, WormholeChainId actual);
    error NotAuthorized();
    error NoFunds();
    error NativeTransferFailed();
    error ParamterLengthMismatch();

    event FundsDepositedForRelaying(uint256 indexed deliveryVAASequenceNumber, uint256 indexed amount);
    event DeliveryFeeClaimed(
        uint256 indexed deliveryVAASequenceNumber, RelayerAddress indexed relayer, uint256 indexed amount
    );
    event RedeliveryFeeClaimed(
        uint256 indexed redeliveryVAASequenceNumber, RelayerAddress indexed relayer, uint256 indexed amount
    );
}
