// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import "./interfaces/IApplicationMockEventsErrors.sol";
import "src/transaction-allocator/common/TAConstants.sol";
import "openzeppelin-contracts/contracts/access/Ownable.sol";

contract ApplicationMock is IApplicationMockEventsErrors, Ownable {
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

    function incrementA(uint256 _i) external returns (bool) {
        a += _i;
        return true;
    }

    function getA() external view returns (uint256) {
        return a;
    }

    // add this to be excluded from coverage report
    function test() public {}
}
