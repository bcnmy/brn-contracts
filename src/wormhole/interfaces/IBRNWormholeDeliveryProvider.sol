// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import {IDeliveryProvider} from "wormhole-contracts/interfaces/relayer/IDeliveryProviderTyped.sol";

import "./IBRNWormholeDeliveryProviderEventsErrors.sol";
import "./WormholeTypes.sol";

interface IBRNWormholeDeliveryProvider is IDeliveryProvider, IBRNWormholeDeliveryProviderEventsErrors {
    struct AssetConversion {
        // The following two fields are a percentage buffer that is used to upcharge the user for the value attached to the message sent.
        // The cost of getting ‘targetAmount’ on the target chain for the receiverValue is
        // (denominator + buffer) / (denominator) * (the converted amount in source chain currency using the ‘quoteAssetPrice’ values)
        uint16 buffer;
        uint16 denominator;
    }

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
}
