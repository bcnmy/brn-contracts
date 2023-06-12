// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import "./TATypes.sol";

uint16 constant CDF_PRECISION_MULTIPLIER = 10 ** 4;
uint256 constant PERCENTAGE_MULTIPLIER = 100;
uint256 constant BOND_TOKEN_DECIMAL_MULTIPLIER = 10 ** 18;
TokenAddress constant NATIVE_TOKEN = TokenAddress.wrap(0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE);
