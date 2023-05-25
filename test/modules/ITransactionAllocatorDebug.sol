// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import "ta/interfaces/ITransactionAllocator.sol";
import "ta-wormhole-application/interfaces/IWormholeApplication.sol";
import "./minimal-application/interfaces/IMinimalApplication.sol";
import "./debug/interfaces/ITADebug.sol";

interface ITransactionAllocatorDebug is ITransactionAllocator, ITADebug, IWormholeApplication, IMinimalApplication {}
