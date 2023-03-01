// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "./interfaces/ITransactionMockEventsErrors.sol";
import "openzeppelin-contracts/contracts/access/Ownable.sol";

contract TransactionMock is ITransactionMockEventsErrors, Ownable {
    uint256 a;

    constructor() Ownable() {}

    function mockAdd(uint256 b, uint256 c) public pure returns (uint256) {
        return b + c;
    }

    function mockSubtract(uint256 b, uint256 c) public pure returns (uint256) {
        return b - c;
    }

    function mockUpdate(uint256 _a) public returns (bool) {
        a = _a;
        emit UpdatedA(_a);
        return true;
    }

    // add this to be excluded from coverage report
    function test() public {}
}
