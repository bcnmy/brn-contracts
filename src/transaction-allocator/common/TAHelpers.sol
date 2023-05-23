// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import "openzeppelin-contracts/contracts/utils/math/SafeCast.sol";

import "./interfaces/ITAHelpers.sol";
import "./TAConstants.sol";
import "./TATypes.sol";
import "../modules/relayer-management/TARelayerManagementStorage.sol";
import "../modules/delegation/TADelegationStorage.sol";
import "src/library/arrays/U32ArrayHelper.sol";
import "src/library/arrays/RAArrayHelper.sol";
import "src/library/arrays/U16ArrayHelper.sol";

import "forge-std/console2.sol";

abstract contract TAHelpers is TARelayerManagementStorage, TADelegationStorage, ITAHelpers {
    using SafeERC20 for IERC20;
    using SafeCast for uint256;
    using Uint256WrapperHelper for uint256;
    using FixedPointTypeHelper for FixedPointType;
    using VersionManager for VersionManager.VersionManagerState;
    using U32ArrayHelper for uint32[];
    using U16ArrayHelper for uint16[];
    using RAArrayHelper for RelayerAddress[];

    ////////////////////////////// Verification Helpers //////////////////////////////
    modifier onlyStakedRelayer(RelayerAddress _relayer) {
        if (!_isStakedRelayer(_relayer)) {
            revert InvalidRelayer(_relayer);
        }
        _;
    }

    modifier verifyLatestActiveRelayerList(RelayerAddress[] calldata _activeRelayers) {
        _verifyLatestActiveRelayerList(_activeRelayers);
        _;
    }

    function _isStakedRelayer(RelayerAddress _relayer) internal view returns (bool) {
        return getRMStorage().relayerInfo[_relayer].stake > 0;
    }

    function _verifyExternalStateForCdfUpdation(
        uint32[] calldata _currentStakeArray,
        uint32[] calldata _currentDelegationArray,
        RelayerAddress[] calldata _latestActiveRelayerArray
    ) internal view {
        RMStorage storage rs = getRMStorage();
        TADStorage storage ds = getTADStorage();

        if (rs.latestActiveRelayerStakeArrayHash != _currentStakeArray.cd_hash()) {
            revert InvalidStakeArrayHash();
        }

        if (ds.delegationArrayHash != _currentDelegationArray.cd_hash()) {
            revert InvalidDelegationArrayHash();
        }

        if (!rs.activeRelayerListVersionManager.verifyHashAgainstPendingState(_latestActiveRelayerArray.cd_hash())) {
            revert InvalidRelayersArrayHash();
        }
    }

    function _verifyExternalStateForTransactionAllocation(
        uint16[] calldata _cdf,
        RelayerAddress[] calldata _activeRelayers,
        uint256 _blockNumber
    ) internal view {
        RMStorage storage rs = getRMStorage();
        WindowIndex windowIndex = _windowIndex(_blockNumber);

        if (!rs.cdfVersionManager.verifyHashAgainstActiveState(_cdf.cd_hash(), windowIndex)) {
            revert InvalidCdfArrayHash();
        }

        if (!rs.activeRelayerListVersionManager.verifyHashAgainstActiveState(_activeRelayers.cd_hash(), windowIndex)) {
            revert InvalidRelayersArrayHash();
        }
    }

    function _verifyLatestActiveRelayerList(RelayerAddress[] calldata _activeRelayers) internal view {
        if (!getRMStorage().activeRelayerListVersionManager.verifyHashAgainstPendingState(_activeRelayers.cd_hash())) {
            revert InvalidRelayersArrayHash();
        }
    }

    function _verifyCurrentlyActiveRelayerList(RelayerAddress[] calldata _activeRelayers) internal view {
        if (
            !getRMStorage().activeRelayerListVersionManager.verifyHashAgainstActiveState(
                _activeRelayers.cd_hash(), _windowIndex(block.number)
            )
        ) {
            revert InvalidRelayersArrayHash();
        }
    }

    ////////////////////////////// Relayer Selection //////////////////////////////
    function _windowIndex(uint256 _blockNumber) internal view returns (WindowIndex) {
        return WindowIndex.wrap((_blockNumber / getRMStorage().blocksPerWindow).toUint64());
    }

    function _windowIndexToStartingBlock(uint256 __windowIndex) internal view returns (uint256) {
        return __windowIndex * getRMStorage().blocksPerWindow;
    }

    function _randomNumberForCdfSelection(uint256 _blockNumber, uint256 _iter, uint256 _max)
        internal
        view
        returns (uint256)
    {
        // The seed for jth iteration is a function of the base seed and j
        uint256 baseSeed = uint256(keccak256(abi.encodePacked(_windowIndex(_blockNumber))));
        uint256 seed = uint256(keccak256(abi.encodePacked(baseSeed, _iter)));
        return (seed % _max);
    }

    function _verifyRelayerSelection(
        address _relayer,
        uint16[] calldata _cdf,
        RelayerAddress[] calldata _activeRelayers,
        uint256 _relayerIndex,
        uint256 _relayerGenerationIterationBitmap,
        uint256 _blockNumber
    ) internal view returns (bool) {
        _verifyExternalStateForTransactionAllocation(_cdf, _activeRelayers, _blockNumber);

        RMStorage storage ds = getRMStorage();

        {
            // Verify Each Iteration against _cdfIndex in _cdf
            uint256 stakeSum = _cdf[_cdf.length - 1];
            uint256 relayerGenerationIteration;

            // TODO: Optimize iteration over set bits (potentially using x & -x flow)
            while (_relayerGenerationIterationBitmap != 0) {
                if (_relayerGenerationIterationBitmap % 2 == 1) {
                    if (relayerGenerationIteration >= ds.relayersPerWindow) {
                        revert InvalidRelayerGenerationIteration();
                    }

                    // Verify if correct stake prefix sum index has been provided
                    uint256 randomRelayerStake =
                        _randomNumberForCdfSelection(_blockNumber, relayerGenerationIteration, stakeSum);

                    if (
                        !(
                            (_relayerIndex == 0 || _cdf[_relayerIndex - 1] < randomRelayerStake)
                                && randomRelayerStake <= _cdf[_relayerIndex]
                        )
                    ) {
                        // The supplied index does not point to the correct interval
                        revert RelayerIndexDoesNotPointToSelectedCdfInterval();
                    }
                }

                unchecked {
                    ++relayerGenerationIteration;
                    _relayerGenerationIterationBitmap /= 2;
                }
            }
        }

        RelayerAddress relayerAddress = _activeRelayers[_relayerIndex];
        RelayerInfo storage node = ds.relayerInfo[relayerAddress];

        if (relayerAddress != RelayerAddress.wrap(_relayer) && !node.isAccount[RelayerAccountAddress.wrap(_relayer)]) {
            revert RelayerAddressDoesNotMatchSelectedRelayer();
        }

        return true;
    }

    ////////////////////////////// Relayer State //////////////////////////////
    function _generateCdfArray(uint32[] memory _stakeArray, uint32[] memory _delegationArray)
        internal
        pure
        returns (uint16[] memory)
    {
        uint16[] memory cdf = new uint16[](_stakeArray.length);
        uint256 totalStakeSum = 0;
        uint256 length = _stakeArray.length;
        for (uint256 i = 0; i < length;) {
            totalStakeSum += _stakeArray[i] + _delegationArray[i];
            unchecked {
                ++i;
            }
        }

        // Scale the values to fit uint16 and get the CDF
        uint256 sum = 0;
        for (uint256 i = 0; i < length;) {
            sum += _stakeArray[i] + _delegationArray[i];
            cdf[i] = ((sum * CDF_PRECISION_MULTIPLIER) / totalStakeSum).toUint16();
            unchecked {
                ++i;
            }
        }

        return cdf;
    }

    function _updateCdf(
        uint32[] memory _stakeArray,
        bool _shouldUpdateStakeAccounting,
        uint32[] memory _delegationArray,
        bool _shouldUpdateDelegationAccounting
    ) internal {
        if (_stakeArray.length != _delegationArray.length) {
            revert ParameterLengthMismatch();
        }

        RMStorage storage ds = getRMStorage();

        // Update Stake Array Hash
        if (_shouldUpdateStakeAccounting) {
            ds.latestActiveRelayerStakeArrayHash = _stakeArray.m_hash();
            emit StakeArrayUpdated(ds.latestActiveRelayerStakeArrayHash);
        }

        // Update Delegation Array Hash
        if (_shouldUpdateDelegationAccounting) {
            TADStorage storage tds = getTADStorage();
            tds.delegationArrayHash = _delegationArray.m_hash();
            emit DelegationArrayUpdated(tds.delegationArrayHash);
        }

        // Update cdf hash
        bytes32 cdfHash = _generateCdfArray(_stakeArray, _delegationArray).m_hash();
        ds.cdfVersionManager.setPendingState(cdfHash);
    }

    ////////////////////////////// Delegation ////////////////////////
    function _addDelegatorRewards(RelayerAddress _relayer, TokenAddress _token, uint256 _amount) internal {
        getTADStorage().unclaimedRewards[_relayer][_token] += _amount;

        emit DelegatorRewardsAdded(_relayer, _token, _amount);
    }

    ////////////////////////// Constant Rate Rewards //////////////////////////
    function _protocolRewardRate() internal view returns (uint256) {
        return (
            BASE_REWARD_RATE_PER_MIN_STAKE_PER_SEC.fp() * MINIMUM_STAKE_AMOUNT.fp()
                * (getRMStorage().relayerCount.fp().sqrt())
        ).u256();
    }

    function _getUpdatedUnpaidProtocolRewards() internal view returns (uint256) {
        RMStorage storage rs = getRMStorage();
        return
            rs.unpaidProtocolRewards + _protocolRewardRate() * (block.timestamp - rs.lastUnpaidRewardUpdatedTimestamp);
    }

    function _updateProtocolRewards() internal {
        // Update unpaid rewards
        RMStorage storage rs = getRMStorage();

        if (block.timestamp == rs.lastUnpaidRewardUpdatedTimestamp) {
            return;
        }

        rs.unpaidProtocolRewards = _getUpdatedUnpaidProtocolRewards();
        rs.lastUnpaidRewardUpdatedTimestamp = block.timestamp;
    }

    function _protocolRewardRelayerSharePrice() internal view returns (FixedPointType) {
        RMStorage storage rs = getRMStorage();

        if (rs.totalShares == FP_ZERO) {
            return FP_ONE;
        }
        return (rs.totalStake.fp() + rs.unpaidProtocolRewards.fp()) / rs.totalShares;
    }

    function _protocolRewardsEarnedByRelayer(RelayerAddress _relayer) internal view returns (uint256) {
        RMStorage storage rs = getRMStorage();
        FixedPointType totalValue = rs.relayerInfo[_relayer].rewardShares * _protocolRewardRelayerSharePrice();
        FixedPointType rewards = totalValue - rs.relayerInfo[_relayer].stake.fp();
        return rewards.u256();
    }

    function _splitRewards(uint256 _totalRewards, uint256 _delegatorRewardSharePercentage)
        internal
        pure
        returns (uint256, uint256)
    {
        uint256 delegatorRewards = (_totalRewards * _delegatorRewardSharePercentage) / (100 * PERCENTAGE_MULTIPLIER);
        return (_totalRewards - delegatorRewards, delegatorRewards);
    }

    function _burnRewardSharesForRelayerAndGetRewards(RelayerAddress _relayer) internal returns (uint256, uint256) {
        RMStorage storage rs = getRMStorage();

        uint256 rewards = _protocolRewardsEarnedByRelayer(_relayer);
        if (rewards == 0) {
            return (0, 0);
        }

        FixedPointType rewardShares = rewards.fp() / _protocolRewardRelayerSharePrice();
        rs.relayerInfo[_relayer].rewardShares = rs.relayerInfo[_relayer].rewardShares - rewardShares;
        rs.totalShares = rs.totalShares - rewardShares;

        (uint256 relayerRewards, uint256 delegatorRewards) =
            _splitRewards(rewards, rs.relayerInfo[_relayer].delegatorPoolPremiumShare);

        emit RelayerProtocolRewardSharesBurnt(_relayer, rewardShares, rewards, relayerRewards, delegatorRewards);

        return (relayerRewards, delegatorRewards);
    }

    ////////////////////////////// Misc //////////////////////////////
    function _transfer(TokenAddress _token, address _to, uint256 _amount) internal {
        if (_token == NATIVE_TOKEN) {
            uint256 balance = address(this).balance;
            if (balance < _amount) {
                revert InsufficientBalance(_token, balance, _amount);
            }

            (bool status,) = payable(_to).call{value: _amount}("");
            if (!status) {
                revert NativeTransferFailed(_to, _amount);
            }
        } else {
            IERC20 token = IERC20(TokenAddress.unwrap(_token));
            uint256 balance = token.balanceOf(address(this));
            if (balance < _amount) {
                revert InsufficientBalance(_token, balance, _amount);
            }

            token.safeTransfer(_to, _amount);
        }
    }

    // TODO: Measure gas and check if these are needed
    function _scaleStake(uint256 _stake) internal pure returns (uint32) {
        return (_stake / STAKE_SCALING_FACTOR).toUint32();
    }

    function _unscaleStake(uint32 _scaledStake) internal pure returns (uint256) {
        return _scaledStake * STAKE_SCALING_FACTOR;
    }
}
