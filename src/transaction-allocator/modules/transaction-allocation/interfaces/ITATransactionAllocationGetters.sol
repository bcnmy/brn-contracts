// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import {RelayerAddress} from "ta-common/TATypes.sol";
import {FixedPointType} from "src/library/FixedPointArithmetic.sol";

/// @title ITATransactionAllocationGetters
interface ITATransactionAllocationGetters {
    function transactionsSubmittedByRelayer(RelayerAddress _relayerAddress) external view returns (uint256);

    function totalTransactionsSubmitted() external view returns (uint256);

    function epochLengthInSec() external view returns (uint256);

    function epochEndTimestamp() external view returns (uint256);

    function livenessZParameter() external view returns (FixedPointType);

    function stakeThresholdForJailing() external view returns (uint256);
}
