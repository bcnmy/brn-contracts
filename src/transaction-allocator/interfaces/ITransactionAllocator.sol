// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import "../modules/delegation/interfaces/ITADelegation.sol";
import "../modules/relayer-management/interfaces/ITARelayerManagement.sol";
import "../modules/transaction-allocation/interfaces/ITATransactionAllocation.sol";
import "../modules/application/base-application/interfaces/IApplicationBase.sol";
import "../common/interfaces/ITAHelpers.sol";

interface ITransactionAllocator is
    ITADelegation,
    ITARelayerManagement,
    ITATransactionAllocation,
    ITAHelpers,
    IApplicationBase
{}
