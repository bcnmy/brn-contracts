// SPDX-License-Identifier: MIT

pragma solidity 0.8.17;

import "./modules/delegation/ITADelegation.sol";
import "./modules/relayer-management/ITARelayerManagement.sol";
import "./modules/transaction-allocation/ITATransactionAllocation.sol";
import "./ITAProxy.sol";

interface ITransactionAllocator is ITADelegation, ITARelayerManagement, ITATransactionAllocation, ITAProxy {}
