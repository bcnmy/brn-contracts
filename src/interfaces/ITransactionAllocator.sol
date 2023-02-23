// SPDX-License-Identifier: MIT

pragma solidity 0.8.17;

import "./ITAAllocationHelper.sol";
import "./ITARelayerManagement.sol";
import "./ITATransactionExecution.sol";
import "./ITAVerificationUtils.sol";
import "./ITAInitializer.sol";

interface ITransactionAllocator is
    ITAAllocationHelper,
    ITARelayerManagement,
    ITATransactionExecution,
    ITAVerificationUtils,
    ITAInitializer
{}
