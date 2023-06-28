// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {IDeliveryProvider} from "wormhole-contracts/interfaces/relayer/IDeliveryProviderTyped.sol";
import {toWormholeFormat} from "wormhole-contracts/libraries/relayer/Utils.sol";
import "wormhole-contracts/interfaces/relayer/IWormholeReceiver.sol";
import "wormhole-contracts/interfaces/IWormhole.sol";

import "wormhole-application/interfaces/IBRNWormholeDeliveryProvider.sol";
import "./interaces/IMockWormholeReceiver.sol";

contract MockWormholeReceiver is IMockWormholeReceiver, IWormholeReceiver {
    IBRNWormholeDeliveryProvider public immutable deliveryProvider;
    IWormholeRelayer public immutable relayer;
    WormholeChainId public immutable chainId;
    IWormhole public immutable wormhole;

    mapping(bytes32 => bool) public replayProtection;
    mapping(WormholeChainId => bytes32) public mockWormholeReceiverAddress;
    uint256 public sum = 0;

    modifier onlyRelayerContract() {
        require(msg.sender == address(relayer), "msg.sender is not WormholeRelayer contract.");
        _;
    }

    constructor(
        IWormhole _wormhole,
        IBRNWormholeDeliveryProvider _deliveryProvider,
        IWormholeRelayer _wormholeRelayer,
        WormholeChainId _chainId
    ) {
        deliveryProvider = _deliveryProvider;
        relayer = _wormholeRelayer;
        chainId = _chainId;
        wormhole = _wormhole;
    }

    function sendPayload(
        WormholeChainId _targetChain,
        uint256 _payloadValue,
        Gas _gasLimit,
        TargetNative _receiverValue,
        address _targetContract
    ) public {
        bytes memory payload = abi.encode(_payloadValue);

        // calculate cost to deliver message
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

    function sendPayloadAndAdditionalVAA(
        WormholeChainId _targetChain,
        uint256 _payloadValue,
        uint256[] memory _additionalVAAPayloadValues,
        Gas _gasLimit,
        TargetNative _receiverValue,
        address _targetContract
    ) public {
        // Emit the VAAs
        VaaKey[] memory vaaKeys = new VaaKey[](_additionalVAAPayloadValues.length);
        for (uint256 i = 0; i < _additionalVAAPayloadValues.length; i++) {
            uint64 sequence = wormhole.publishMessage(0, abi.encode(_additionalVAAPayloadValues[i]), 0);
            vaaKeys[i] = VaaKey({
                sequence: sequence,
                chainId: WormholeChainId.unwrap(chainId),
                emitterAddress: toWormholeFormat(address(this))
            });
        }

        bytes memory payload = abi.encode(_payloadValue);

        // calculate cost to deliver message
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
            vaaKeys,
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

    function receiveWormholeMessages(bytes memory payload, bytes[] memory additionalVAAs, bytes32, uint16) internal {
        uint256 value = abi.decode(payload, (uint256));
        sum += value;

        for (uint256 i = 0; i < additionalVAAs.length; i++) {
            (IWormhole.VM memory vm, bool status, string memory reason) = wormhole.parseAndVerifyVM(additionalVAAs[i]);
            if (!status) {
                revert VAAVerificationFailed(reason);
            }
            if (mockWormholeReceiverAddress[WormholeChainId.wrap(vm.emitterChainId)] != vm.emitterAddress) {
                revert VAAEmitterVerificationFailed(
                    mockWormholeReceiverAddress[WormholeChainId.wrap(vm.emitterChainId)], vm.emitterAddress
                );
            }
            uint256 additionalValue = abi.decode(vm.payload, (uint256));
            sum += additionalValue;
        }

        emit ValueAdded(value);
    }

    function setMockWormholeReceiverAddress(WormholeChainId _chainId, address _address) public {
        mockWormholeReceiverAddress[_chainId] = toWormholeFormat(_address);
    }

    receive() external payable {}

    // Exclude from coverage
    function test() external {}
}
