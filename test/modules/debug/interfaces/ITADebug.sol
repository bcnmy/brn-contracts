// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import "src/transaction-allocator/common/TATypes.sol";

interface ITADebug {
    function debug_increaseRewards(RelayerAddress _relayerAddress, TokenAddress _pool, uint256 _amount) external;

    function debug_verifyCdfHashAtWindow(uint16[] calldata _array, WindowIndex __windowIndex)
        external
        view
        returns (bool);

    function debug_currentWindowIndex() external view returns (WindowIndex);

    function debug_cdfHash(uint16[] calldata _cdf) external view returns (bytes32);

    function debug_setTransactionsProcessedByRelayer(RelayerAddress _relayerAddress, uint256 _transactionsProcessed)
        external;

    function debug_setTotalTransactionsProcessed(uint256 _transactionsProcessed) external;
}
