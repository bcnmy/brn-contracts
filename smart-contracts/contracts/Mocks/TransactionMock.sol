// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

contract TransactionMock {
    event UpdatedA(uint256 a);

    uint256 a;

    function mockAdd(uint256 b, uint256 c) public pure returns (uint256) {
        return b + c;
    }

    function mockSubtract(uint256 b, uint256 c) public pure returns (uint256) {
        return b - c;
    }

    function mockUpdate(uint256 _a) public {
        a = _a;
        emit UpdatedA(_a);
    }
}
