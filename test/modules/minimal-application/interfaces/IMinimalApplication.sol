// SPDX-License-Identifier: MIT

pragma solidity ^0.8.19;

import "src/transaction-allocator/common/TAStructs.sol";
import "./IMinimalApplicationEventsErrors.sol";

interface IMinimalApplication is IMinimalApplicationEventsErrors {
    function count() external view returns (uint256);
    function executeMinimalApplication(bytes32 _data) external payable;
    function allocateMinimalApplicationTransaction(AllocateTransactionParams calldata _params)
        external
        returns (bytes[] memory, uint256, uint256);
}
