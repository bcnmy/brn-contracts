// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {IGuards} from "./interfaces/IGuards.sol";

/// @title Guards
/// @dev Common guard modifiers
abstract contract Guards is IGuards {
    ///  @dev Used by core functions to prevent the execute() from function calling them.
    ///       The execute() function of the Transaction Allocation module accepts arbitrary calldata from the user and delegatecalls to itself,
    ///       which means that the user can call any function of the contract with any arguments and the function will be executed in the context of the contract.
    ///       All core public and external functions MUST use this modifier to prevent the execute() function from calling them.
    ///       This is tested in InternalInvocationTest.sol
    modifier noSelfCall() {
        if (msg.sender == address(this)) {
            revert NoSelfCall();
        }
        _;
    }
}
