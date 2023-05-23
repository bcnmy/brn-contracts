// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import "./interfaces/ITADebug.sol";
import "src/transaction-allocator/common/TAHelpers.sol";
import "src/transaction-allocator/modules/transaction-allocation/TATransactionAllocationStorage.sol";
import "forge-std/console2.sol";

contract TADebug is ITADebug, TAHelpers, TATransactionAllocationStorage {
    using U16ArrayHelper for uint16[];
    using VersionManager for VersionManager.VersionManagerState;

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

    function debug_verifyCdfHashAtWindow(uint16[] calldata _array, uint256 __windowIndex)
        external
        view
        override
        returns (bool)
    {
        return getRMStorage().cdfVersionManager.verifyHashAgainstActiveState(_array.cd_hash(), __windowIndex);
    }

    function debug_currentWindowIndex() external view override returns (uint256) {
        return _windowIndex(block.number);
    }

    function debug_cdfHash(uint16[] calldata _cdf) external pure override returns (bytes32) {
        return _cdf.cd_hash();
    }

    function debug_setTransactionsProcessedByRelayer(RelayerAddress _relayerAddress, uint256 _transactionsProcessed)
        external
        override
    {
        getTAStorage().transactionsSubmitted[getTAStorage().epochEndTimestamp][_relayerAddress] = _transactionsProcessed;
    }

    function debug_setTotalTransactionsProcessed(uint256 _transactionsProcessed) external override {
        getTAStorage().totalTransactionsSubmitted[getTAStorage().epochEndTimestamp] = _transactionsProcessed;
    }
}
