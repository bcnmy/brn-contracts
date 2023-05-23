// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import "src/interfaces/IDebug_GasConsumption.sol";
import "src/transaction-allocator/common/TAStructs.sol";
import "./ITATransactionAllocationEventsErrors.sol";

interface ITATransactionAllocation is IDebug_GasConsumption, ITATransactionAllocationEventsErrors {
    struct ExecuteParams {
        bytes[] reqs;
        uint256[] forwardedNativeAmounts;
        uint16[] cdf;
        RelayerAddress[] activeRelayers;
        uint256 relayerIndex;
        uint256 relayerGenerationIterationBitmap;
    }

    function execute(ExecuteParams calldata _data) external payable;

    struct ProcessLivenessCheckParams {
        uint16[] currentCdf;
        RelayerAddress[] currentActiveRelayers;
        RelayerAddress[] pendingActiveRelayers;
        uint256[] currentActiveRelayerToPendingActiveRelayersIndex;
        uint32[] latestStakeArray;
        uint32[] latestDelegationArray;
    }

    function processLivenessCheck(ProcessLivenessCheckParams calldata _params) external;

    function allocateRelayers(uint16[] calldata _cdf, RelayerAddress[] calldata _activeRelayers)
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
}
