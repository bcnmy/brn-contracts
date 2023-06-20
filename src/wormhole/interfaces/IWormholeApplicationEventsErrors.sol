// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

interface IWormholeApplicationEventsErrors {
    error VMVersionIncompatible(uint256 expected, uint256 actual);

    event Initialized(address indexed wormhole, address indexed delivery);
    event WormholeDeliveryExecuted(bytes indexed encodedDeliveryVAA);
}
