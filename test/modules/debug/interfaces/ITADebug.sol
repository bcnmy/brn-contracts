// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import "src/transaction-allocator/common/TATypes.sol";

interface ITADebug {
    function debug_increaseRewards(RelayerAddress _relayerAddress, TokenAddress _pool, uint256 _amount) external;

    function debug_verifyCdfHashAtWindow(uint16[] calldata _array, uint256 __windowIndex, uint256 _cdfLogIndex)
        external
        view
        returns (bool);

    function debug_currentWindowIndex() external view returns (uint256);

    function debug_cdfHash(uint16[] calldata _cdf) external view returns (bytes32);
}
