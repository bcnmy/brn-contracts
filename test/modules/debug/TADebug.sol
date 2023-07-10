// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import "./interfaces/ITADebug.sol";
import "ta-common/TAHelpers.sol";
import "ta-transaction-allocation/TATransactionAllocationStorage.sol";
import {RelayerStateManager} from "ta-common/RelayerStateManager.sol";

contract TADebug is ITADebug, TAHelpers, TATransactionAllocationStorage {
    using RAArrayHelper for RelayerAddress[];
    using U256ArrayHelper for uint256[];
    using VersionManager for VersionManager.VersionManagerState;
    using RelayerStateManager for RelayerStateManager.RelayerState;

    function debug_verifyRelayerStateAtWindow(
        RelayerStateManager.RelayerState calldata _relayerState,
        uint256 __windowIndex
    ) external view override returns (bool) {
        return
            getRMStorage().relayerStateVersionManager.verifyHashAgainstActiveState(_relayerState.hash(), __windowIndex);
    }

    function debug_currentWindowIndex() external view override returns (uint256) {
        return _windowIndex(block.number);
    }

    function debug_relayerStateHash(RelayerStateManager.RelayerState calldata _relayerState)
        external
        pure
        override
        returns (bytes32)
    {
        return _relayerState.hash();
    }

    function debug_setTransactionsProcessedByRelayer(RelayerAddress _relayerAddress, uint256 _transactionsProcessed)
        external
        override
    {
        getTAStorage().transactionsSubmitted[getTAStorage().epochEndTimestamp][_relayerAddress] = _transactionsProcessed;
    }

    function debug_setRelayerCount(uint256 _relayerCount) external override {
        getRMStorage().relayerCount = _relayerCount;
    }

    function debug_setTotalStake(uint256 _totalStake) external override {
        getRMStorage().totalStake = _totalStake;
    }

    function debug_protocolRewardsSharePrice() external view override returns (FixedPointType) {
        return _protocolRewardRelayerSharePrice(_getLatestTotalUnpaidProtocolRewards());
    }

    function debug_setBaseProtoocolRewardRate(uint256 _rate) external override {
        getRMStorage().baseRewardRatePerMinimumStakePerSec = _rate;
    }

    function debug_setStakeThresholdForJailing(uint256 _amount) external override {
        getTAStorage().stakeThresholdForJailing = _amount;
    }

    function debug_getPendingProtocolRewardsData(RelayerAddress _relayerAddress)
        external
        view
        override
        returns (uint256, uint256, FixedPointType)
    {
        return _getPendingProtocolRewardsData(_relayerAddress, _getLatestTotalUnpaidProtocolRewards());
    }

    function debug_setWithdrawal(
        RelayerAddress _relayerAddress,
        DelegatorAddress _delegatorAddress,
        TokenAddress[] calldata _tokens,
        uint256[] calldata _amounts
    ) external override {
        require(_tokens.length == _amounts.length, "TADebug: token and amount length mismatch");

        for (uint256 i = 0; i < _amounts.length; i++) {
            getTADStorage().delegationWithdrawal[_relayerAddress][_delegatorAddress].amounts[_tokens[i]] = _amounts[i];
        }
    }
}
