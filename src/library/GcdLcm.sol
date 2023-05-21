// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

library GcdLcm {
    function gcd(uint256 a, uint256 b) internal pure returns (uint256) {
        while (b != 0) {
            uint256 t = b;
            b = a % b;
            a = t;
        }
        return a;
    }

    function lcm(uint256 a, uint256 b) internal pure returns (uint256) {
        return (a / gcd(a, b)) * b;
    }
}
