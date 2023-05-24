// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import "./ITATransactionAllocationEventsErrors.sol";
import "ta-common/TATypes.sol";
import "src/library/FixedPointArithmetic.sol";

interface ITATransactionAllocation is ITATransactionAllocationEventsErrors {
    struct ExecuteParams {
        bytes[] reqs;
        uint256[] forwardedNativeAmounts;
        uint256 relayerIndex;
        uint256 relayerGenerationIterationBitmap;
        RelayerState activeState;
        RelayerState latestState;
        uint256[] activeStateToPendingStateMap;
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
    function livenessZParameter() external view returns (FixedPointType);
}
