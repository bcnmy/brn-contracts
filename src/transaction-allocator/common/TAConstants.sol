// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import "./TATypes.sol";
import "src/library/FixedPointArithmetic.sol";

uint256 constant CDF_PRECISION_MULTIPLIER = 10 ** 4;
uint256 constant STAKE_SCALING_FACTOR = 10 ** 18;
uint256 constant DELGATION_SCALING_FACTOR = 10 ** 18;
uint256 constant PERCENTAGE_MULTIPLIER = 100;
uint256 constant ABSENCE_PENALTY = 250; // % * PERCENTAGE_MULTIPLIER
uint256 constant ABSENTEE_PROOF_REPORTER_GENERATION_ITERATION = 0;
uint256 constant MINIMUM_STAKE_AMOUNT = 10000 ether;
uint256 constant MINIMUM_DELGATION_AMOUNT = 1 ether;
uint256 constant RELAYER_PREMIUM_PERCENTAGE = 900; // % * PERCENTAGE_MULTIPLIER
uint256 constant BASE_REWARD_RATE_PER_MIN_STAKE_PER_SEC = 1003000000000; // Assume 18 decimals
uint256 constant RELAYER_WITHDRAW_DELAY_IN_BLOCKS = 10;
uint256 constant INTERVAL_IDENTIIFER_STARTING_BLOCK_OFFSET = 128;
uint256 constant INTERVAL_LENGTH_MASK = (1 << INTERVAL_IDENTIIFER_STARTING_BLOCK_OFFSET) - 1;
TokenAddress constant NATIVE_TOKEN = TokenAddress.wrap(0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE);
FixedPointType constant LIVENESS_Z_PARAMETER = FixedPointType.wrap(33 * MULTIPLIER / 10);
