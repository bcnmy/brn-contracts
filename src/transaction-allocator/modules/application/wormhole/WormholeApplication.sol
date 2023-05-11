// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import "lib/solidity-bytes-utils/contracts/BytesLib.sol";
import "./interfaces/IWormholeApplication.sol";
import "./WormholeApplicationStorage.sol";
import "../base-application/ApplicationBase.sol";

contract WormholeApplication is IWormholeApplication, ApplicationBase, WormholeApplicationStorage {
    uint256 constant EXPECTED_VM_VERSION = 1;

    using BytesLib for bytes;

    // TODO: Only Governance
    function initialize(IWormhole _wormhole, IDelivery _delivery) external {
        WHStorage storage ws = getWHStorage();
        if (ws.initialized) {
            revert AlreadyInitialized();
        }

        ws.initialized = true;
        ws.wormhole = _wormhole;
        ws.delivery = _delivery;

        emit Initialized(address(_wormhole), address(_delivery));
    }

    ////// Alloction Logic //////
    function _getTransactionHash(bytes calldata _calldata) internal pure virtual override returns (bytes32) {
        (IDelivery.TargetDeliveryParameters memory params) =
            abi.decode(_calldata[4:], (IDelivery.TargetDeliveryParameters));

        return keccak256(abi.encode(_getVAASequenceNumber(params.encodedDeliveryVAA)));
    }

    // TODO: Optimize
    function _getVAASequenceNumber(bytes memory _encodedVAA) internal pure returns (uint256 sequenceNumber) {
        uint256 index = 0;

        uint256 version = _encodedVAA.toUint8(index);
        if (version != EXPECTED_VM_VERSION) {
            revert VMVersionIncompatible(EXPECTED_VM_VERSION, version);
        }

        index += 4 + 1;
        uint256 signersLen = _encodedVAA.toUint8(index);
        index += 1 + (1 + 32 + 32 + 1) * signersLen + 4 + 4 + 2 + 32;
        sequenceNumber = _encodedVAA.toUint64(index);
    }

    function allocateWormholeDeliveryVAA(AllocateTransactionParams calldata _params)
        external
        view
        override
        returns (bytes[] memory, uint256, uint256)
    {
        return _allocateTransaction(_params);
    }

    /// Execution Logic
    function executeWormhole(IDelivery.TargetDeliveryParameters calldata _targetParams)
        external
        payable
        override
        applicationHandler(msg.data)
    {
        // Forward the call the CoreRelayerDelivery with value
        WHStorage storage whs = getWHStorage();
        whs.delivery.deliver{value: msg.value}(_targetParams);

        // Generate a ReceiptVAA
        (RelayerAddress relayerAddress,,) = _getCalldataParams();
        bytes memory receiptVAAPayload =
            abi.encode(_getVAASequenceNumber(_targetParams.encodedDeliveryVAA), relayerAddress);
        whs.wormhole.publishMessage(0, receiptVAAPayload, whs.receiptVAAConsistencyLevel);

        emit WormholeDeliveryExecuted(_targetParams.encodedDeliveryVAA);
    }
}
