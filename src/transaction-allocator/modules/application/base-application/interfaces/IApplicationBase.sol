// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import "src/transaction-allocator/common/TATypes.sol";

interface IApplicationBase {
    error ExternalCallsNotAllowed();
    error RelayerNotAssignedToTransaction();
    error RelayerAllocationResultLengthMismatch(uint256 expectedLength, uint256 actualLength);
    error AlreadyInitialized();
}
