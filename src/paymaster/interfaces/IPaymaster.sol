// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import "src/transaction-allocator/common/TAStructs.sol";
import "./IPaymasterEventsErrors.sol";

interface IPaymaster is IPaymasterEventsErrors {
    function prepayGas(bytes calldata _tx, uint256 _expectedGas, bytes calldata data)
        external
        returns (TokenAddress paymentTokenAddress);

    function addFunds(address _sponsor) external payable;
}
