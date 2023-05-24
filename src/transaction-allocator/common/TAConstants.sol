// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import "./TATypes.sol";

uint256 constant CDF_PRECISION_MULTIPLIER = 10 ** 4;
uint256 constant STAKE_SCALING_FACTOR = 10 ** 18;
uint256 constant DELGATION_SCALING_FACTOR = 10 ** 18;
uint256 constant PERCENTAGE_MULTIPLIER = 100;
TokenAddress constant NATIVE_TOKEN = TokenAddress.wrap(0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE);
