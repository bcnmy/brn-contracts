// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import "src/interfaces/IDebug_GasConsumption.sol";
import "src/transaction-allocator/common/TAStructs.sol";
import "./ITATransactionAllocationEventsErrors.sol";

interface ITATransactionAllocation is IDebug_GasConsumption, ITATransactionAllocationEventsErrors {
    function execute(
        bytes[] calldata _reqs,
        uint256[] calldata _forwardedNativeAmounts,
        uint16[] calldata _cdf,
        uint256 _currentCdfLogIndex,
        RelayerAddress[] calldata _activeRelayers,
        uint256 _currentRelayerListLogIndex,
        uint256 _relayerIndex,
        uint256 _relayerGenerationIterationBitmap
    ) external payable;

    function allocateRelayers(
        uint16[] calldata _cdf,
        uint256 _currentCdfLogIndex,
        RelayerAddress[] calldata _activeRelayers,
        uint256 _relayerLogIndex
    ) external view returns (RelayerAddress[] memory, uint256[] memory);

    function processLivenessCheck(
        TargetEpochData calldata _targetEpochData,
        LatestActiveRelayersStakeAndDelegationState calldata _latestState,
        uint256[] calldata _targetEpochRelayerIndexToLatestRelayerIndexMapping
    ) external;

    function calculateMinimumTranasctionsForLiveness(
        uint256 _relayerStake,
        uint256 _totalStake,
        FixedPointType _totalTransactions,
        FixedPointType _zScore
    ) external pure returns (FixedPointType);

    ////////////////////////// Getters //////////////////////////
    function transactionsSubmittedInEpochByRelayer(EpochId _epoch, RelayerAddress _relayerAddress)
        external
        view
        returns (uint256);
    function totalTransactionsSubmittedInEpoch(EpochId _epoch) external view returns (uint256);
    function livenessCheckProcessedForEpoch(EpochId _epoch) external view returns (bool);
}
