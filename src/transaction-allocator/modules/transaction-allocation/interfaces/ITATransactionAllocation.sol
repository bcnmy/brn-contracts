// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import {ITATransactionAllocationEventsErrors} from "./ITATransactionAllocationEventsErrors.sol";
import {FixedPointType} from "src/library/FixedPointArithmetic.sol";
import {ITATransactionAllocationGetters} from "./ITATransactionAllocationGetters.sol";
import {RelayerAddress} from "ta-common/TATypes.sol";
import {RelayerStateManager} from "ta-common/RelayerStateManager.sol";

/// @title ITATransactionAllocation
interface ITATransactionAllocation is ITATransactionAllocationEventsErrors, ITATransactionAllocationGetters {
    /// @dev Data structure to hold the parameters for the execute function.
    /// @custom:member reqs The array of calldata containing the transactions to be executed.
    /// @custom:member forwardedNativeAmounts The array of native amounts to be forwarded to the call with the corresponding transaction.
    /// @custom:member relayerIndex The index of the relayer in the active state calling the execute function.
    /// @custom:member relayerGenerationIterationBitmap A bitmap with set bit indicating the relayer was selected at that iteration.
    /// @custom:member activeState The active state of the relayers.
    /// @custom:member latestState The latest state of the relayers.
    struct ExecuteParams {
        bytes[] reqs;
        uint256[] forwardedNativeAmounts;
        uint256 relayerIndex;
        uint256 relayerGenerationIterationBitmap;
        RelayerStateManager.RelayerState activeState;
        RelayerStateManager.RelayerState latestState;
    }

    /// @notice This function is called by the relayer to execute the transactions.
    /// @param _data The data structure containing the parameters for the execute function.
    function execute(ExecuteParams calldata _data) external payable;

    /// @notice Returns the list of relayers selected in the current window. Expected to be called off-chain.
    /// @param _activeState The active state of the relayers.
    /// @return selectedRelayers list of relayers selected of length relayersPerWindow, but
    ///                          there can be duplicates
    /// @return indices list of indices of the selected relayers in the active state, used for verification
    function allocateRelayers(RelayerStateManager.RelayerState calldata _activeState)
        external
        view
        returns (RelayerAddress[] memory, uint256[] memory);

    /// @notice Convenience function to calculate the miniumum number of transactions required to pass the liveness check.
    /// @param _relayerStake The stake of the relayer calling the execute function.
    /// @param _totalStake The total stake of all the relayers.
    /// @param _totalTransactions The total number of transactions submitted in the current epoch.
    /// @param _zScore A parameter used to calculate the minimum number of transactions required to pass the liveness check.
    function calculateMinimumTranasctionsForLiveness(
        uint256 _relayerStake,
        uint256 _totalStake,
        uint256 _totalTransactions,
        FixedPointType _zScore
    ) external view returns (FixedPointType);
}
