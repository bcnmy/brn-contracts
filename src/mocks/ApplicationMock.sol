// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import "./interfaces/IApplicationMockEventsErrors.sol";
import "src/interfaces/IApplication.sol";
import "src/transaction-allocator/common/TAConstants.sol";
import "openzeppelin-contracts/contracts/access/Ownable.sol";

contract ApplicationMock is IApplicationMockEventsErrors, Ownable, IApplication {
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

    function prepayGas(Transaction calldata, uint256 _expectedGas)
        external
        override
        returns (address paymentTokenAddress)
    {
        (bool success,) = address(msg.sender).call{value: _expectedGas * tx.gasprice}("");
        if (!success) {
            revert AppPrepaymentFailed();
        }
        return TokenAddress.unwrap(NATIVE_TOKEN);
    }

    function refundGas() external payable override {}
}
