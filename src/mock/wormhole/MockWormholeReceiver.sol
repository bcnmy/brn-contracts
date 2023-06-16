// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {IDeliveryProvider} from "wormhole-contracts/interfaces/relayer/IDeliveryProviderTyped.sol";
import "wormhole-contracts/interfaces/relayer/IWormholeReceiver.sol";
import "wormhole-application/interfaces/IBRNWormholeDeliveryProvider.sol";

import "./interaces/IMockWormholeReceiver.sol";
import "forge-std/console2.sol";

contract MockWormholeReceiver is IMockWormholeReceiver, IWormholeReceiver {
    mapping(bytes32 => bool) public replayProtection;
    uint256 public sum = 0;

    IBRNWormholeDeliveryProvider public deliveryProvider;
    IWormholeRelayer public relayer;
    WormholeChainId public chainId;

    modifier onlyRelayerContract() {
        require(msg.sender == address(relayer), "msg.sender is not WormholeRelayer contract.");
        _;
    }

    constructor(
        IBRNWormholeDeliveryProvider _deliveryProvider,
        IWormholeRelayer _wormholeRelayer,
        WormholeChainId _chainId
    ) {
        deliveryProvider = _deliveryProvider;
        relayer = _wormholeRelayer;
        chainId = _chainId;
    }

    function sendPayload(
        WormholeChainId _targetChain,
        uint256 _payloadValue,
        Gas _gasLimit,
        TargetNative _receiverValue,
        address _targetContract
    ) public payable {
        bytes memory payload = abi.encode(_payloadValue);

        //calculate cost to deliver message
        (LocalNative deliveryCost,) =
            deliveryProvider.quoteEvmDeliveryPrice(WormholeChainId.unwrap(_targetChain), _gasLimit, _receiverValue);

        // publish delivery request
        relayer.sendToEvm{value: LocalNative.unwrap(deliveryCost)}(
            WormholeChainId.unwrap(_targetChain),
            _targetContract,
            payload,
            _receiverValue,
            LocalNative.wrap(0),
            _gasLimit,
            WormholeChainId.unwrap(chainId),
            address(this),
            address(deliveryProvider),
            new VaaKey[](0),
            0
        );
    }

    function receiveWormholeMessages(
        bytes memory payload,
        bytes[] memory additionalVaas,
        bytes32 sourceAddress,
        uint16 sourceChain,
        bytes32 deliveryHash
    ) public payable override onlyRelayerContract {
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

    receive() external payable {}
}
