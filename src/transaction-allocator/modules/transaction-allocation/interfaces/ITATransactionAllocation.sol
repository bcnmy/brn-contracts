// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import "src/interfaces/IDebug_GasConsumption.sol";
import "src/transaction-allocator/common/TATypes.sol";
import "src/library/FixedPointArithmetic.sol";
import "./ITATransactionAllocationEventsErrors.sol";

interface ITATransactionAllocation is IDebug_GasConsumption, ITATransactionAllocationEventsErrors {
    struct ExecuteParams {
        bytes[] reqs;
        uint256[] forwardedNativeAmounts;
        uint256 relayerIndex;
        uint256 relayerGenerationIterationBitmap;
        RelayerState activeState;
        RelayerState latestState;
    }

    function execute(ExecuteParams calldata _data) external payable;

    function allocateRelayers(RelayerState calldata _activeState)
        external
        view
        returns (RelayerAddress[] memory, uint256[] memory);

    function calculateMinimumTranasctionsForLiveness(
        uint256 _relayerStake,
        uint256 _totalStake,
        FixedPointType _totalTransactions,
        FixedPointType _zScore
    ) external pure returns (FixedPointType);

    ////////////////////////// Getters //////////////////////////
    function transactionsSubmittedRelayer(RelayerAddress _relayerAddress) external view returns (uint256);
    function totalTransactionsSubmitted() external view returns (uint256);
    function epochLengthInSec() external view returns (uint256);
    function epochEndTimestamp() external view returns (uint256);
}
