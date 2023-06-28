// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import "./TATypes.sol";

// Controls the precision of the entries in the Cumulative Distribution Function's array representation built on top of the relayer stakes.
uint16 constant CDF_PRECISION_MULTIPLIER = 10 ** 4;

// Controls the precision for specifying percentages. A value of 100 corresponds to precision upto two decimal places, like 12.23%
uint256 constant PERCENTAGE_MULTIPLIER = 100;

// The BICO Token is guaranteed to have 18 decimals
uint256 constant BOND_TOKEN_DECIMAL_MULTIPLIER = 10 ** 18;

// Sentinel value for native token address
TokenAddress constant NATIVE_TOKEN = TokenAddress.wrap(0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE);
