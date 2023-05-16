// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import "./interfaces/ITADebug.sol";
import "src/transaction-allocator/common/TAHelpers.sol";
import "src/transaction-allocator/modules/transaction-allocation/TATransactionAllocationStorage.sol";
import "forge-std/console2.sol";

contract TADebug is ITADebug, TAHelpers, TATransactionAllocationStorage {
    using VersionHistoryManager for VersionHistoryManager.Version[];

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
        returns (bool)
    {
        return getRMStorage().cdfVersionHistoryManager.verifyContentHashAtTimestamp(
            _hashUint16ArrayCalldata(_array), _cdfLogIndex, __windowIndex
        );
    }

    function debug_currentWindowIndex() external view override returns (uint256) {
        return _windowIndex(block.number);
    }

    function debug_cdfHash(uint16[] calldata _cdf) external pure override returns (bytes32) {
        return _hashUint16ArrayCalldata(_cdf);
    }

    function debug_printCdfLog() external view override {
        RMStorage storage rms = getRMStorage();
        VersionHistoryManager.Version[] storage cdfVersionHistory = rms.cdfVersionHistoryManager;
        console2.log("CDF Log:");
        for (uint256 i = 0; i < cdfVersionHistory.length; i++) {
            console2.log(i, uint256(cdfVersionHistory[i].contentHash), cdfVersionHistory[i].timestamp);
        }
    }

    function debug_setTransactionsProcessedInEpochByRelayer(
        uint256 _epoch,
        RelayerAddress _relayerAddress,
        uint256 _transactionsProcessed
    ) external override {
        getTAStorage().transactionsSubmitted[_epoch][_relayerAddress] = _transactionsProcessed;
    }

    function debug_setTotalTransactionsProcessedInEpoch(uint256 _epoch, uint256 _transactionsProcessed)
        external
        override
    {
        getTAStorage().totalTransactionsSubmitted[_epoch] = _transactionsProcessed;
    }
}
