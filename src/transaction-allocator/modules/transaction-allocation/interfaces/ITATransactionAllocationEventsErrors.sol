// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import {RelayerAddress} from "ta-common/TATypes.sol";
import {RelayerStateManager} from "ta-common/RelayerStateManager.sol";

/// @title ITATransactionAllocationEventsErrors
interface ITATransactionAllocationEventsErrors {
    error RelayerAddressNotFoundInMemoryState(RelayerAddress relayerAddress);
    error RelayerIndexDoesNotPointToSelectedCdfInterval();
    error RelayerAddressDoesNotMatchSelectedRelayer();
    error InvalidRelayerGenerationIteration();
    error NoRelayersRegistered();
    error TransactionExecutionFailed(uint256 index, bytes returndata);
    error InvalidFeeAttached(uint256 totalExpectedValue, uint256 actualValue);
    error RelayerAlreadySubmittedTransaction(RelayerAddress relayerAddress, uint256 windowId);

    event TransactionStatus(uint256 indexed index, bool indexed success, bytes indexed returndata);
    event RelayerPenalized(
        RelayerAddress indexed relayerAddress, uint256 indexed newStake, uint256 indexed penaltyAmount
    );
    event RelayerJailed(RelayerAddress indexed relayerAddress, uint256 jailedUntilTimestamp);
    event LivenessCheckProcessed(uint256 indexed epochEndTimestamp);
    event NoTransactionsSubmittedInEpoch();
    event EpochEndTimestampUpdated(uint256 indexed epochEndTimestamp);
    event NewRelayerState(
        bytes32 indexed relayerStateHash, uint256 indexed activationWindow, RelayerStateManager.RelayerState newState
    );
}
