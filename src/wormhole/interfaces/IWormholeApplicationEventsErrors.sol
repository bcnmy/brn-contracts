// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

/// @title IWormholeApplicationEventsErrors
interface IWormholeApplicationEventsErrors {
    error VMVersionIncompatible(uint256 expected, uint256 actual);
    error AlreadyInitialized();

    event Initialized(address indexed wormhole, address indexed delivery);
    event WormholeDeliveryExecuted(bytes indexed encodedDeliveryVAA);
}
