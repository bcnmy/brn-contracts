// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import "../TATypes.sol";

interface ITAHelpers {
    error InvalidStakeArrayHash();
    error InvalidCdfArrayHash();
    error NativeTransferFailed(address to, uint256 amount);
    error InsufficientBalance(TokenAddress token, uint256 balance, uint256 amount);
}
