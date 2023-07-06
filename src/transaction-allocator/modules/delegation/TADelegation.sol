// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import {IERC20} from "openzeppelin-contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "openzeppelin-contracts/token/ERC20/utils/SafeERC20.sol";

import {ITADelegation} from "./interfaces/ITADelegation.sol";
import {TADelegationGetters} from "./TADelegationGetters.sol";
import {TAHelpers} from "ta-common/TAHelpers.sol";
import {RAArrayHelper} from "src/library/arrays/RAArrayHelper.sol";
import {U256ArrayHelper} from "src/library/arrays/U256ArrayHelper.sol";
import {
    FixedPointType,
    FixedPointTypeHelper,
    Uint256WrapperHelper,
    FP_ZERO,
    FP_ONE
} from "src/library/FixedPointArithmetic.sol";
import {RelayerAddress, DelegatorAddress, TokenAddress} from "ta-common/TATypes.sol";
import {RelayerStateManager} from "ta-common/RelayerStateManager.sol";
import {NATIVE_TOKEN} from "ta-common/TAConstants.sol";

/// @title TADelegation
/// @dev Module for delegating tokens to relayers.
/// BICO holders can delegate their tokens to a relayer signaling support to the relayer activity.
/// Delegation increases the total effective staked amount of a relayer, which in turn increases the probability
/// of that particular relayer being selected to relay transactions.
/// Premiums and rewards of the relayers are shared with delegators according to the rules established in the economics of the BRN
///
/// The delegators earn rewards for each token in storage.supportedPools.
/// The accounting for each (relayer, token_pool) is done separately.
/// Each (relayer, token_pool) has a separate share price, determined as:
///    share_price{i} = (total_delegation_in_bico_to_relayer + unclaimed_rewards{i}) / total_shares_minted{i} for total_shares_minted{i} != 0
///                     1 for total_shares_minted{i} == 0
/// for the ith token in storage.supportedPools. Notice that total_delegation_in_bico_to_relayer is common for all supported tokens.
/// When a delegator delegates to a relayer, it receives shares for all tokens in storage.supportedPools, for that relayer.
contract TADelegation is TADelegationGetters, TAHelpers, ITADelegation {
    using FixedPointTypeHelper for FixedPointType;
    using Uint256WrapperHelper for uint256;
    using RAArrayHelper for RelayerAddress[];
    using U256ArrayHelper for uint256[];
    using SafeERC20 for IERC20;
    using RelayerStateManager for RelayerStateManager.RelayerState;

    /// @dev Mints delegation pool shares at the current share price for that relayer's pool
    /// @param _relayerAddress The relayer address to delegate to
    /// @param _delegatorAddress The delegator address
    /// @param _delegatedAmount The amount of bond tokens (bico) to delegate
    /// @param _pool The token for which shares are being minted
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

    /// @dev Mints delegation pool shares at the current share price in each supported pool for the delegator
    /// @param _relayerAddress The relayer address to delegate to
    /// @param _delegator The delegator address
    /// @param _amount The amount of bond tokens (bico) to delegate
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

    /// @dev Delegator are entitled to share of the protocol rewards generated for the relayer.
    ///      This function calcualtes the protocol rewards generated for the relayer since the last time it was calcualted,
    ///      splits the rewards b/w the relayer and the delegators based on the relayer's premium sharing configuration
    /// @param _relayer The relayer address for which the accounting is being updated
    function _updateRelayerProtocolRewards(RelayerAddress _relayer) internal {
        // Non-active relayer do not generate protocol rewards
        if (!_isActiveRelayer(_relayer)) {
            return;
        }

        uint256 updatedTotalUnpaidProtocolRewards = _getLatestTotalUnpaidProtocolRewardsAndUpdateUpdatedTimestamp();
        (uint256 relayerRewards, uint256 delegatorRewards, FixedPointType sharesToBurn) =
            _getPendingProtocolRewardsData(_relayer, updatedTotalUnpaidProtocolRewards);

        // Process delegator rewards
        RMStorage storage rs = getRMStorage();
        RelayerInfo storage relayerInfo = rs.relayerInfo[_relayer];

        if (delegatorRewards > 0) {
            _addDelegatorRewards(_relayer, TokenAddress.wrap(address(rs.bondToken)), delegatorRewards);
        }

        // Store the relayer's rewards in the relayer's state to claim later
        if (relayerRewards > 0) {
            relayerInfo.unpaidProtocolRewards += relayerRewards;
            emit RelayerProtocolRewardsGenerated(_relayer, relayerRewards);
        }

        // Update global accounting
        rs.totalUnpaidProtocolRewards = updatedTotalUnpaidProtocolRewards - relayerRewards - delegatorRewards;
        rs.totalProtocolRewardShares = rs.totalProtocolRewardShares - sharesToBurn;
        relayerInfo.rewardShares = relayerInfo.rewardShares - sharesToBurn;

        emit RelayerProtocolSharesBurnt(_relayer, sharesToBurn);
    }

    /// @inheritdoc ITADelegation
    function delegate(RelayerStateManager.RelayerState calldata _latestState, uint256 _relayerIndex, uint256 _amount)
        external
        override
        noSelfCall
    {
        if (_relayerIndex >= _latestState.relayers.length) {
            revert InvalidRelayerIndex();
        }

        _verifyExternalStateForRelayerStateUpdation(_latestState);

        RelayerAddress relayerAddress = _latestState.relayers[_relayerIndex];
        _updateRelayerProtocolRewards(relayerAddress);

        getRMStorage().bondToken.safeTransferFrom(msg.sender, address(this), _amount);
        TADStorage storage ds = getTADStorage();

        // Mint Shares for all supported pools
        DelegatorAddress delegatorAddress = DelegatorAddress.wrap(msg.sender);
        _mintAllPoolShares(relayerAddress, delegatorAddress, _amount);

        // Update global counters
        ds.delegation[relayerAddress][delegatorAddress] += _amount;
        ds.totalDelegation[relayerAddress] += _amount;
        emit DelegationAdded(relayerAddress, delegatorAddress, _amount);

        // Schedule the CDF update
        uint256[] memory newCdf = _latestState.increaseWeight(_relayerIndex, _amount);
        _cd_updateLatestRelayerState(_latestState.relayers, newCdf);
    }

    struct AmountOwed {
        TokenAddress token;
        uint256 amount;
    }

    /// @dev Calculate and return the rewards earned by the delegator for the given relayer and pool, including the original delegation amount
    /// @param _relayerAddress The relayer address
    /// @param _pool The token for which rewards are being calculated
    /// @param _delegatorAddress The delegator address
    /// @param _bondToken The bond token address
    /// @param _delegation The amount of bond tokens (bico) delegated
    /// @return The amount of rewards earned by the delegator. If _pool==_bondToken, include the original delegation amount
    function _processRewards(
        RelayerAddress _relayerAddress,
        TokenAddress _pool,
        DelegatorAddress _delegatorAddress,
        TokenAddress _bondToken,
        uint256 _delegation
    ) internal returns (AmountOwed memory) {
        TADStorage storage ds = getTADStorage();

        uint256 rewardsEarned_ = _delegationRewardsEarned(_relayerAddress, _pool, _delegatorAddress);

        if (rewardsEarned_ != 0) {
            ds.unclaimedRewards[_relayerAddress][_pool] -= rewardsEarned_;
        }

        // Update global counters
        ds.totalShares[_relayerAddress][_pool] =
            ds.totalShares[_relayerAddress][_pool] - ds.shares[_relayerAddress][_delegatorAddress][_pool];
        ds.shares[_relayerAddress][_delegatorAddress][_pool] = FP_ZERO;

        return AmountOwed({token: _pool, amount: _pool == _bondToken ? rewardsEarned_ + _delegation : rewardsEarned_});
    }

    /// @inheritdoc ITADelegation
    function undelegate(
        RelayerStateManager.RelayerState calldata _latestState,
        RelayerAddress _relayerAddress,
        uint256 _relayerIndex
    ) external override noSelfCall {
        _verifyExternalStateForRelayerStateUpdation(_latestState);

        TADStorage storage ds = getTADStorage();

        _updateRelayerProtocolRewards(_relayerAddress);

        uint256 delegation_ = ds.delegation[_relayerAddress][DelegatorAddress.wrap(msg.sender)];
        TokenAddress bondToken = TokenAddress.wrap(address(getRMStorage().bondToken));

        // Burn shares for each pool and calculate rewards
        uint256 length = ds.supportedPools.length;
        AmountOwed[] memory amountOwed = new AmountOwed[](length);
        for (uint256 i; i != length;) {
            amountOwed[i] = _processRewards(
                _relayerAddress, ds.supportedPools[i], DelegatorAddress.wrap(msg.sender), bondToken, delegation_
            );
            unchecked {
                ++i;
            }
        }

        // Update delegation state
        ds.totalDelegation[_relayerAddress] -= delegation_;
        delete ds.delegation[_relayerAddress][DelegatorAddress.wrap(msg.sender)];
        emit DelegationRemoved(_relayerAddress, DelegatorAddress.wrap(msg.sender), delegation_);

        // Store the rewards and the original stake to be withdrawn after the delay
        DelegationWithdrawal storage withdrawal =
            ds.delegationWithdrawal[_relayerAddress][DelegatorAddress.wrap(msg.sender)];
        withdrawal.minWithdrawalTimestamp = block.timestamp + ds.delegationWithdrawDelayInSec;
        for (uint256 i; i != length;) {
            AmountOwed memory t = amountOwed[i];
            if (t.amount > 0) {
                withdrawal.amounts[t.token] += t.amount;
                emit DelegationWithdrawalCreated(
                    _relayerAddress,
                    DelegatorAddress.wrap(msg.sender),
                    t.token,
                    t.amount,
                    withdrawal.minWithdrawalTimestamp
                );
            }
            unchecked {
                ++i;
            }
        }

        // Update the CDF if and only if the relayer is still registered
        // The delegator should be allowed to undelegate even if the relayer has been removed
        if (_isActiveRelayer(_relayerAddress)) {
            // Verify the relayer index
            if (_latestState.relayers[_relayerIndex] != _relayerAddress) {
                revert InvalidRelayerIndex();
            }

            uint256[] memory newCdf = _latestState.decreaseWeight(_relayerIndex, delegation_);
            _cd_updateLatestRelayerState(_latestState.relayers, newCdf);
        }
    }

    /// @dev The price of for the given relayer and pool
    /// @param _relayerAddress The relayer address
    /// @param _tokenAddress The token (pool) address
    /// @param _extraUnclaimedRewards Rewards to considered in the share price calculation which are not stored in the contract (yet)
    function _delegationSharePrice(
        RelayerAddress _relayerAddress,
        TokenAddress _tokenAddress,
        uint256 _extraUnclaimedRewards
    ) internal view returns (FixedPointType) {
        TADStorage storage ds = getTADStorage();
        FixedPointType totalShares_ = ds.totalShares[_relayerAddress][_tokenAddress];

        if (totalShares_ == FP_ZERO) {
            return FP_ONE;
        }

        return (
            ds.totalDelegation[_relayerAddress] + ds.unclaimedRewards[_relayerAddress][_tokenAddress]
                + _extraUnclaimedRewards
        ).fp() / totalShares_;
    }

    /// @dev Calculate the rewards earned by the delegator for the given relayer and pool
    /// @param _relayerAddress The relayer address
    /// @param _tokenAddress The token (pool) address
    /// @param _delegatorAddress The delegator address
    function _delegationRewardsEarned(
        RelayerAddress _relayerAddress,
        TokenAddress _tokenAddress,
        DelegatorAddress _delegatorAddress
    ) internal view returns (uint256) {
        TADStorage storage ds = getTADStorage();

        FixedPointType currentValue = ds.shares[_relayerAddress][_delegatorAddress][_tokenAddress]
            * _delegationSharePrice(_relayerAddress, _tokenAddress, 0);
        FixedPointType delegation_ = ds.delegation[_relayerAddress][_delegatorAddress].fp();

        if (currentValue >= delegation_) {
            return (currentValue - delegation_).u256();
        }
        return 0;
    }

    /// @inheritdoc ITADelegation
    function claimableDelegationRewards(
        RelayerAddress _relayerAddress,
        TokenAddress _tokenAddress,
        DelegatorAddress _delegatorAddress
    ) external view noSelfCall returns (uint256) {
        TADStorage storage ds = getTADStorage();

        uint256 protocolDelegationRewards;

        if (TokenAddress.unwrap(_tokenAddress) == address(getRMStorage().bondToken)) {
            uint256 updatedTotalUnpaidProtocolRewards = _getLatestTotalUnpaidProtocolRewards();

            (, protocolDelegationRewards,) =
                _getPendingProtocolRewardsData(_relayerAddress, updatedTotalUnpaidProtocolRewards);
        }

        FixedPointType currentValue = ds.shares[_relayerAddress][_delegatorAddress][_tokenAddress]
            * _delegationSharePrice(_relayerAddress, _tokenAddress, protocolDelegationRewards);
        FixedPointType delegation_ = ds.delegation[_relayerAddress][_delegatorAddress].fp();

        if (currentValue >= delegation_) {
            return (currentValue - delegation_).u256();
        }
        return 0;
    }

    /// @inheritdoc ITADelegation
    function withdrawDelegation(RelayerAddress _relayerAddress) external noSelfCall {
        TokenAddress[] storage supportedPools = getTADStorage().supportedPools;
        DelegationWithdrawal storage withdrawal =
            getTADStorage().delegationWithdrawal[_relayerAddress][DelegatorAddress.wrap(msg.sender)];

        if (withdrawal.minWithdrawalTimestamp > block.timestamp) {
            revert WithdrawalNotReady(withdrawal.minWithdrawalTimestamp);
        }

        uint256 length = supportedPools.length;
        for (uint256 i; i != length;) {
            TokenAddress tokenAddress = supportedPools[i];

            uint256 amount = withdrawal.amounts[tokenAddress];
            delete withdrawal.amounts[tokenAddress];

            _transfer(tokenAddress, msg.sender, amount);

            emit RewardSent(_relayerAddress, DelegatorAddress.wrap(msg.sender), tokenAddress, amount);

            unchecked {
                ++i;
            }
        }

        delete getTADStorage().delegationWithdrawal[_relayerAddress][DelegatorAddress.wrap(msg.sender)];
    }

    /// @inheritdoc ITADelegation
    function addDelegationRewards(RelayerAddress _relayerAddress, uint256 _tokenIndex, uint256 _amount)
        external
        payable
        override
        noSelfCall
    {
        TADStorage storage ds = getTADStorage();

        if (_tokenIndex >= ds.supportedPools.length) {
            revert InvalidTokenIndex();
        }
        TokenAddress tokenAddress = ds.supportedPools[_tokenIndex];

        // Accept the tokens
        if (tokenAddress != NATIVE_TOKEN) {
            IERC20(TokenAddress.unwrap(tokenAddress)).safeTransferFrom(msg.sender, address(this), _amount);
        } else if (msg.value != _amount) {
            revert NativeAmountMismatch();
        }

        // Add to unclaimed rewards
        _addDelegatorRewards(_relayerAddress, tokenAddress, _amount);
    }
}
