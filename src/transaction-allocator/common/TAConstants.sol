// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import "./TATypes.sol";

uint256 constant CDF_PRECISION_MULTIPLIER = 10 ** 4;
uint256 constant STAKE_SCALING_FACTOR = 10 ** 18;
uint256 constant DELGATION_SCALING_FACTOR = 10 ** 18;
uint256 constant ABSENCE_PENALTY = 250; // % * 100
uint256 constant ABSENTEE_PROOF_REPORTER_GENERATION_ITERATION = 0;
uint256 constant MINIMUM_STAKE_AMOUNT = 10000 ether;
uint256 constant MINIMUM_DELGATION_AMOUNT = 1 ether;
uint256 constant CDF_UPDATE_DELAY_IN_WINDOWS = 2;
TokenAddress constant NATIVE_TOKEN = TokenAddress.wrap(0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE);
