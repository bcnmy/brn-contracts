// SPDX-License-Identifier: Apache 2

// Heavily based on https://github.com/wormhole-foundation/wormhole/blob/1a50de38e5dca6f8f254998e843285f61a7d32f2/ethereum/contracts/relayer/deliveryProvider/DeliveryProvider.sol

pragma solidity 0.8.19;

import "openzeppelin-contracts/access/Ownable.sol";

import {IWormhole} from "wormhole-contracts/interfaces/IWormhole.sol";
import {IWormholeRelayer} from "wormhole-contracts/interfaces/relayer/IWormholeRelayerTyped.sol";
import "wormhole-contracts/libraries/relayer/ExecutionParameters.sol";

import "./interfaces/IBRNWormholeDeliveryProvider.sol";

contract BRNWormholeDeliveryProvider is IBRNWormholeDeliveryProvider, Ownable {
    using WeiLib for Wei;
    using GasLib for Gas;
    using GasPriceLib for GasPrice;
    using WeiPriceLib for WeiPrice;
    using TargetNativeLib for TargetNative;
    using LocalNativeLib for LocalNative;

    /////////////////////// State ///////////////////////
    IWormhole public immutable wormhole;
    IWormholeRelayer public immutable relayer;
    WormholeChainId public immutable chainId;

    // State Related to the oracles.
    mapping(WormholeChainId chainId => GasPrice) public gasPrice;
    mapping(WormholeChainId chainId => WeiPrice) public nativeCurrencyPrice;
    mapping(WormholeChainId chainId => Gas) public deliveyrGasOverhead;
    mapping(WormholeChainId chainId => Wei) public maximumBudget;
    mapping(WormholeChainId chainId => bool) private isWormholeChainSupported;
    mapping(WormholeChainId chainId => bytes32) public brnRelayerProviderAddress;
    mapping(WormholeChainId chainId => AssetConversion) public assetConversionBuffer;

    // State for BRN Accounting
    mapping(WormholeChainId chainId => bytes32) brnTransactionAllocatorAddress;
    mapping(uint256 deliveryVAASequenceNumber => uint256 nativeTokenAmount) public fundsDepositedForRelaying;

    constructor(IWormhole _wormhole, IWormholeRelayer _relayer, address _owner) Ownable(_owner) {
        wormhole = _wormhole;
        relayer = _relayer;
        chainId = WormholeChainId.wrap(_wormhole.chainId());
    }

    /////////////////////// RelayerProvider Specification ///////////////////////
    function quoteEvmDeliveryPrice(uint16 targetChain, Gas gasLimit, TargetNative receiverValue)
        public
        view
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

    function quoteAssetConversion(uint16 targetChain, LocalNative currentChainAmount)
        external
        view
        override
        returns (TargetNative targetChainAmount)
    {
        return quoteAssetConversion(chainId, WormholeChainId.wrap(targetChain), currentChainAmount);
    }

    //Returns the address on this chain that rewards should be sent to
    function getRewardAddress() public view override returns (address payable) {
        return payable(address(this));
    }

    function getTargetChainAddress(uint16 targetChain) public view override returns (bytes32 deliveryProviderAddress) {
        return brnRelayerProviderAddress[WormholeChainId.wrap(targetChain)];
    }

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
        Gas overhead = deliveyrGasOverhead[targetChain];
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

        uint256 deliveryVAASequenceNumber = wormhole.nextSequence(address(relayer)) - 1;
        fundsDepositedForRelaying[deliveryVAASequenceNumber] += msg.value;

        emit FundsDepositedForRelaying(deliveryVAASequenceNumber, msg.value);
    }

    function claimFee(bytes[] calldata _encodedReceiptVAAs) external override {
        uint256 totalFee;
        uint256 length = _encodedReceiptVAAs.length;

        for (uint256 i; i != length;) {
            (IWormhole.VM memory vm, bool valid, string memory reason) =
                wormhole.parseAndVerifyVM(_encodedReceiptVAAs[i]);

            if (!valid) {
                revert WormholeDeliveryVAAVerificationFailed(i, reason);
            }

            if (vm.emitterAddress != brnTransactionAllocatorAddress[WormholeChainId.wrap(vm.emitterChainId)]) {
                revert WormholeDeliveryVAAEmitterMismatch(
                    i, brnTransactionAllocatorAddress[WormholeChainId.wrap(vm.emitterChainId)], vm.emitterAddress
                );
            }

            ReceiptVAAPayload memory payload = abi.decode(vm.payload, (ReceiptVAAPayload));

            if (payload.deliveryVAASourceChainId != chainId) {
                revert WormholeDeliveryVAASourceChainMismatch(i, chainId, payload.deliveryVAASourceChainId);
            }

            if (payload.relayer != RelayerAddress.wrap(msg.sender)) {
                revert NotAuthorized(i);
            }

            uint256 amount = fundsDepositedForRelaying[payload.deliveryVAASequenceNumber];
            totalFee += amount;
            delete fundsDepositedForRelaying[payload.deliveryVAASequenceNumber];

            emit FeeClaimed(payload.deliveryVAASequenceNumber, payload.relayer, amount);

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
        deliveyrGasOverhead[targetChain] = deliverGasOverhead_;
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
}
