// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import {ITADelegation} from "ta-delegation/interfaces/ITADelegation.sol";
import {ITARelayerManagement} from "ta-relayer-management/interfaces/ITARelayerManagement.sol";
import {ITATransactionAllocation} from "ta-transaction-allocation/interfaces/ITATransactionAllocation.sol";
import {IApplicationBase} from "ta-base-application/interfaces/IApplicationBase.sol";
import {ITAHelpers} from "ta-common/interfaces/ITAHelpers.sol";
import {IGuards} from "src/utils/interfaces/IGuards.sol";

interface ITransactionAllocator is
    ITADelegation,
    ITARelayerManagement,
    ITATransactionAllocation,
    ITAHelpers,
    IApplicationBase,
    IGuards
{}
