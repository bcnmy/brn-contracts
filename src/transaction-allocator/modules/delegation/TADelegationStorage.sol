// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import {FixedPointType} from "src/library/FixedPointArithmetic.sol";
import {RelayerAddress, DelegatorAddress, TokenAddress} from "ta-common/TATypes.sol";

/// @title TADelegationStorage
abstract contract TADelegationStorage {
    bytes32 internal constant DELEGATION_STORAGE_SLOT = keccak256("Delegation.storage");

    /// @dev Structure for storing the information of a delegation withdrawal.
    /// @custom:member tokens The tokens to be withdrawn.
    /// @custom:member amounts The corresponding amounts of tokens to be withdrawn.
    /// @custom:member minWithdrawalTimestamp The minimum timestamp after which the withdrawal can be executed.
    struct DelegationWithdrawal {
        uint256 minWithdrawalTimestamp;
        mapping(TokenAddress => uint256) amounts;
    }

    struct TADStorage {
        ////////////////////////// Configuration Parameters //////////////////////////
        uint256 minimumDelegationAmount;
        uint256 delegationWithdrawDelayInSec;
        mapping(RelayerAddress => uint256) totalDelegation;
        TokenAddress[] supportedPools;
        ////////////////////////// Delegation State //////////////////////////
        mapping(RelayerAddress => mapping(DelegatorAddress => uint256)) delegation;
        mapping(RelayerAddress => mapping(DelegatorAddress => mapping(TokenAddress => FixedPointType))) shares;
        mapping(RelayerAddress => mapping(TokenAddress => FixedPointType)) totalShares;
        mapping(RelayerAddress => mapping(TokenAddress => uint256)) unclaimedRewards;
        mapping(RelayerAddress => mapping(DelegatorAddress => DelegationWithdrawal)) delegationWithdrawal;
    }

    /* solhint-disable no-inline-assembly */
    function getTADStorage() internal pure returns (TADStorage storage ms) {
        bytes32 slot = DELEGATION_STORAGE_SLOT;
        assembly {
            ms.slot := slot
        }
    }
    /* solhint-enable no-inline-assembly */
}
