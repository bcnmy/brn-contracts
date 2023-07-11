// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import {TATransactionAllocationStorage} from "./TATransactionAllocationStorage.sol";
import {ITATransactionAllocationGetters} from "./interfaces/ITATransactionAllocationGetters.sol";
import {Guards} from "src/utils/Guards.sol";
import {RelayerAddress} from "ta-common/TATypes.sol";
import {FixedPointType} from "src/library/FixedPointArithmetic.sol";
import {RelayerStateManager} from "ta-common/RelayerStateManager.sol";
import {TAHelpers} from "ta-common/TAHelpers.sol";

/// @title TATransactionAllocationGetters
abstract contract TATransactionAllocationGetters is
    ITATransactionAllocationGetters,
    TATransactionAllocationStorage,
    TAHelpers,
    Guards
{
    function transactionsSubmittedByRelayer(RelayerAddress _relayerAddress)
        external
        view
        override
        noSelfCall
        returns (uint256)
    {
        return getTAStorage().transactionsSubmitted[_relayerAddress];
    }

    function _totalTransactionsSubmitted(RelayerAddress[] calldata _activeRelayerAddresses)
        internal
        view
        returns (uint256 totalTransactionsSubmitted_)
    {
        TAStorage storage ta = getTAStorage();
        uint256 length = _activeRelayerAddresses.length;
        for (uint256 i; i != length;) {
            totalTransactionsSubmitted_ += ta.transactionsSubmitted[_activeRelayerAddresses[i]];
            unchecked {
                ++i;
            }
        }
    }

    function totalTransactionsSubmitted(RelayerStateManager.RelayerState calldata _activeState)
        external
        view
        override
        noSelfCall
        returns (uint256)
    {
        _verifyExternalStateForTransactionAllocation(_activeState, block.number);
        return _totalTransactionsSubmitted(_activeState.relayers);
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
