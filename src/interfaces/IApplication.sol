// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import "src/transaction-allocator/common/TAStructs.sol";

interface IApplication {
    function prepayGas(Transaction calldata _tx, uint256 _expectedGas) external returns (address paymentTokenAddress);
    function refundGas() external payable;
}
