// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import "wormhole-contracts/interfaces/relayer/IWormholeReceiver.sol";

import "./interaces/IMockWormholeReceiver.sol";

contract MockWormholeReceiver is IMockWormholeReceiver, IWormholeReceiver {
    mapping(bytes32 => bool) public replayProtection;
    uint256 public sum = 0;

    function receiveWormholeMessages(
        bytes memory payload,
        bytes[] memory additionalVaas,
        bytes32 sourceAddress,
        uint16 sourceChain,
        bytes32 deliveryHash
    ) public payable override {
        require(!replayProtection[deliveryHash], "Replay protection");
        replayProtection[deliveryHash] = true;

        receiveWormholeMessages(payload, additionalVaas, sourceAddress, sourceChain);

        emit WomrholeMessageReceived(payload, additionalVaas, sourceAddress, sourceChain, deliveryHash);
    }

    function receiveWormholeMessages(bytes memory payload, bytes[] memory, bytes32, uint16) internal {
        uint256 value = abi.decode(payload, (uint256));
        sum += value;

        emit ValueAdded(value);
    }
}
