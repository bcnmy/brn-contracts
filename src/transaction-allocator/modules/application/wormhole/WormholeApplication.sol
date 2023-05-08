// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import "lib/solidity-bytes-utils/contracts/BytesLib.sol";
import "./interfaces/IWormholeApplication.sol";
import "./WormholeApplicationStorage.sol";
import "../base-application/ApplicationBase.sol";

contract WormholeApplication is IWormholeApplication, ApplicationBase, WormholeApplicationStorage {
    uint256 constant EXPECTED_VM_VERSION = 1;

    using BytesLib for bytes;

    ////// Alloction Logic //////
    function _getTransactionHash(bytes calldata _encodedDeliveryVAA) internal pure virtual override returns (bytes32) {
        return keccak256(abi.encode(_getVAASequenceNumber(_encodedDeliveryVAA)));
    }

    function _getVAASequenceNumber(bytes calldata _encodedVAA) internal pure returns (uint256 sequenceNumber) {
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

    /// Execution Logic
    function executeWormhole(IDelivery.TargetDeliveryParameters calldata _targetParams)
        external
        payable
        override
        applicationHandler(_targetParams.encodedDeliveryVAA)
    {
        // Forward the call the CoreRelayerDelivery with value
        WHStorage storage whs = getWHStorage();
        whs.delivery.deliver{value: msg.value}(_targetParams);

        // Generate a ReceiptVAA
        (RelayerAddress relayerAddress,,) = _getCalldataParams();
        bytes memory receiptVAAPayload =
            abi.encode(_getVAASequenceNumber(_targetParams.encodedDeliveryVAA), relayerAddress);
        whs.wormhole.publishMessage(0, receiptVAAPayload, whs.receiptVAAConsistencyLevel);
    }
}
