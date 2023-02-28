// SPDX-License-Identifier: MIT

pragma solidity 0.8.17;

import "src/interfaces/IDebug_GasConsumption.sol";
import "src/structs/Transaction.sol";
import "./ITATransactionAllocationEventsErrors.sol";

interface ITATransactionAllocation is IDebug_GasConsumption, ITATransactionAllocationEventsErrors {
    function execute(
        ForwardRequest[] calldata _reqs,
        uint16[] calldata _cdf,
        uint256[] calldata _relayerGenerationIterations,
        uint256 _cdfIndex
    ) external payable returns (bool[] memory, bytes[] memory);

    function allocateRelayers(uint256 _blockNumber, uint16[] calldata _cdf)
        external
        view
        returns (address[] memory, uint256[] memory);

    function allocateTransaction(
        address _relayer,
        uint256 _blockNumber,
        bytes[] calldata _txnCalldata,
        uint16[] calldata _cdf
    ) external view returns (bytes[] memory, uint256[] memory, uint256);

    function attendance(uint256, address) external view returns (bool);
}
