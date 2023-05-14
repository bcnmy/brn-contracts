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
    ) external payable returns (bool[] memory);

    function allocateRelayers(
        uint16[] calldata _cdf,
        uint256 _currentCdfLogIndex,
        RelayerAddress[] calldata _activeRelayers,
        uint256 _relayerLogIndex
    ) external view returns (RelayerAddress[] memory, uint256[] memory);
}
