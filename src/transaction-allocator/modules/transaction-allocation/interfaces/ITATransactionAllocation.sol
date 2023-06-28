// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import {ITATransactionAllocationEventsErrors} from "./ITATransactionAllocationEventsErrors.sol";
import {FixedPointType} from "src/library/FixedPointArithmetic.sol";
import {ITATransactionAllocationGetters} from "./ITATransactionAllocationGetters.sol";
import {RelayerAddress, RelayerState} from "ta-common/TATypes.sol";

interface ITATransactionAllocation is ITATransactionAllocationEventsErrors, ITATransactionAllocationGetters {
    struct ExecuteParams {
        bytes[] reqs;
        uint256[] forwardedNativeAmounts;
        uint256 relayerIndex;
        uint256 relayerGenerationIterationBitmap;
        RelayerState activeState;
        RelayerState latestState;
        uint256[] activeStateToLatestStateMap;
    }

    function execute(ExecuteParams calldata _data) external payable;

    function allocateRelayers(RelayerState calldata _activeState)
        external
        view
        returns (RelayerAddress[] memory, uint256[] memory);

    function calculateMinimumTranasctionsForLiveness(
        uint256 _relayerStake,
        uint256 _totalStake,
        uint256 _totalTransactions,
        FixedPointType _zScore
    ) external view returns (FixedPointType);
}
