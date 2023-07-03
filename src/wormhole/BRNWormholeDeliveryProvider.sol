// SPDX-License-Identifier: Apache 2

pragma solidity 0.8.19;

import {Ownable} from "openzeppelin-contracts/access/Ownable.sol";

import {IWormhole} from "wormhole-contracts/interfaces/IWormhole.sol";
import {toWormholeFormat} from "wormhole-contracts/libraries/relayer/Utils.sol";
import {IWormholeRelayer} from "wormhole-contracts/interfaces/relayer/IWormholeRelayerTyped.sol";
import "wormhole-contracts/relayer/wormholeRelayer/WormholeRelayerSerde.sol";
import {
    ExecutionParamsVersion,
    EvmExecutionParamsV1,
    decodeExecutionParamsVersion,
    UnsupportedExecutionParamsVersion,
    decodeEvmExecutionParamsV1,
    encodeEvmExecutionInfoV1,
    EvmExecutionInfoV1
} from "wormhole-contracts/libraries/relayer/ExecutionParameters.sol";
import {IDeliveryProvider} from "wormhole-contracts/interfaces/relayer/IDeliveryProviderTyped.sol";

import {IBRNWormholeDeliveryProvider} from "./interfaces/IBRNWormholeDeliveryProvider.sol";
import {RelayerAddress} from "ta-common/TATypes.sol";
import {ReceiptVAAPayload, WormholeChainId} from "./interfaces/WormholeTypes.sol";

/// @title BRN Wormhole Delivery Provider
/// @notice The BRN Wormhole Delivery Provider is responsible for the following:
///         1. Quoting the price of a message delivery to a target chain
///         2. Quoting Asset Conversion prices
///         3. Storing and accounting for the fees that are paid to the BRN Relayer Provider on the source chain.
///         4. Allow relayers to claim fees by submitting a proof of execution on the destination chain - receipt VAA
/// Heavily based on https://github.com/wormhole-foundation/wormhole/blob/1a50de38e5dca6f8f254998e843285f61a7d32f2/ethereum/contracts/relayer/deliveryProvider/DeliveryProvider.sol
contract BRNWormholeDeliveryProvider is IBRNWormholeDeliveryProvider, Ownable {
    using WeiLib for Wei;
    using GasLib for Gas;
    using GasPriceLib for GasPrice;
    using WeiPriceLib for WeiPrice;
    using TargetNativeLib for TargetNative;
    using LocalNativeLib for LocalNative;

    /////////////////////// State ///////////////////////
    IWormhole public immutable wormhole;
    bytes32 public immutable wormholeRelayerAddress;
    IWormholeRelayer public immutable relayer;
    WormholeChainId public immutable chainId;

    // State Related to the oracles.
    mapping(WormholeChainId chainId => GasPrice) public gasPrice;
    mapping(WormholeChainId chainId => WeiPrice) public nativeCurrencyPrice;
    mapping(WormholeChainId chainId => Gas) public deliveryGasOverhead;
    mapping(WormholeChainId chainId => Wei) public maximumBudget;
    mapping(WormholeChainId chainId => bool) private isWormholeChainSupported;
    mapping(WormholeChainId chainId => bytes32) public brnRelayerProviderAddress;
    mapping(WormholeChainId chainId => AssetConversion) public assetConversionBuffer;

    // State for BRN Accounting
    mapping(WormholeChainId chainId => bytes32) public brnTransactionAllocatorAddress;
    mapping(uint256 deliveryVAASequenceNumber => uint256 nativeTokenAmount) public fundsDepositedForRelaying;

    constructor(IWormhole _wormhole, IWormholeRelayer _relayer, address _owner) Ownable(_owner) {
        wormhole = _wormhole;
        relayer = _relayer;
        wormholeRelayerAddress = toWormholeFormat(address(_relayer));
        chainId = WormholeChainId.wrap(_wormhole.chainId());
    }

    /////////////////////// DeliveryProvider Specification ///////////////////////
    /// @inheritdoc IBRNWormholeDeliveryProvider
    function quoteEvmDeliveryPrice(uint16 targetChain, Gas gasLimit, TargetNative receiverValue)
        public
        view
        override
        returns (LocalNative nativePriceQuote, GasPrice targetChainRefundPerUnitGasUnused)
    {
        targetChainRefundPerUnitGasUnused = gasPrice[WormholeChainId.wrap(targetChain)];
        Wei costOfProvidingFullGasLimit = gasLimit.toWei(targetChainRefundPerUnitGasUnused);
        Wei transactionFee = quoteDeliveryOverhead(WormholeChainId.wrap(targetChain))
            + gasLimit.toWei(quoteGasPrice(WormholeChainId.wrap(targetChain)));
        Wei receiverValueCost = quoteAssetCost(WormholeChainId.wrap(targetChain), receiverValue);
        nativePriceQuote =
            (transactionFee.max(costOfProvidingFullGasLimit) + receiverValueCost + wormholeMessageFee()).asLocalNative();
        require(
            receiverValue.asNative() + costOfProvidingFullGasLimit <= maximumBudget[WormholeChainId.wrap(targetChain)],
            "Exceeds maximum budget"
        );
    }

    /// @inheritdoc IDeliveryProvider
    function quoteDeliveryPrice(uint16 targetChain, TargetNative receiverValue, bytes memory encodedExecutionParams)
        external
        view
        override
        returns (LocalNative nativePriceQuote, bytes memory encodedExecutionInfo)
    {
        ExecutionParamsVersion version = decodeExecutionParamsVersion(encodedExecutionParams);
        if (version != ExecutionParamsVersion.EVM_V1) {
            revert UnsupportedExecutionParamsVersion(uint8(version));
        }

        EvmExecutionParamsV1 memory parsed = decodeEvmExecutionParamsV1(encodedExecutionParams);
        GasPrice targetChainRefundPerUnitGasUnused;
        (nativePriceQuote, targetChainRefundPerUnitGasUnused) =
            quoteEvmDeliveryPrice(targetChain, parsed.gasLimit, receiverValue);
        return (
            nativePriceQuote,
            encodeEvmExecutionInfoV1(EvmExecutionInfoV1(parsed.gasLimit, targetChainRefundPerUnitGasUnused))
        );
    }

    /// @inheritdoc IDeliveryProvider
    function quoteAssetConversion(uint16 targetChain, LocalNative currentChainAmount)
        external
        view
        override
        returns (TargetNative targetChainAmount)
    {
        return quoteAssetConversion(chainId, WormholeChainId.wrap(targetChain), currentChainAmount);
    }

    /// @inheritdoc IDeliveryProvider
    function getRewardAddress() public view override returns (address payable) {
        // All rewards are stored in this contract.
        return payable(address(this));
    }

    /// @inheritdoc IDeliveryProvider
    function getTargetChainAddress(uint16 targetChain) public view override returns (bytes32 deliveryProviderAddress) {
        return brnRelayerProviderAddress[WormholeChainId.wrap(targetChain)];
    }

    /// @inheritdoc IDeliveryProvider
    function isChainSupported(uint16 targetChain) external view override returns (bool supported) {
        return isWormholeChainSupported[WormholeChainId.wrap(targetChain)];
    }

    /////////////////////// Helpers ///////////////////////

    function quoteAssetConversion(
        WormholeChainId sourceChain,
        WormholeChainId targetChain,
        LocalNative sourceChainAmount
    ) internal view returns (TargetNative targetChainAmount) {
        AssetConversion storage _assetConversion = assetConversionBuffer[targetChain];
        return sourceChainAmount.asNative().convertAsset(
            nativeCurrencyPrice[sourceChain],
            nativeCurrencyPrice[targetChain],
            (_assetConversion.buffer),
            (uint32(_assetConversion.buffer) + _assetConversion.denominator),
            false
        ).asTargetNative();
        // round down
    }

    function wormholeMessageFee() public view returns (Wei) {
        return Wei.wrap(wormhole.messageFee());
    }

    //Returns the delivery overhead fee required to deliver a message to the target chain, denominated in this chain's wei.
    function quoteDeliveryOverhead(WormholeChainId targetChain) public view returns (Wei nativePriceQuote) {
        Gas overhead = deliveryGasOverhead[targetChain];
        Wei targetFees = overhead.toWei(gasPrice[targetChain]);
        Wei result = assetConversion(targetChain, targetFees, chainId);
        require(result.unwrap() <= type(uint128).max, "Overflow");
        return result;
    }

    //Returns the price of purchasing 1 unit of gas on the target chain, denominated in this chain's wei.
    function quoteGasPrice(WormholeChainId targetChain) public view returns (GasPrice) {
        Wei gasPriceInSourceChainCurrency = assetConversion(targetChain, gasPrice[targetChain].priceAsWei(), chainId);
        require(gasPriceInSourceChainCurrency.unwrap() <= type(uint88).max, "Overflow");
        return GasPrice.wrap(uint88(gasPriceInSourceChainCurrency.unwrap()));
    }

    // relevant for chains that have dynamic execution pricing (e.g. Ethereum)
    function assetConversion(WormholeChainId sourceChain, Wei sourceAmount, WormholeChainId targetChain)
        internal
        view
        returns (Wei targetAmount)
    {
        return sourceAmount.convertAsset(
            nativeCurrencyPrice[sourceChain],
            nativeCurrencyPrice[targetChain],
            1,
            1,
            // round up
            true
        );
    }

    function quoteAssetCost(WormholeChainId targetChain, TargetNative targetChainAmount)
        internal
        view
        returns (Wei currentChainAmount)
    {
        AssetConversion storage _assetConversion = assetConversionBuffer[targetChain];
        return targetChainAmount.asNative().convertAsset(
            nativeCurrencyPrice[chainId],
            nativeCurrencyPrice[targetChain],
            (uint32(_assetConversion.buffer) + _assetConversion.denominator),
            (_assetConversion.buffer),
            // round up
            true
        );
    }

    /////////////////////// BRN Fee Accounting ///////////////////////
    receive() external payable {
        if (msg.sender != address(relayer)) {
            revert CallerMustBeWormholeRelayer();
        }

        if (msg.value == 0) {
            revert NoFunds();
        }

        // Prior to this call, a delivery VAA or Re delivery VAA must have been emitted by the Wormhole Relayer contract.
        // We can use the sequence number of the VAA to identify the VAA that was emitted.
        uint256 deliveryVAASequenceNumber = wormhole.nextSequence(address(relayer)) - 1;
        fundsDepositedForRelaying[deliveryVAASequenceNumber] += msg.value;

        emit FundsDepositedForRelaying(deliveryVAASequenceNumber, msg.value);
    }

    /// @inheritdoc IBRNWormholeDeliveryProvider
    function claimFee(bytes[] calldata _encodedReceiptVAAs, bytes[][] calldata _encodedRedeliveryVAAs)
        external
        override
    {
        uint256 totalFee;
        uint256 length = _encodedReceiptVAAs.length;

        if (length != _encodedRedeliveryVAAs.length) {
            revert ParamterLengthMismatch();
        }

        for (uint256 i; i != length;) {
            totalFee += _checkClaim(_encodedReceiptVAAs[i], _encodedRedeliveryVAAs[i]);
            unchecked {
                ++i;
            }
        }

        // Send the total fee to the relayer
        (bool status,) = msg.sender.call{value: totalFee}("");
        if (!status) {
            revert NativeTransferFailed();
        }
    }

    /// @dev Checks the validity of the receipt VAA and the associated redelivery VAAs
    /// @param _encodedReceiptVAA The encoded receipt VAA
    /// @param _encodedRedeliveryVAA The encoded redelivery VAAs associated with the receipt VAA
    /// @return The total fee claimable by the relayer
    function _checkClaim(bytes calldata _encodedReceiptVAA, bytes[] calldata _encodedRedeliveryVAA)
        internal
        returns (uint256)
    {
        IWormhole.VM memory receiptVM = _parseAndVerifyVAA(_encodedReceiptVAA);

        bytes32 targetChainBRNTransactionAllocatorAddress =
            brnTransactionAllocatorAddress[WormholeChainId.wrap(receiptVM.emitterChainId)];

        ReceiptVAAPayload memory payload = abi.decode(receiptVM.payload, (ReceiptVAAPayload));

        if (WormholeChainId.wrap(payload.deliveryVAAKey.chainId) != chainId) {
            revert WormholeDeliveryVAASourceChainMismatch(chainId, WormholeChainId.wrap(payload.deliveryVAAKey.chainId));
        }

        if (receiptVM.emitterAddress != targetChainBRNTransactionAllocatorAddress) {
            revert WormholeReceiptVAAEmitterMismatch(
                targetChainBRNTransactionAllocatorAddress, receiptVM.emitterAddress
            );
        }

        if (payload.relayerAddress != RelayerAddress.wrap(msg.sender)) {
            revert NotAuthorized();
        }

        uint256 amount = fundsDepositedForRelaying[payload.deliveryVAAKey.sequence];
        delete fundsDepositedForRelaying[payload.deliveryVAAKey.sequence];

        emit DeliveryFeeClaimed(payload.deliveryVAAKey.sequence, payload.relayerAddress, amount);

        // Process any re-delivery VAAs
        uint256 redeliveryVAACount = _encodedRedeliveryVAA.length;
        for (uint256 i; i != redeliveryVAACount;) {
            amount += _checkRedeliveryVAAClaim(payload.deliveryVAAKey, _encodedRedeliveryVAA[i], payload.relayerAddress);

            unchecked {
                ++i;
            }
        }

        return amount;
    }

    /// @dev Checks the validity of the redelivery VAA against the delivery VAA
    /// @param _deliveryInstructionVAAKey The VAA Key of the delivery VAA
    /// @param _encodedRedeliveryVAA The encoded redelivery VAA
    /// @param _relayer The address of the relayer claiming the fee
    /// @return The fee claimable by the relayer
    function _checkRedeliveryVAAClaim(
        VaaKey memory _deliveryInstructionVAAKey,
        bytes calldata _encodedRedeliveryVAA,
        RelayerAddress _relayer
    ) internal returns (uint256) {
        IWormhole.VM memory redeliveryVM = _parseAndVerifyVAA(_encodedRedeliveryVAA);

        if (WormholeChainId.wrap(redeliveryVM.emitterChainId) != chainId) {
            revert WormholeRedeliveryVAAEmitterChainMismatch(chainId, WormholeChainId.wrap(redeliveryVM.emitterChainId));
        }

        if (redeliveryVM.emitterAddress != wormholeRelayerAddress) {
            revert WormholeRedeliveryVAAEmitterMismatch(wormholeRelayerAddress, redeliveryVM.emitterAddress);
        }

        RedeliveryInstruction memory redeliveryPayload =
            WormholeRelayerSerde.decodeRedeliveryInstruction(redeliveryVM.payload);

        if (!_compareVaaKey(_deliveryInstructionVAAKey, redeliveryPayload.deliveryVaaKey)) {
            revert WormholeRedeliveryVAAKeyMismatch(_deliveryInstructionVAAKey, redeliveryPayload.deliveryVaaKey);
        }

        uint256 amount = fundsDepositedForRelaying[redeliveryVM.sequence];
        delete fundsDepositedForRelaying[redeliveryVM.sequence];

        emit RedeliveryFeeClaimed(redeliveryVM.sequence, _relayer, amount);

        return amount;
    }

    /// @dev Parses and verifies a VAA
    /// @param _encodedVAA The encoded VAA
    /// @return The parsed VAA if valid
    function _parseAndVerifyVAA(bytes calldata _encodedVAA) internal view returns (IWormhole.VM memory) {
        (IWormhole.VM memory vm, bool valid, string memory reason) = wormhole.parseAndVerifyVM(_encodedVAA);

        if (!valid) {
            revert WormholeVAAVerificationFailed(reason);
        }

        return vm;
    }

    /// @dev Compares two VAA keys
    /// @param _a The first VAA key
    /// @param _b The second VAA key
    /// @return True if the VAA keys are equal
    function _compareVaaKey(VaaKey memory _a, VaaKey memory _b) internal pure returns (bool) {
        return _a.chainId == _b.chainId && _a.emitterAddress == _b.emitterAddress && _a.sequence == _b.sequence;
    }

    /////////////////////// Setters ///////////////////////
    function setGasPrice(WormholeChainId targetChain, GasPrice gasPrice_) external override onlyOwner {
        gasPrice[targetChain] = gasPrice_;
    }

    function setNativeCurrencyPrice(WormholeChainId targetChain, WeiPrice nativeCurrencyPrice_)
        external
        override
        onlyOwner
    {
        nativeCurrencyPrice[targetChain] = nativeCurrencyPrice_;
    }

    function setDeliverGasOverhead(WormholeChainId targetChain, Gas deliverGasOverhead_) external override onlyOwner {
        deliveryGasOverhead[targetChain] = deliverGasOverhead_;
    }

    function setMaximumBudget(WormholeChainId targetChain, Wei maximumBudget_) external override onlyOwner {
        maximumBudget[targetChain] = maximumBudget_;
    }

    function setIsWormholeChainSupported(WormholeChainId targetChain, bool isWormholeChainSupported_)
        external
        override
        onlyOwner
    {
        isWormholeChainSupported[targetChain] = isWormholeChainSupported_;
    }

    function setBrnRelayerProviderAddress(WormholeChainId targetChain, bytes32 brnRelayerProviderAddress_)
        external
        override
        onlyOwner
    {
        brnRelayerProviderAddress[targetChain] = brnRelayerProviderAddress_;
    }

    function setAssetConversionBuffer(WormholeChainId targetChain, AssetConversion calldata assetConversionBuffer_)
        external
        override
        onlyOwner
    {
        assetConversionBuffer[targetChain] = assetConversionBuffer_;
    }

    function setBrnTransactionAllocatorAddress(WormholeChainId targetChain, bytes32 brnTransactionAllocatorAddress_)
        external
        override
        onlyOwner
    {
        brnTransactionAllocatorAddress[targetChain] = brnTransactionAllocatorAddress_;
    }
}
