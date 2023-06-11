// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import "openzeppelin-contracts/token/ERC20/IERC20.sol";
import "openzeppelin-contracts/token/ERC20/utils/SafeERC20.sol";
import "openzeppelin-contracts/utils/math/SafeCast.sol";

import "./TADelegationStorage.sol";
import "./interfaces/ITADelegation.sol";
import "ta-common/TAHelpers.sol";

contract TADelegation is TADelegationStorage, TAHelpers, ITADelegation {
    using FixedPointTypeHelper for FixedPointType;
    using Uint256WrapperHelper for uint256;
    using U16ArrayHelper for uint16[];
    using U32ArrayHelper for uint32[];
    using RAArrayHelper for RelayerAddress[];
    using SafeERC20 for IERC20;
    using SafeCast for uint256;

    function _mintPoolShares(
        RelayerAddress _relayerAddress,
        DelegatorAddress _delegatorAddress,
        uint256 _delegatedAmount,
        TokenAddress _pool
    ) internal {
        TADStorage storage ds = getTADStorage();

        FixedPointType sharePrice_ = _delegationSharePrice(_relayerAddress, _pool, 0);
        FixedPointType sharesMinted = (_delegatedAmount.fp() / sharePrice_);

        ds.shares[_relayerAddress][_delegatorAddress][_pool] =
            ds.shares[_relayerAddress][_delegatorAddress][_pool] + sharesMinted;
        ds.totalShares[_relayerAddress][_pool] = ds.totalShares[_relayerAddress][_pool] + sharesMinted;

        emit SharesMinted(_relayerAddress, _delegatorAddress, _pool, _delegatedAmount, sharesMinted, sharePrice_);
    }

    function _updateRelayerProtocolRewards(RelayerAddress _relayer) internal {
        if (!_isActiveRelayer(_relayer)) {
            return;
        }

        uint256 updatedTotalUnpaidProtocolRewards = _getLatestTotalUnpaidProtocolRewardsAndUpdate();
        (uint256 relayerRewards, uint256 delegatorRewards, FixedPointType sharesToBurn) =
            _getPendingProtocolRewardsData(_relayer, updatedTotalUnpaidProtocolRewards);

        // Process delegator rewards
        RMStorage storage rs = getRMStorage();
        RelayerInfo storage relayerInfo = rs.relayerInfo[_relayer];

        if (delegatorRewards > 0) {
            _addDelegatorRewards(_relayer, TokenAddress.wrap(address(rs.bondToken)), delegatorRewards);
        }

        // Process relayer rewards
        if (relayerRewards > 0) {
            relayerInfo.unpaidProtocolRewards += relayerRewards;
            emit RelayerProtocolRewardsGenerated(_relayer, relayerRewards);
        }

        rs.totalUnpaidProtocolRewards = updatedTotalUnpaidProtocolRewards - relayerRewards - delegatorRewards;
        rs.totalProtocolRewardShares = rs.totalProtocolRewardShares - sharesToBurn;
        relayerInfo.rewardShares = relayerInfo.rewardShares - sharesToBurn;
    }

    function _mintAllPoolShares(RelayerAddress _relayerAddress, DelegatorAddress _delegator, uint256 _amount)
        internal
    {
        TADStorage storage ds = getTADStorage();
        uint256 length = ds.supportedPools.length;
        if (length == 0) {
            revert NoSupportedGasTokens();
        }

        for (uint256 i; i != length;) {
            _mintPoolShares(_relayerAddress, _delegator, _amount, ds.supportedPools[i]);
            unchecked {
                ++i;
            }
        }
    }

    function delegate(RelayerState calldata _latestState, uint256 _relayerIndex, uint256 _amount) external override {
        if (_relayerIndex >= _latestState.relayers.length) {
            revert InvalidRelayerIndex();
        }

        _verifyExternalStateForRelayerStateUpdation(_latestState.cdf.cd_hash(), _latestState.relayers.cd_hash());

        RelayerAddress relayerAddress = _latestState.relayers[_relayerIndex];
        _updateRelayerProtocolRewards(relayerAddress);

        getRMStorage().bondToken.safeTransferFrom(msg.sender, address(this), _amount);
        TADStorage storage ds = getTADStorage();

        {
            DelegatorAddress delegatorAddress = DelegatorAddress.wrap(msg.sender);
            _mintAllPoolShares(relayerAddress, delegatorAddress, _amount);

            ds.delegation[relayerAddress][delegatorAddress] += _amount;
            ds.totalDelegation[relayerAddress] += _amount;
            emit DelegationAdded(relayerAddress, delegatorAddress, _amount);
        }

        // Update the CDF
        _updateCdf_c(_latestState.relayers);
    }

    function _processRewards(RelayerAddress _relayerAddress, TokenAddress _pool, DelegatorAddress _delegatorAddress)
        internal
    {
        TADStorage storage ds = getTADStorage();

        uint256 rewardsEarned_ = _delegationRewardsEarned(_relayerAddress, _pool, _delegatorAddress);

        if (rewardsEarned_ != 0) {
            ds.unclaimedRewards[_relayerAddress][_pool] -= rewardsEarned_;
            ds.totalShares[_relayerAddress][_pool] =
                ds.totalShares[_relayerAddress][_pool] - ds.shares[_relayerAddress][_delegatorAddress][_pool];
            ds.shares[_relayerAddress][_delegatorAddress][_pool] = FP_ZERO;

            _transfer(_pool, DelegatorAddress.unwrap(_delegatorAddress), rewardsEarned_);
            emit RewardSent(_relayerAddress, _delegatorAddress, _pool, rewardsEarned_);
        }
    }

    // TODO: Non Reentrant
    function undelegate(RelayerState calldata _latestState, RelayerAddress _relayerAddress, uint256 _relayerIndex)
        external
        override
    {
        bool shouldUpdateCdf = false;

        _verifyExternalStateForRelayerStateUpdation(_latestState.cdf.cd_hash(), _latestState.relayers.cd_hash());
        if (_relayerIndex < _latestState.relayers.length && _latestState.relayers[_relayerIndex] == _relayerAddress) {
            // Relayer is active in the pending state, therefore it's CDF should be updated
            shouldUpdateCdf = true;
        } else {
            // Relayer is not active in the pending state, therefore it's CDF should not be updated
            // We need to verify that the relayer is not present in the active relayers array at all,
            // by scanning the array linearly
            // In this case, the relayerIndex should not be used.
            if (_latestState.relayers.cd_linearSearch(_relayerAddress) != _latestState.relayers.length) {
                revert RelayerIsActiveInPendingState();
            }
        }

        TADStorage storage ds = getTADStorage();

        _updateRelayerProtocolRewards(_relayerAddress);

        {
            uint256 length = ds.supportedPools.length;
            DelegatorAddress delegatorAddress = DelegatorAddress.wrap(msg.sender);
            for (uint256 i; i != length;) {
                _processRewards(_relayerAddress, ds.supportedPools[i], delegatorAddress);
                unchecked {
                    ++i;
                }
            }
        }

        {
            DelegatorAddress delegatorAddress = DelegatorAddress.wrap(msg.sender);
            uint256 delegation_ = ds.delegation[_relayerAddress][delegatorAddress];
            ds.totalDelegation[_relayerAddress] -= delegation_;
            ds.delegation[_relayerAddress][delegatorAddress] = 0;
            emit DelegationRemoved(_relayerAddress, delegatorAddress, delegation_);
        }

        // Update the CDF if and only if the relayer is still registered
        // There can be a case where the relayer is unregistered and the user still has rewards
        if (shouldUpdateCdf) {
            _updateCdf_c(_latestState.relayers);
        }
    }

    function _delegationSharePrice(
        RelayerAddress _relayerAddress,
        TokenAddress _tokenAddress,
        uint256 _extraUnclaimedRewards
    ) internal view returns (FixedPointType) {
        TADStorage storage ds = getTADStorage();
        if (ds.totalShares[_relayerAddress][_tokenAddress] == FP_ZERO) {
            return FP_ONE;
        }
        FixedPointType totalDelegation_ = ds.totalDelegation[_relayerAddress].fp();
        FixedPointType unclaimedRewards_ =
            (ds.unclaimedRewards[_relayerAddress][_tokenAddress] + _extraUnclaimedRewards).fp();
        FixedPointType totalShares_ = ds.totalShares[_relayerAddress][_tokenAddress];

        return (totalDelegation_ + unclaimedRewards_) / totalShares_;
    }

    function _delegationRewardsEarned(
        RelayerAddress _relayerAddress,
        TokenAddress _tokenAddres,
        DelegatorAddress _delegatorAddress
    ) internal view returns (uint256) {
        TADStorage storage ds = getTADStorage();

        FixedPointType shares_ = ds.shares[_relayerAddress][_delegatorAddress][_tokenAddres];
        FixedPointType delegation_ = ds.delegation[_relayerAddress][_delegatorAddress].fp();
        FixedPointType rewards = shares_ * _delegationSharePrice(_relayerAddress, _tokenAddres, 0) - delegation_;

        return rewards.u256();
    }

    function claimableDelegationRewards(
        RelayerAddress _relayerAddress,
        TokenAddress _tokenAddres,
        DelegatorAddress _delegatorAddress
    ) external view returns (uint256) {
        TADStorage storage ds = getTADStorage();

        uint256 updatedTotalUnpaidProtocolRewards = _getLatestTotalUnpaidProtocolRewards();

        (, uint256 protocolDelegationRewards,) =
            _getPendingProtocolRewardsData(_relayerAddress, updatedTotalUnpaidProtocolRewards);

        FixedPointType shares_ = ds.shares[_relayerAddress][_delegatorAddress][_tokenAddres];
        FixedPointType delegation_ = ds.delegation[_relayerAddress][_delegatorAddress].fp();
        FixedPointType rewards =
            shares_ * _delegationSharePrice(_relayerAddress, _tokenAddres, protocolDelegationRewards) - delegation_;

        return rewards.u256();
    }

    ////////////////////////// Getters //////////////////////////
    function totalDelegation(RelayerAddress _relayerAddress) external view override returns (uint256) {
        return getTADStorage().totalDelegation[_relayerAddress];
    }

    function delegation(RelayerAddress _relayerAddress, DelegatorAddress _delegatorAddress)
        external
        view
        override
        returns (uint256)
    {
        return getTADStorage().delegation[_relayerAddress][_delegatorAddress];
    }

    function shares(RelayerAddress _relayerAddress, DelegatorAddress _delegatorAddress, TokenAddress _tokenAddress)
        external
        view
        override
        returns (FixedPointType)
    {
        return getTADStorage().shares[_relayerAddress][_delegatorAddress][_tokenAddress];
    }

    function totalShares(RelayerAddress _relayerAddress, TokenAddress _tokenAddress)
        external
        view
        override
        returns (FixedPointType)
    {
        return getTADStorage().totalShares[_relayerAddress][_tokenAddress];
    }

    function unclaimedRewards(RelayerAddress _relayerAddress, TokenAddress _tokenAddress)
        external
        view
        override
        returns (uint256)
    {
        return getTADStorage().unclaimedRewards[_relayerAddress][_tokenAddress];
    }

    function supportedPools() external view override returns (TokenAddress[] memory) {
        return getTADStorage().supportedPools;
    }

    function minimumDelegationAmount() external view override returns (uint256) {
        return getTADStorage().minimumDelegationAmount;
    }
}
