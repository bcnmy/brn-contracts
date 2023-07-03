// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import {VaaKey, WormholeChainId} from "./WormholeTypes.sol";
import {RelayerAddress} from "ta-common/TATypes.sol";

interface IBRNWormholeDeliveryProviderEventsErrors {
    error CallerMustBeWormholeRelayer();
    error WormholeVAAVerificationFailed(string reason);
    error WormholeReceiptVAAEmitterMismatch(bytes32 expected, bytes32 actual);
    error WormholeDeliveryVAASourceChainMismatch(WormholeChainId expected, WormholeChainId actual);
    error WormholeReceiptVAAEmitterChainMismatch(WormholeChainId expected, WormholeChainId actual);
    error WormholeRedeliveryVAAEmitterChainMismatch(WormholeChainId expected, WormholeChainId actual);
    error WormholeRedeliveryVAAEmitterMismatch(bytes32 expected, bytes32 actual);
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
