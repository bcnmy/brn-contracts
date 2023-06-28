// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import {TATransactionAllocationStorage} from "./TATransactionAllocationStorage.sol";
import {ITATransactionAllocationGetters} from "./interfaces/ITATransactionAllocationGetters.sol";
import {Guards} from "src/utils/Guards.sol";
import {RelayerAddress} from "ta-common/TATypes.sol";
import {FixedPointType} from "src/library/FixedPointArithmetic.sol";

abstract contract TATransactionAllocationGetters is
    ITATransactionAllocationGetters,
    TATransactionAllocationStorage,
    Guards
{
    function transactionsSubmittedByRelayer(RelayerAddress _relayerAddress)
        external
        view
        override
        noSelfCall
        returns (uint256)
    {
        return getTAStorage().transactionsSubmitted[getTAStorage().epochEndTimestamp][_relayerAddress];
    }

    function totalTransactionsSubmitted() external view override noSelfCall returns (uint256) {
        return getTAStorage().totalTransactionsSubmitted[getTAStorage().epochEndTimestamp];
    }

    function epochLengthInSec() external view override noSelfCall returns (uint256) {
        return getTAStorage().epochLengthInSec;
    }

    function epochEndTimestamp() external view override noSelfCall returns (uint256) {
        return getTAStorage().epochEndTimestamp;
    }

    function livenessZParameter() external view override noSelfCall returns (FixedPointType) {
        return getTAStorage().livenessZParameter;
    }

    function stakeThresholdForJailing() external view override noSelfCall returns (uint256) {
        return getTAStorage().stakeThresholdForJailing;
    }
}
