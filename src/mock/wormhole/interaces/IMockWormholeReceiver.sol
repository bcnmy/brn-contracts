// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

interface IMockWormholeReceiver {
    error AlreadyExecuted();

    event WomrholeMessageReceived(
        bytes payload, bytes[] additionalVaas, bytes32 sourceAddress, uint16 sourceChain, bytes32 deliveryHash
    );
    event ValueAdded(uint256 value);
}
