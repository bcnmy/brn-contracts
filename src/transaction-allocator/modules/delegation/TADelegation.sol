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
    using SafeERC20 for IERC20;
    using SafeCast for uint256;

    function _scaleDelegation(uint256 _delegatedAmount) internal pure returns (uint32) {
        return (_delegatedAmount / DELGATION_SCALING_FACTOR).toUint32();
    }

    function _addDelegationInDelegationArray(uint32[] calldata _delegationArray, uint256 _index, uint32 _scaledAmount)
        internal
        pure
        returns (uint32[] memory)
    {
        uint32[] memory _newDelegationArray = _delegationArray;
        _newDelegationArray[_index] = _newDelegationArray[_index] + _scaledAmount;
        return _newDelegationArray;
    }

    function _decreaseDelegationInDelegationArray(
        uint32[] calldata _delegationArray,
        uint256 _index,
        uint32 _scaledAmount
    ) internal pure returns (uint32[] memory) {
        uint32[] memory _newDelegationArray = _delegationArray;
        _newDelegationArray[_index] = _newDelegationArray[_index] - _scaledAmount;
        return _newDelegationArray;
    }

    function _mintPoolShares(
        RelayerId _relayerId,
        DelegatorAddress _delegatorAddress,
        uint256 _delegatedAmount,
        TokenAddress _pool
    ) internal {
        TADStorage storage ds = getTADStorage();
        RMStorage storage rms = getRMStorage();

        if (!rms.relayerInfo[_relayerId].isGasTokenSupported[_pool]) {
            revert PoolNotSupported(_relayerId, _pool);
        }
        FixedPointType sharePrice_ = sharePrice(_relayerId, _pool);
        FixedPointType sharesMinted = (_delegatedAmount.toFixedPointType() / sharePrice_);

        ds.shares[_relayerId][_delegatorAddress][_pool] = ds.shares[_relayerId][_delegatorAddress][_pool] + sharesMinted;
        ds.totalShares[_relayerId][_pool] = ds.totalShares[_relayerId][_pool] + sharesMinted;

        emit SharesMinted(_relayerId, _delegatorAddress, _pool, _delegatedAmount, sharesMinted, sharePrice_);
    }

    function delegate(
        uint32[] calldata _currentStakeArray,
        uint32[] calldata _prevDelegationArray,
        RelayerId _relayerId,
        uint256 _amount
    )
        external
        override
        verifyStakeArrayHash(_currentStakeArray)
        verifyDelegationArrayHash(_prevDelegationArray)
        onlyStakedRelayer(_relayerId)
    {
        RMStorage storage rms = getRMStorage();
        TADStorage storage ds = getTADStorage();

        rms.bondToken.safeTransferFrom(msg.sender, address(this), _amount);
        DelegatorAddress delegatorAddress = DelegatorAddress.wrap(msg.sender);

        TokenAddress[] storage supportedGasTokens = rms.relayerInfo[_relayerId].supportedGasTokens;
        uint256 length = supportedGasTokens.length;
        if (length == 0) {
            revert NoSupportedGasTokens(_relayerId);
        }

        for (uint256 i = 0; i < length;) {
            _mintPoolShares(_relayerId, delegatorAddress, _amount, supportedGasTokens[i]);
            unchecked {
                ++i;
            }
        }

        ds.delegation[_relayerId][delegatorAddress] += _amount;
        ds.totalDelegation[_relayerId] += _amount;

        uint32[] memory _newDelegationArray = _addDelegationInDelegationArray(
            _prevDelegationArray, rms.relayerInfo[_relayerId].index, _scaleDelegation(_amount)
        );

        // TODO: Update CDF after Delay
        _updateAccountingState(_currentStakeArray, false, _newDelegationArray, true);

        emit DelegationAdded(_relayerId, delegatorAddress, _amount);
    }

    function _processRewards(RelayerId _relayerId, TokenAddress _pool, DelegatorAddress _delegatorAddress) internal {
        TADStorage storage ds = getTADStorage();
        RMStorage storage rms = getRMStorage();

        if (!rms.relayerInfo[_relayerId].isGasTokenSupported[_pool]) {
            revert PoolNotSupported(_relayerId, _pool);
        }

        uint256 rewardsEarned_ = rewardsEarned(_relayerId, _pool, _delegatorAddress);

        if (rewardsEarned_ != 0) {
            ds.unclaimedRewards[_relayerId][_pool] -= rewardsEarned_;
            ds.totalShares[_relayerId][_pool] =
                ds.totalShares[_relayerId][_pool] - ds.shares[_relayerId][_delegatorAddress][_pool];
            ds.shares[_relayerId][_delegatorAddress][_pool] = uint256(0).toFixedPointType();

            _transfer(_pool, DelegatorAddress.unwrap(_delegatorAddress), rewardsEarned_);
            emit RewardSent(_relayerId, _delegatorAddress, _pool, rewardsEarned_);
        }
    }

    // TODO: Non Reentrant
    // TODO: Partial Claim?
    // TODO: Implement delay
    // TODO: What if the relayer has already un-registered?
    function unDelegate(
        uint32[] calldata _currentStakeArray,
        uint32[] calldata _prevDelegationArray,
        RelayerId _relayerId
    ) external override verifyStakeArrayHash(_currentStakeArray) verifyDelegationArrayHash(_prevDelegationArray) {
        TADStorage storage ds = getTADStorage();
        RMStorage storage rms = getRMStorage();

        DelegatorAddress delegatorAddress = DelegatorAddress.wrap(msg.sender);

        TokenAddress[] storage supportedGasTokens = rms.relayerInfo[_relayerId].supportedGasTokens;
        uint256 length = supportedGasTokens.length;

        // TODO: What if relayer removes support for a token once rewards are accrued?
        for (uint256 i = 0; i < length;) {
            _processRewards(_relayerId, supportedGasTokens[i], delegatorAddress);
            unchecked {
                ++i;
            }
        }

        uint256 delegation_ = ds.delegation[_relayerId][delegatorAddress];
        uint32[] memory _newDelegationArray = _decreaseDelegationInDelegationArray(
            _prevDelegationArray, rms.relayerInfo[_relayerId].index, _scaleDelegation(delegation_)
        );
        ds.totalDelegation[_relayerId] -= delegation_;
        ds.delegation[_relayerId][delegatorAddress] = 0;

        // TODO: Update CDF after Delay
        _updateAccountingState(_currentStakeArray, false, _newDelegationArray, true);

        emit DelegationRemoved(_relayerId, delegatorAddress, delegation_);
    }

    function sharePrice(RelayerId _relayerId, TokenAddress _tokenAddress)
        public
        view
        override
        returns (FixedPointType)
    {
        TADStorage storage ds = getTADStorage();
        if (ds.totalShares[_relayerId][_tokenAddress] == uint256(0).toFixedPointType()) {
            return uint256(1).toFixedPointType();
        }
        FixedPointType totalDelegation_ = ds.totalDelegation[_relayerId].toFixedPointType();
        FixedPointType unclaimedRewards_ = ds.unclaimedRewards[_relayerId][_tokenAddress].toFixedPointType();
        FixedPointType totalShares_ = ds.totalShares[_relayerId][_tokenAddress];

        return (totalDelegation_ + unclaimedRewards_) / totalShares_;
    }

    function rewardsEarned(RelayerId _relayerId, TokenAddress _tokenAddres, DelegatorAddress _delegatorAddress)
        public
        view
        override
        returns (uint256)
    {
        TADStorage storage ds = getTADStorage();

        FixedPointType shares_ = ds.shares[_relayerId][_delegatorAddress][_tokenAddres];
        FixedPointType delegation_ = ds.delegation[_relayerId][_delegatorAddress].toFixedPointType();
        FixedPointType rewards = shares_ * sharePrice(_relayerId, _tokenAddres) - delegation_;

        return rewards.toUint256();
    }

    ////////////////////////// Getters //////////////////////////
    function totalDelegation(RelayerId _relayerId) external view override returns (uint256) {
        TADStorage storage ds = getTADStorage();
        return ds.totalDelegation[_relayerId];
    }

    function delegation(RelayerId _relayerId, DelegatorAddress _delegatorAddress)
        external
        view
        override
        returns (uint256)
    {
        TADStorage storage ds = getTADStorage();
        return ds.delegation[_relayerId][_delegatorAddress];
    }

    function shares(RelayerId _relayerId, DelegatorAddress _delegatorAddress, TokenAddress _tokenAddress)
        external
        view
        override
        returns (FixedPointType)
    {
        TADStorage storage ds = getTADStorage();
        return ds.shares[_relayerId][_delegatorAddress][_tokenAddress];
    }

    function totalShares(RelayerId _relayerId, TokenAddress _tokenAddress)
        external
        view
        override
        returns (FixedPointType)
    {
        TADStorage storage ds = getTADStorage();
        return ds.totalShares[_relayerId][_tokenAddress];
    }

    function unclaimedRewards(RelayerId _relayerId, TokenAddress _tokenAddress)
        external
        view
        override
        returns (uint256)
    {
        TADStorage storage ds = getTADStorage();
        return ds.unclaimedRewards[_relayerId][_tokenAddress];
    }

    function getDelegationArray() external view override returns (uint32[] memory) {
        TADStorage storage ds = getTADStorage();
        RMStorage storage rms = getRMStorage();
        uint256 length = rms.relayerCount;
        uint32[] memory delegationArray = new uint32[](length);

        for (uint256 i = 0; i < length;) {
            delegationArray[i] = _scaleDelegation(ds.totalDelegation[rms.relayerIndexToRelayer[i]]);
            unchecked {
                ++i;
            }
        }

        return delegationArray;
    }
}
