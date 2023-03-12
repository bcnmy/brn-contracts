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
        RelayerAddress _relayerAddress,
        DelegatorAddress _delegatorAddress,
        uint256 _delegatedAmount,
        TokenAddress _pool
    ) internal {
        TADStorage storage ds = getTADStorage();
        RMStorage storage rms = getRMStorage();

        if (!rms.relayerInfo[_relayerAddress].isGasTokenSupported[_pool]) {
            revert PoolNotSupported(_relayerAddress, _pool);
        }
        FixedPointType sharePrice_ = sharePrice(_relayerAddress, _pool);
        FixedPointType sharesMinted = (_delegatedAmount.toFixedPointType() / sharePrice_);

        ds.shares[_relayerAddress][_delegatorAddress][_pool] =
            ds.shares[_relayerAddress][_delegatorAddress][_pool] + sharesMinted;
        ds.totalShares[_relayerAddress][_pool] = ds.totalShares[_relayerAddress][_pool] + sharesMinted;

        emit SharesMinted(_relayerAddress, _delegatorAddress, _pool, _delegatedAmount, sharesMinted, sharePrice_);
    }

    function delegate(
        uint32[] calldata _currentStakeArray,
        uint32[] calldata _prevDelegationArray,
        RelayerAddress _relayerAddress,
        uint256 _amount
    )
        external
        override
        verifyStakeArrayHash(_currentStakeArray)
        verifyDelegationArrayHash(_prevDelegationArray)
        onlyStakedRelayer(_relayerAddress)
    {
        RMStorage storage rms = getRMStorage();
        TADStorage storage ds = getTADStorage();

        rms.bondToken.safeTransferFrom(msg.sender, address(this), _amount);
        DelegatorAddress delegatorAddress = DelegatorAddress.wrap(msg.sender);

        TokenAddress[] storage supportedPools_ = ds.supportedPools[_relayerAddress];
        uint256 length = supportedPools_.length;
        if (length == 0) {
            revert NoSupportedGasTokens(_relayerAddress);
        }

        for (uint256 i = 0; i < length;) {
            _mintPoolShares(_relayerAddress, delegatorAddress, _amount, supportedPools_[i]);
            unchecked {
                ++i;
            }
        }

        ds.delegation[_relayerAddress][delegatorAddress] += _amount;
        ds.totalDelegation[_relayerAddress] += _amount;

        uint32[] memory _newDelegationArray = _addDelegationInDelegationArray(
            _prevDelegationArray, rms.relayerInfo[_relayerAddress].index, _scaleDelegation(_amount)
        );

        // TODO: Update CDF after Delay
        _updateAccountingState(_currentStakeArray, false, _newDelegationArray, true);

        emit DelegationAdded(_relayerAddress, delegatorAddress, _amount);
    }

    function _processRewards(RelayerAddress _relayerAddress, TokenAddress _pool, DelegatorAddress _delegatorAddress)
        internal
    {
        TADStorage storage ds = getTADStorage();
        RMStorage storage rms = getRMStorage();

        if (!rms.relayerInfo[_relayerAddress].isGasTokenSupported[_pool]) {
            revert PoolNotSupported(_relayerAddress, _pool);
        }

        uint256 rewardsEarned_ = rewardsEarned(_relayerAddress, _pool, _delegatorAddress);

        if (rewardsEarned_ != 0) {
            ds.unclaimedRewards[_relayerAddress][_pool] -= rewardsEarned_;
            ds.totalShares[_relayerAddress][_pool] =
                ds.totalShares[_relayerAddress][_pool] - ds.shares[_relayerAddress][_delegatorAddress][_pool];
            ds.shares[_relayerAddress][_delegatorAddress][_pool] = uint256(0).toFixedPointType();

            _transfer(_pool, DelegatorAddress.unwrap(_delegatorAddress), rewardsEarned_);
            emit RewardSent(_relayerAddress, _delegatorAddress, _pool, rewardsEarned_);
        }
    }

    // TODO: Non Reentrant
    // TODO: Partial Claim?
    // TODO: Implement delay
    function unDelegate(
        uint32[] calldata _currentStakeArray,
        uint32[] calldata _prevDelegationArray,
        RelayerAddress _relayerAddress
    ) external override verifyStakeArrayHash(_currentStakeArray) verifyDelegationArrayHash(_prevDelegationArray) {
        TADStorage storage ds = getTADStorage();
        RMStorage storage rms = getRMStorage();

        DelegatorAddress delegatorAddress = DelegatorAddress.wrap(msg.sender);

        TokenAddress[] storage supportedPools_ = ds.supportedPools[_relayerAddress];
        uint256 length = supportedPools_.length;

        // TODO: What if relayer removes support for a token once rewards are accrued?
        for (uint256 i = 0; i < length;) {
            _processRewards(_relayerAddress, supportedPools_[i], delegatorAddress);
            unchecked {
                ++i;
            }
        }

        uint256 delegation_ = ds.delegation[_relayerAddress][delegatorAddress];
        ds.totalDelegation[_relayerAddress] -= delegation_;
        ds.delegation[_relayerAddress][delegatorAddress] = 0;

        // TODO: Update CDF after Delay
        // Update the CDF if and only if the relayer is still registered
        // There can be a case where the relayer is unregistered and the user still has rewards
        if (_isStakedRelayer(_relayerAddress)) {
            uint32[] memory _newDelegationArray = _decreaseDelegationInDelegationArray(
                _prevDelegationArray, rms.relayerInfo[_relayerAddress].index, _scaleDelegation(delegation_)
            );
            _updateAccountingState(_currentStakeArray, false, _newDelegationArray, true);
        }

        emit DelegationRemoved(_relayerAddress, delegatorAddress, delegation_);
    }

    function sharePrice(RelayerAddress _relayerAddress, TokenAddress _tokenAddress)
        public
        view
        override
        returns (FixedPointType)
    {
        TADStorage storage ds = getTADStorage();
        if (ds.totalShares[_relayerAddress][_tokenAddress] == uint256(0).toFixedPointType()) {
            return uint256(1).toFixedPointType();
        }
        FixedPointType totalDelegation_ = ds.totalDelegation[_relayerAddress].toFixedPointType();
        FixedPointType unclaimedRewards_ = ds.unclaimedRewards[_relayerAddress][_tokenAddress].toFixedPointType();
        FixedPointType totalShares_ = ds.totalShares[_relayerAddress][_tokenAddress];

        return (totalDelegation_ + unclaimedRewards_) / totalShares_;
    }

    function rewardsEarned(
        RelayerAddress _relayerAddress,
        TokenAddress _tokenAddres,
        DelegatorAddress _delegatorAddress
    ) public view override returns (uint256) {
        TADStorage storage ds = getTADStorage();

        FixedPointType shares_ = ds.shares[_relayerAddress][_delegatorAddress][_tokenAddres];
        FixedPointType delegation_ = ds.delegation[_relayerAddress][_delegatorAddress].toFixedPointType();
        FixedPointType rewards = shares_ * sharePrice(_relayerAddress, _tokenAddres) - delegation_;

        return rewards.toUint256();
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

    function supportedPools(RelayerAddress _relayerAddress) external view override returns (TokenAddress[] memory) {
        TADStorage storage ds = getTADStorage();
        return ds.supportedPools[_relayerAddress];
    }
}
