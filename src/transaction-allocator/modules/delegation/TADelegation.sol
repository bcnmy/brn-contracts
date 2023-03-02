// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";

import "./TADelegationStorage.sol";
import "./interfaces/ITADelegation.sol";
import "../relayer-management/TARelayerManagementStorage.sol";
import "src/library/FixedPointArithmetic.sol";
import "../../common/TAConstants.sol";
import "../../common/TAHelpers.sol";

contract TADelegation is TADelegationStorage, TARelayerManagementStorage, ITADelegation, TAHelpers {
    using FixedPointTypeHelper for FixedPointType;
    using Uint256WrapperHelper for uint256;
    using SafeERC20 for IERC20;

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

    function delegate(RelayerAddress _relayerAddress, uint256 _amount) external {
        RMStorage storage rms = getRMStorage();
        TADStorage storage ds = getTADStorage();

        rms.bondToken.safeTransferFrom(msg.sender, address(this), _amount);
        DelegatorAddress delegatorAddress = DelegatorAddress.wrap(msg.sender);

        TokenAddress[] storage supportedGasTokens = rms.relayerInfo[_relayerAddress].supportedGasTokens;
        uint256 length = supportedGasTokens.length;

        for (uint256 i = 0; i < length;) {
            _mintPoolShares(_relayerAddress, delegatorAddress, _amount, supportedGasTokens[i]);
            unchecked {
                ++i;
            }
        }

        ds.delegation[_relayerAddress][delegatorAddress] += _amount;
        ds.totalDelegation[_relayerAddress] += _amount;

        // TODO: Update CDF after Delay

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
        ds.unclaimedRewards[_relayerAddress][_pool] -= rewardsEarned_;
        ds.totalShares[_relayerAddress][_pool] =
            ds.totalShares[_relayerAddress][_pool] - ds.shares[_relayerAddress][_delegatorAddress][_pool];
        ds.shares[_relayerAddress][_delegatorAddress][_pool] = uint256(0).toFixedPointType();

        if (rewardsEarned_ != 0) {
            _transfer(_pool, DelegatorAddress.unwrap(_delegatorAddress), rewardsEarned_);
            emit RewardSent(_relayerAddress, _delegatorAddress, _pool, rewardsEarned_);
        }
    }

    // TODO: Non Reentrant
    // TODO: Partial Claim?
    // TODO: Implement delay
    function unDelegate(RelayerAddress _relayerAddress) external {
        TADStorage storage ds = getTADStorage();
        RMStorage storage rms = getRMStorage();

        DelegatorAddress delegatorAddress = DelegatorAddress.wrap(msg.sender);

        TokenAddress[] storage supportedGasTokens = rms.relayerInfo[_relayerAddress].supportedGasTokens;
        uint256 length = supportedGasTokens.length;

        for (uint256 i = 0; i < length;) {
            _processRewards(_relayerAddress, supportedGasTokens[i], delegatorAddress);
            unchecked {
                ++i;
            }
        }

        ds.totalDelegation[_relayerAddress] -= ds.delegation[_relayerAddress][delegatorAddress];
        ds.delegation[_relayerAddress][delegatorAddress] = 0;

        // TODO: Update CDF after Delay

        emit DelegationRemoved(_relayerAddress, delegatorAddress, ds.delegation[_relayerAddress][delegatorAddress]);
    }

    function sharePrice(RelayerAddress _relayerAddress, TokenAddress _tokenAddress)
        public
        view
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
    ) public view returns (uint256) {
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
}
