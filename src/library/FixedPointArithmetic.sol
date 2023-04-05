// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import "openzeppelin-contracts/contracts/utils/math/Math.sol";

using Math for uint256;
using Uint256WrapperHelper for uint256;
using FixedPointTypeHelper for FixedPointType;

uint256 constant PRECISION = 24;
uint256 constant MULTIPLIER = 10 ** PRECISION;
uint256 constant MULTIPLIER_SQRT = 10 ** (PRECISION / 2);

type FixedPointType is uint256;

// Wrappers
library Uint256WrapperHelper {
    function toFixedPointType(uint256 _value) internal pure returns (FixedPointType) {
        return FixedPointType.wrap(_value * MULTIPLIER);
    }
}

library FixedPointTypeHelper {
    function toUint256(FixedPointType _value) internal pure returns (uint256) {
        return FixedPointType.unwrap(_value) / MULTIPLIER;
    }
}

function fixedPointAdd(FixedPointType _a, FixedPointType _b) pure returns (FixedPointType) {
    return FixedPointType.wrap(FixedPointType.unwrap(_a) + FixedPointType.unwrap(_b));
}

function fixedPointSubtract(FixedPointType _a, FixedPointType _b) pure returns (FixedPointType) {
    return FixedPointType.wrap(FixedPointType.unwrap(_a) - FixedPointType.unwrap(_b));
}

function fixedPointMultiply(FixedPointType _a, FixedPointType _b) pure returns (FixedPointType) {
    return FixedPointType.wrap((FixedPointType.unwrap(_a) * FixedPointType.unwrap(_b)) / MULTIPLIER);
}

function fixedPointDivide(FixedPointType _a, FixedPointType _b) pure returns (FixedPointType) {
    return FixedPointType.wrap((FixedPointType.unwrap(_a) * MULTIPLIER) / FixedPointType.unwrap(_b));
}

function fixedPointSqrt(FixedPointType _a) pure returns (FixedPointType) {
    return FixedPointType.wrap(_a.toUint256().sqrt() * MULTIPLIER_SQRT);
}

function fixedPointEquality(FixedPointType _a, FixedPointType _b) pure returns (bool) {
    return FixedPointType.unwrap(_a) == FixedPointType.unwrap(_b);
}

function fixedPointInequality(FixedPointType _a, FixedPointType _b) pure returns (bool) {
    return FixedPointType.unwrap(_a) != FixedPointType.unwrap(_b);
}

using {
    fixedPointAdd as +,
    fixedPointSubtract as -,
    fixedPointMultiply as *,
    fixedPointDivide as /,
    fixedPointEquality as ==,
    fixedPointInequality as !=
} for FixedPointType global;
