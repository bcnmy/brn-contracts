// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import "src/interfaces/IDebug_GasConsumption.sol";
import "src/transaction-allocator/common/TAStructs.sol";
import "./ITATransactionAllocationEventsErrors.sol";

interface ITATransactionAllocation is IDebug_GasConsumption, ITATransactionAllocationEventsErrors {
    function execute(
        bytes[] calldata _reqs,
        uint16[] calldata _cdf,
        uint256 _relayerGenerationIterationBitmap,
        uint256 _relayerIndex,
        uint256 _currentCdfLogIndex
    ) external returns (bool[] memory);

    function allocateRelayers(uint16[] calldata _cdf, uint256 _currentCdfLogIndex)
        external
        view
        returns (RelayerAddress[] memory, uint256[] memory);
}
