// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import "./interfaces/ITADebug.sol";
import "src/transaction-allocator/common/TAHelpers.sol";
import "src/transaction-allocator/modules/transaction-allocation/TATransactionAllocationStorage.sol";
import "forge-std/console2.sol";

contract TADebug is ITADebug, TAHelpers, TATransactionAllocationStorage {
    using VersionHistoryManager for VersionHistoryManager.Version[];
    using U16ArrayHelper for uint16[];

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
            _array.cd_hash(), _cdfLogIndex, __windowIndex
        );
    }

    function debug_currentWindowId() external view override returns (WindowId) {
        return _windowId(block.number);
    }

    function debug_currentEpochId() external view override returns (EpochId) {
        return _epochId(block.number);
    }

    function debug_cdfHash(uint16[] calldata _cdf) external pure override returns (bytes32) {
        return _cdf.cd_hash();
    }

    function debug_printCdfLog() external view override {
        RMStorage storage rms = getRMStorage();
        VersionHistoryManager.Version[] storage cdfVersionHistory = rms.cdfVersionHistoryManager;
        for (uint256 i = 0; i < cdfVersionHistory.length; i++) {
            console2.log(i, uint256(cdfVersionHistory[i].contentHash), cdfVersionHistory[i].timestamp);
        }
    }

    function debug_setTransactionsProcessedInEpochByRelayer(
        EpochId _epoch,
        RelayerAddress _relayerAddress,
        uint256 _transactionsProcessed
    ) external override {
        getTAStorage().transactionsSubmitted[_epoch][_relayerAddress] = _transactionsProcessed;
    }

    function debug_setTotalTransactionsProcessedInEpoch(EpochId _epoch, uint256 _transactionsProcessed)
        external
        override
    {
        getTAStorage().totalTransactionsSubmitted[_epoch] = _transactionsProcessed;
    }
}
