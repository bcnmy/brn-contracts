// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

interface IMockWormholeReceiver {
    error AlreadyExecuted();
    error VAAVerificationFailed(string reason);
    error VAAEmitterVerificationFailed(bytes32 expected, bytes32 actual);

    event WomrholeMessageReceived(
        bytes payload, bytes[] additionalVaas, bytes32 sourceAddress, uint16 sourceChain, bytes32 deliveryHash
    );
    event ValueAdded(uint256 value);
}
