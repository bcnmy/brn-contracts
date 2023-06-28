// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import "ta-delegation/interfaces/ITADelegation.sol";
import "ta-relayer-management/interfaces/ITARelayerManagement.sol";
import "ta-transaction-allocation/interfaces/ITATransactionAllocation.sol";
import "ta-base-application/interfaces/IApplicationBase.sol";
import "ta-common/interfaces/ITAHelpers.sol";
import "src/utils/interfaces/IGuards.sol";

interface ITransactionAllocator is
    ITADelegation,
    ITARelayerManagement,
    ITATransactionAllocation,
    ITAHelpers,
    IApplicationBase,
    IGuards
{}
