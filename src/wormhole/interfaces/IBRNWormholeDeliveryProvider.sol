// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import {IDeliveryProvider} from "wormhole-contracts/interfaces/relayer/IDeliveryProviderTyped.sol";

import {IBRNWormholeDeliveryProviderEventsErrors} from "./IBRNWormholeDeliveryProviderEventsErrors.sol";
import {Gas, TargetNative, LocalNative, GasPrice, WeiPrice, Wei, WormholeChainId} from "./WormholeTypes.sol";

/// @title IBRNWormholeDeliveryProvider
interface IBRNWormholeDeliveryProvider is IDeliveryProvider, IBRNWormholeDeliveryProviderEventsErrors {
    struct AssetConversion {
        // The following two fields are a percentage buffer that is used to upcharge the user for the value attached to the message sent.
        // The cost of getting ‘targetAmount’ on the target chain for the receiverValue is
        // (denominator + buffer) / (denominator) * (the converted amount in source chain currency using the ‘quoteAssetPrice’ values)
        uint16 buffer;
        uint16 denominator;
    }

    /// @notice Returns the quote to deliver a message to a target chain
    /// @param targetChain The chain to deliver to
    /// @param gasLimit The gas limit for the message on the target chain
    /// @param receiverValue The value to send to the receiver on the target chain, in the target chain's native currency
    /// @return nativePriceQuote The price of the delivery in the source chain's native currency
    /// @return targetChainRefundPerUnitGasUnused The amount refunded (in target chain currency) per ununsed gas on the target chain
    function quoteEvmDeliveryPrice(uint16 targetChain, Gas gasLimit, TargetNative receiverValue)
        external
        returns (LocalNative nativePriceQuote, GasPrice targetChainRefundPerUnitGasUnused);

    /// @notice Allows a relayer to claim fees by submitting a proof of execution on the destination chain - receipt VAA
    /// @param _encodedReceiptVAAs The list of encoded receipt VAAs
    /// @param _encodedRedeliveryVAAs A list of redelivery VAAs corresponding to each receipt VAA. If the user requsted a redelivery,
    ///                               additional fees will be paid to the BRN Relayer Provider on the source chain. The relayer is able to
    ///                               claim these additinoal fees by submitting the redelivery VAA corresponding to the extra payment.
    function claimFee(bytes[] calldata _encodedReceiptVAAs, bytes[][] calldata _encodedRedeliveryVAAs) external;

    /////////////////////// Setters ///////////////////////
    function setGasPrice(WormholeChainId targetChain, GasPrice gasPrice_) external;

    function setNativeCurrencyPrice(WormholeChainId targetChain, WeiPrice nativeCurrencyPrice_) external;

    function setDeliverGasOverhead(WormholeChainId targetChain, Gas deliverGasOverhead_) external;

    function setMaximumBudget(WormholeChainId targetChain, Wei maximumBudget_) external;

    function setIsWormholeChainSupported(WormholeChainId targetChain, bool isWormholeChainSupported_) external;

    function setBrnRelayerProviderAddress(WormholeChainId targetChain, bytes32 brnRelayerProviderAddress_) external;

    function setAssetConversionBuffer(WormholeChainId targetChain, AssetConversion calldata assetConversionBuffer_)
        external;

    function setBrnTransactionAllocatorAddress(WormholeChainId targetChain, bytes32 brnTransactionAllocatorAddress_)
        external;
}
