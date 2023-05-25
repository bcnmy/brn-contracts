// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import "ta-common/TATypes.sol";

interface ITADebug {
    function debug_increaseRewards(RelayerAddress _relayerAddress, TokenAddress _pool, uint256 _amount) external;

    function debug_verifyRelayerStateAtWindow(RelayerState calldata _relayerState, uint256 __windowIndex)
        external
        view
        returns (bool);

    function debug_currentWindowIndex() external view returns (uint256);

    function debug_relayerStateHash(RelayerState calldata _relayerState) external pure returns (bytes32);

    function debug_setTransactionsProcessedByRelayer(RelayerAddress _relayerAddress, uint256 _transactionsProcessed)
        external;

    function debug_setTotalTransactionsProcessed(uint256 _transactionsProcessed) external;
}
