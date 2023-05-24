// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import "openzeppelin-contracts/contracts/utils/math/SafeMath.sol";

import "src/library/FixedPointArithmetic.sol";
import "ta-common/TATypes.sol";

abstract contract TADelegationStorage {
    bytes32 internal constant DELEGATION_STORAGE_SLOT = keccak256("Delegation.storage");

    struct TADStorage {
        uint256 minimumDelegationAmount;
        uint256 baseRewardRatePerMinimumStakePerSec;
        mapping(RelayerAddress => uint256) totalDelegation;
        mapping(RelayerAddress => mapping(DelegatorAddress => uint256)) delegation;
        mapping(RelayerAddress => mapping(DelegatorAddress => mapping(TokenAddress => FixedPointType))) shares;
        mapping(RelayerAddress => mapping(TokenAddress => FixedPointType)) totalShares;
        // TODO: Add C*Time
        mapping(RelayerAddress => mapping(TokenAddress => uint256)) unclaimedRewards;
        TokenAddress[] supportedPools;
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
