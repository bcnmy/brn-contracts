// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import {RelayerAddress, DelegatorAddress, TokenAddress} from "ta-common/TATypes.sol";
import {FixedPointType} from "src/library/FixedPointArithmetic.sol";
import {ITADelegationGetters} from "./interfaces/ITADelegationGetters.sol";
import {TADelegationStorage} from "./TADelegationStorage.sol";
import {Guards} from "src/utils/Guards.sol";

/// @title TADelegationGetters
abstract contract TADelegationGetters is TADelegationStorage, ITADelegationGetters, Guards {
    function totalDelegation(RelayerAddress _relayerAddress) external view override noSelfCall returns (uint256) {
        return getTADStorage().totalDelegation[_relayerAddress];
    }

    function delegation(RelayerAddress _relayerAddress, DelegatorAddress _delegatorAddress)
        external
        view
        override
        noSelfCall
        returns (uint256)
    {
        return getTADStorage().delegation[_relayerAddress][_delegatorAddress];
    }

    function shares(RelayerAddress _relayerAddress, DelegatorAddress _delegatorAddress, TokenAddress _tokenAddress)
        external
        view
        override
        noSelfCall
        returns (FixedPointType)
    {
        return getTADStorage().shares[_relayerAddress][_delegatorAddress][_tokenAddress];
    }

    function totalShares(RelayerAddress _relayerAddress, TokenAddress _tokenAddress)
        external
        view
        override
        noSelfCall
        returns (FixedPointType)
    {
        return getTADStorage().totalShares[_relayerAddress][_tokenAddress];
    }

    function unclaimedDelegationRewards(RelayerAddress _relayerAddress, TokenAddress _tokenAddress)
        external
        view
        override
        noSelfCall
        returns (uint256)
    {
        return getTADStorage().unclaimedRewards[_relayerAddress][_tokenAddress];
    }

    function supportedPools() external view override noSelfCall returns (TokenAddress[] memory) {
        return getTADStorage().supportedPools;
    }

    function minimumDelegationAmount() external view override noSelfCall returns (uint256) {
        return getTADStorage().minimumDelegationAmount;
    }
}
