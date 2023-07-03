// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import {BytesLib} from "solidity-bytes-utils/contracts/BytesLib.sol";
import {IWormhole} from "wormhole-contracts/interfaces/IWormhole.sol";
import {IWormholeRelayerDelivery} from "wormhole-contracts/interfaces/relayer/IWormholeRelayerTyped.sol";

import {IWormholeApplication} from "./interfaces/IWormholeApplication.sol";
import {WormholeApplicationStorage} from "./WormholeApplicationStorage.sol";
import {ApplicationBase} from "ta-base-application/ApplicationBase.sol";
import {WormholeChainId, ReceiptVAAPayload, VaaKey} from "./interfaces/WormholeTypes.sol";
import {RelayerAddress, RelayerState} from "ta-common/TATypes.sol";

/// @title WormholeApplication
/// @notice The Wormhole Application module is responsible for executing Wormhole messages and performing transaction allocation.
contract WormholeApplication is IWormholeApplication, ApplicationBase, WormholeApplicationStorage {
    uint256 constant EXPECTED_VM_VERSION = 1;
    uint256 constant SIGNATURE_SIZE = 66;
    uint256 constant VERSION_OFFSET = 0;
    uint256 constant SIGNATURE_LENGTH_OFFSET = 5;
    uint256 constant EMITTER_CHAIN_BODY_OFFSET = 14;
    uint256 constant EMITTER_ADDRESS_BODY_OFFSET = 16;
    uint256 constant SEQUENCE_ID_BODY_OFFSET = 48;

    using BytesLib for bytes;

    /// @inheritdoc IWormholeApplication
    function initializeWormholeApplication(IWormhole _wormhole, IWormholeRelayerDelivery _delivery) external {
        WHStorage storage ws = getWHStorage();
        if (ws.initialized) {
            revert AlreadyInitialized();
        }

        ws.initialized = true;
        ws.wormhole = _wormhole;
        ws.delivery = _delivery;

        emit Initialized(address(_wormhole), address(_delivery));
    }

    /// @inheritdoc IWormholeApplication
    function executeWormhole(
        bytes[] calldata _encodedVMs,
        bytes calldata _encodedDeliveryVAA,
        bytes calldata _deliveryOverrides
    ) external payable override {
        (uint64 deliveryVAASequenceNumber, WormholeChainId emitterChain, bytes32 emitterAddress) =
            _parseVAASelective(_encodedDeliveryVAA);
        _verifyTransaction(_hashSequenceNumber(deliveryVAASequenceNumber));

        // Forward the call the CoreRelayerDelivery with value
        (RelayerAddress relayerAddress,,) = _getCalldataParams();
        WHStorage storage whs = getWHStorage();
        whs.delivery.deliver{value: msg.value}(
            _encodedVMs, _encodedDeliveryVAA, payable(RelayerAddress.unwrap(relayerAddress)), _deliveryOverrides
        );

        // Generate a ReceiptVAA
        bytes memory receiptVAAPayload = abi.encode(
            ReceiptVAAPayload({
                relayerAddress: relayerAddress,
                deliveryVAAKey: VaaKey({
                    sequence: deliveryVAASequenceNumber,
                    chainId: WormholeChainId.unwrap(emitterChain),
                    emitterAddress: emitterAddress
                })
            })
        );
        whs.wormhole.publishMessage(0, receiptVAAPayload, whs.receiptVAAConsistencyLevel);

        emit WormholeDeliveryExecuted(_encodedDeliveryVAA);
    }

    /// @inheritdoc IWormholeApplication
    function allocateWormholeDeliveryVAA(
        RelayerAddress _relayerAddress,
        bytes[] calldata _requests,
        RelayerState calldata _currentState
    ) external view override returns (bytes[] memory, uint256, uint256) {
        return _allocateTransaction(_relayerAddress, _requests, _currentState);
    }

    /// @dev Returns the transaction hash for the given wormhole transaction, by hashing the sequence number of the delivery request.
    /// @param _calldata The calldata of executeWormhole to hash. Ignores any appended data
    /// @return The transaction hash
    function _getTransactionHash(bytes calldata _calldata) internal pure virtual override returns (bytes32) {
        (, bytes memory encodedDeliveryVAA,) = abi.decode(_calldata[4:], (bytes[], bytes, bytes));
        (uint256 sequenceNumber,,) = _parseVAASelective(encodedDeliveryVAA);

        return _hashSequenceNumber(sequenceNumber);
    }

    /// @dev Hashes the sequence number of the delivery request.
    /// @param _sequenceNumber The sequence number of the delivery request
    /// @return The hash
    function _hashSequenceNumber(uint256 _sequenceNumber) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked(_sequenceNumber));
    }

    /// @dev Parses the delivery VAA and returns the sequence number, emitter chain, and emitter address.
    ///      Does not perform signature validation, it is assumed that the VAA has already been validated or that it will be later.
    /// @param _encodedVAA The encoded delivery VAA
    /// @return sequenceNumber The sequence number of the delivery request
    /// @return emitterChain The chain ID of the emitter in wormhole format
    /// @return emitterAddress The address of the emitter in wormhole format
    function _parseVAASelective(bytes memory _encodedVAA)
        internal
        pure
        returns (uint64 sequenceNumber, WormholeChainId emitterChain, bytes32 emitterAddress)
    {
        // VAA Structure
        //
        // Offset (bytes) | Data                  | Size (bytes)
        // -----------------------------------------------------
        // 0              | version               | 1
        // 1              | guardian_set_index    | 4
        // 5              | len_signatures        | 1
        // 6              | signatures[0]         | 66
        // 72             | signatures[1]         | 66
        // ...            | ...                   | ...
        // 6 + 66n        | signatures[n]         | 66
        // (Body starts)
        // 6 + 66x        | timestamp             | 4
        // 10 + 66x       | nonce                 | 4
        // 14 + 66x       | emitter_chain         | 2
        // 16 + 66x       | emitter_address[0]    | 32
        // 48 + 66x       | sequence              | 8
        // 56 + 66x       | consistency_level     | 1
        // 57 + 66x       | payload[0]            | variable
        // ...            | ...                   | ...
        //
        // x = len_signatures
        uint256 version = _encodedVAA.toUint8(VERSION_OFFSET);
        if (version != EXPECTED_VM_VERSION) {
            revert VMVersionIncompatible(EXPECTED_VM_VERSION, version);
        }

        uint256 signersLen = _encodedVAA.toUint8(SIGNATURE_LENGTH_OFFSET);
        emitterChain =
            WormholeChainId.wrap(_encodedVAA.toUint16(EMITTER_CHAIN_BODY_OFFSET + SIGNATURE_SIZE * signersLen));
        emitterAddress = _encodedVAA.toBytes32(EMITTER_CHAIN_BODY_OFFSET + SIGNATURE_SIZE * signersLen + 2);
        sequenceNumber = _encodedVAA.toUint64(SEQUENCE_ID_BODY_OFFSET + SIGNATURE_SIZE * signersLen);
    }
}
