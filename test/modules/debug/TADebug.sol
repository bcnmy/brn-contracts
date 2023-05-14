// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import "./interfaces/ITADebug.sol";

import "src/transaction-allocator/common/TAHelpers.sol";

contract TADebug is ITADebug, TAHelpers {
    constructor() {
        if (block.chainid != 31337) {
            revert("TADebug: only for testing");
        }
    }

    function debug_increaseRewards(RelayerAddress _relayerAddress, TokenAddress _pool, uint256 _amount)
        external
        override
    {
        TADStorage storage ds = getTADStorage();
        ds.unclaimedRewards[_relayerAddress][_pool] += _amount;
    }

    function debug_verifyCdfHashAtWindow(uint16[] calldata _array, uint256 __windowIndex, uint256 _cdfLogIndex)
        external
        view
        override
        verifyCDF(_array, __windowIndex, _cdfLogIndex)
        returns (bool)
    {}

    function debug_currentWindowIndex() external view override returns (uint256) {
        return _windowIndex(block.number);
    }

    function debug_cdfHash(uint16[] calldata _cdf) external pure override returns (bytes32) {
        return _hashUint16ArrayCalldata(_cdf);
    }
}
