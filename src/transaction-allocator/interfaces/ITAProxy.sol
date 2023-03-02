// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import "src/transaction-allocator/common/TAStructs.sol";

interface ITAProxy {
    error ParameterLengthMismatch();
    error SelectorAlreadyRegistered(address oldModule, address newModule, bytes4 selector);

    event ModuleAdded(address indexed moduleAddr, bytes4[] selectors);
}
