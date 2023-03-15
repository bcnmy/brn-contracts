// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import "src/interfaces/IDebug_GasConsumption.sol";
import "src/transaction-allocator/common/TAStructs.sol";
import "./ITATransactionAllocationEventsErrors.sol";

interface ITATransactionAllocation is IDebug_GasConsumption, ITATransactionAllocationEventsErrors {
    function execute(
        ForwardRequest[] calldata _reqs,
        uint16[] calldata _cdf,
        uint256[] calldata _relayerGenerationIterations,
        uint256 _cdfIndex,
        uint256 _currentCdfLogIndex,
        uint256 _relayerIndexUpdationLogIndex
    ) external returns (bool[] memory, bytes[] memory);

    function allocateRelayers(uint16[] calldata _cdf, uint256 _currentCdfLogIndex)
        external
        view
        returns (RelayerAddress[] memory, uint256[] memory);

    function allocateTransaction(AllocateTransactionParams calldata _data)
        external
        view
        returns (ForwardRequest[] memory, uint256[] memory, uint256);

    ////////////////////////// Getters //////////////////////////
    function attendance(uint256, RelayerAddress) external view returns (bool);
}
