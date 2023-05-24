// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import "openzeppelin-contracts/contracts/utils/math/SafeCast.sol";

import "src/library/FixedPointArithmetic.sol";

import "./TADelegationStorage.sol";
import "./interfaces/ITADelegation.sol";
import "../../common/TAConstants.sol";
import "../../common/TAHelpers.sol";

contract TADelegation is TADelegationStorage, TAHelpers, ITADelegation {
    using FixedPointTypeHelper for FixedPointType;
    using Uint256WrapperHelper for uint256;
    using U16ArrayHelper for uint16[];
    using U32ArrayHelper for uint32[];
    using RAArrayHelper for RelayerAddress[];
    using SafeERC20 for IERC20;
    using SafeCast for uint256;

    function _scaleDelegation(uint256 _delegatedAmount) internal pure returns (uint32) {
        return (_delegatedAmount / DELGATION_SCALING_FACTOR).toUint32();
    }

    function _mintPoolShares(
        RelayerAddress _relayerAddress,
        DelegatorAddress _delegatorAddress,
        uint256 _delegatedAmount,
        TokenAddress _pool
    ) internal {
        TADStorage storage ds = getTADStorage();

        FixedPointType sharePrice_ = delegationSharePrice(_relayerAddress, _pool);
        FixedPointType sharesMinted = (_delegatedAmount.fp() / sharePrice_);

        ds.shares[_relayerAddress][_delegatorAddress][_pool] =
            ds.shares[_relayerAddress][_delegatorAddress][_pool] + sharesMinted;
        ds.totalShares[_relayerAddress][_pool] = ds.totalShares[_relayerAddress][_pool] + sharesMinted;

        emit SharesMinted(_relayerAddress, _delegatorAddress, _pool, _delegatedAmount, sharesMinted, sharePrice_);
    }

    function _updateRelayerProtocolRewards(RelayerAddress _relayer) internal {
        if (_isActiveRelayer(_relayer)) {
            _updateProtocolRewards();
            (uint256 relayerRewards, uint256 delegatorRewards) = _burnRewardSharesForRelayerAndGetRewards(_relayer);

            // Process delegator rewards
            RMStorage storage rs = getRMStorage();
            if (delegatorRewards > 0) {
                _addDelegatorRewards(_relayer, TokenAddress.wrap(address(rs.bondToken)), delegatorRewards);
            }

            // Process relayer rewards
            if (relayerRewards > 0) {
                rs.relayerInfo[_relayer].unpaidProtocolRewards += relayerRewards;
                emit RelayerProtocolRewardsGenerated(_relayer, relayerRewards);
            }
        }
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

        _verifyExternalStateForCdfUpdation(_latestState.cdf.cd_hash(), _latestState.relayers.cd_hash());

        RelayerAddress relayerAddress = _latestState.relayers[_relayerIndex];
        // TODO: _updateRelayerProtocolRewards(relayerAddress);

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

        uint256 rewardsEarned_ = delegationRewardsEarned(_relayerAddress, _pool, _delegatorAddress);

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
    function unDelegate(RelayerState calldata _latestState, RelayerAddress _relayerAddress, uint256 _relayerIndex)
        external
        override
    {
        bool shouldUpdateCdf = false;

        _verifyExternalStateForCdfUpdation(_latestState.cdf.cd_hash(), _latestState.relayers.cd_hash());
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

        // TODO: _updateRelayerProtocolRewards(relayerAddress);

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

    function delegationSharePrice(RelayerAddress _relayerAddress, TokenAddress _tokenAddress)
        public
        view
        override
        returns (FixedPointType)
    {
        TADStorage storage ds = getTADStorage();
        if (ds.totalShares[_relayerAddress][_tokenAddress] == FP_ZERO) {
            return FP_ONE;
        }
        FixedPointType totalDelegation_ = ds.totalDelegation[_relayerAddress].fp();
        FixedPointType unclaimedRewards_ = ds.unclaimedRewards[_relayerAddress][_tokenAddress].fp();
        FixedPointType totalShares_ = ds.totalShares[_relayerAddress][_tokenAddress];

        return (totalDelegation_ + unclaimedRewards_) / totalShares_;
    }

    function delegationRewardsEarned(
        RelayerAddress _relayerAddress,
        TokenAddress _tokenAddres,
        DelegatorAddress _delegatorAddress
    ) public view override returns (uint256) {
        TADStorage storage ds = getTADStorage();

        FixedPointType shares_ = ds.shares[_relayerAddress][_delegatorAddress][_tokenAddres];
        FixedPointType delegation_ = ds.delegation[_relayerAddress][_delegatorAddress].fp();
        FixedPointType rewards = shares_ * delegationSharePrice(_relayerAddress, _tokenAddres) - delegation_;

        return rewards.u256();
    }

    ////////////////////////// Getters //////////////////////////
    function totalDelegation(RelayerAddress _relayerAddress) external view override returns (uint256) {
        TADStorage storage ds = getTADStorage();
        return ds.totalDelegation[_relayerAddress];
    }

    function delegation(RelayerAddress _relayerAddress, DelegatorAddress _delegatorAddress)
        external
        view
        override
        returns (uint256)
    {
        TADStorage storage ds = getTADStorage();
        return ds.delegation[_relayerAddress][_delegatorAddress];
    }

    function shares(RelayerAddress _relayerAddress, DelegatorAddress _delegatorAddress, TokenAddress _tokenAddress)
        external
        view
        override
        returns (FixedPointType)
    {
        TADStorage storage ds = getTADStorage();
        return ds.shares[_relayerAddress][_delegatorAddress][_tokenAddress];
    }

    function totalShares(RelayerAddress _relayerAddress, TokenAddress _tokenAddress)
        external
        view
        override
        returns (FixedPointType)
    {
        TADStorage storage ds = getTADStorage();
        return ds.totalShares[_relayerAddress][_tokenAddress];
    }

    function unclaimedRewards(RelayerAddress _relayerAddress, TokenAddress _tokenAddress)
        external
        view
        override
        returns (uint256)
    {
        TADStorage storage ds = getTADStorage();
        return ds.unclaimedRewards[_relayerAddress][_tokenAddress];
    }

    function supportedPools() external view override returns (TokenAddress[] memory) {
        return getTADStorage().supportedPools;
    }
}
