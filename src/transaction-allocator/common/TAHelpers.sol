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

import "forge-std/console2.sol";

abstract contract TAHelpers is TARelayerManagementStorage, TADelegationStorage, ITAHelpers {
    using SafeERC20 for IERC20;
    using SafeCast for uint256;
    using Uint256WrapperHelper for uint256;
    using FixedPointTypeHelper for FixedPointType;

    ////////////////////////////// Hash Functions //////////////////////////////
    function _hashUint32ArrayCalldata(uint32[] calldata _array) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked((_array)));
    }

    function _hashUint32ArrayMemory(uint32[] memory _array) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked((_array)));
    }

    function _hashUint16ArrayCalldata(uint16[] calldata _array) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked((_array)));
    }

    function _hashUint16ArrayMemory(uint16[] memory _array) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked((_array)));
    }

    ////////////////////////////// Verification Helpers //////////////////////////////
    modifier verifyDelegationArrayHash(uint32[] calldata _array) {
        if (!_verifyDelegationArrayHash(_array)) {
            revert InvalidDelegationArrayHash();
        }
        _;
    }

    modifier verifyStakeArrayHash(uint32[] calldata _array) {
        if (!_verifyStakeArrayHash(_array)) {
            revert InvalidStakeArrayHash();
        }
        _;
    }

    modifier onlyStakedRelayer(RelayerAddress _relayer) {
        if (!_isStakedRelayer(_relayer)) {
            revert InvalidRelayer(_relayer);
        }
        _;
    }

    function _verifyDelegationArrayHash(uint32[] calldata _array) internal view returns (bool) {
        TADStorage storage ds = getTADStorage();
        return ds.delegationArrayHash == _hashUint32ArrayCalldata(_array);
    }

    function _verifyStakeArrayHash(uint32[] calldata _array) internal view returns (bool) {
        RMStorage storage ds = getRMStorage();
        return ds.stakeArrayHash == _hashUint32ArrayCalldata(_array);
    }

    function _verifyCdfHashAtWindow(uint16[] calldata _array, uint256 __windowIndex, uint256 _cdfLogIndex)
        internal
        view
        returns (bool)
    {
        RMStorage storage ds = getRMStorage();

        if (_cdfLogIndex >= ds.cdfHashUpdateLog.length) {
            return false;
        }

        if (
            !(
                ds.cdfHashUpdateLog[_cdfLogIndex].windowIndex <= __windowIndex
                    && (
                        _cdfLogIndex == ds.cdfHashUpdateLog.length - 1
                            || ds.cdfHashUpdateLog[_cdfLogIndex + 1].windowIndex > __windowIndex
                    )
            )
        ) {
            return false;
        }

        return ds.cdfHashUpdateLog[_cdfLogIndex].cdfHash == _hashUint16ArrayCalldata(_array);
    }

    function _isStakedRelayer(RelayerAddress _relayer) internal view returns (bool) {
        return getRMStorage().relayerInfo[_relayer].stake > 0;
    }

    ////////////////////////////// Relayer Selection //////////////////////////////
    function _windowIndex(uint256 _blockNumber) internal view returns (uint256) {
        return _blockNumber / getRMStorage().blocksPerWindow;
    }

    function _windowIndexToStartingBlock(uint256 __windowIndex) internal view returns (uint256) {
        return __windowIndex * getRMStorage().blocksPerWindow;
    }

    function _randomCdfNumber(uint256 _blockNumber, uint256 _iter, uint256 _max) internal view returns (uint256) {
        // The seed for jth iteration is a function of the base seed and j
        uint256 baseSeed = uint256(keccak256(abi.encodePacked(_windowIndex(_blockNumber))));
        uint256 seed = uint256(keccak256(abi.encodePacked(baseSeed, _iter)));
        return (seed % _max);
    }

    function _verifyRelayerSelection(
        address _relayer,
        uint16[] calldata _cdf,
        uint256 _cdfUpdationLogIndex,
        uint256 _relayerIndex,
        uint256 _relayerGenerationIterationBitmap,
        uint256 _blockNumber
    ) internal view returns (bool) {
        RMStorage storage ds = getRMStorage();

        // uint256 iterationCount = _relayerGenerationIterations.length;
        uint256 stakeSum = _cdf[_cdf.length - 1];

        // Verify CDF
        if (!_verifyCdfHashAtWindow(_cdf, _windowIndex(_blockNumber), _cdfUpdationLogIndex)) {
            revert InvalidCdfArrayHash();
        }

        // Verify Each Iteration against _cdfIndex in _cdf
        uint256 relayerGenerationIteration = 0;

        while (_relayerGenerationIterationBitmap != 0) {
            if (_relayerGenerationIterationBitmap % 2 == 1) {
                if (relayerGenerationIteration >= ds.relayersPerWindow) {
                    revert InvalidRelayerGenerationIteration();
                }

                // Verify if correct stake prefix sum index has been provided
                uint256 randomRelayerStake = _randomCdfNumber(_blockNumber, relayerGenerationIteration, stakeSum);

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

        RelayerAddress relayerAddress = ds.relayerIndexToRelayerAddress[_relayerIndex];
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
        returns (uint16[] memory, bytes32)
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

        return (cdf, _hashUint16ArrayMemory(cdf));
    }

    function _updateAccountingState(
        uint32[] memory _stakeArray,
        bool _shouldUpdateStakeAccounting,
        uint32[] memory _delegationArray,
        bool _shouldUpdateDelegationAccounting
    ) internal returns (uint256) {
        RMStorage storage ds = getRMStorage();

        // Update Stake Array Hash
        if (_shouldUpdateStakeAccounting) {
            ds.stakeArrayHash = _hashUint32ArrayMemory(_stakeArray);
            emit StakeArrayUpdated(ds.stakeArrayHash);
        }

        // Update Delegation Array Hash
        if (_shouldUpdateDelegationAccounting) {
            TADStorage storage tds = getTADStorage();
            tds.delegationArrayHash = _hashUint32ArrayMemory(_delegationArray);
            emit DelegationArrayUpdated(tds.delegationArrayHash);
        }

        if (_stakeArray.length != _delegationArray.length) {
            revert ParameterLengthMismatch();
        }

        // Update cdf hash
        (, bytes32 cdfHash) = _generateCdfArray(_stakeArray, _delegationArray);
        uint256 updateEffectiveAtwindowIndex =
            _windowIndex(block.number) + RELAYER_CONFIGURATION_UPDATE_DELAY_IN_WINDOWS;
        if (
            ds.cdfHashUpdateLog.length > 0
                && ds.cdfHashUpdateLog[ds.cdfHashUpdateLog.length - 1].windowIndex == updateEffectiveAtwindowIndex
        ) {
            ds.cdfHashUpdateLog[ds.cdfHashUpdateLog.length - 1].cdfHash = cdfHash;
            emit CdfArrayUpdateQueued(cdfHash, updateEffectiveAtwindowIndex, ds.cdfHashUpdateLog.length - 1);
        } else {
            ds.cdfHashUpdateLog.push(CdfHashUpdateInfo({windowIndex: updateEffectiveAtwindowIndex, cdfHash: cdfHash}));
            emit CdfArrayUpdateQueued(cdfHash, updateEffectiveAtwindowIndex, ds.cdfHashUpdateLog.length);
        }

        return updateEffectiveAtwindowIndex;
    }

    ////////////////////////////// Delegation ////////////////////////
    function _addDelegatorRewards(RelayerAddress _relayer, TokenAddress _token, uint256 _amount) internal {
        getTADStorage().unclaimedRewards[_relayer][_token] += _amount;

        emit DelegatorRewardsAdded(_relayer, _token, _amount);
    }

    ////////////////////////// Constant Rate Rewards //////////////////////////
    function _protocolRewardRate() internal view returns (uint256) {
        return (
            BASE_REWARD_RATE_PER_MIN_STAKE_PER_SEC.toFixedPointType() * MINIMUM_STAKE_AMOUNT.toFixedPointType()
                * fixedPointSqrt(getRMStorage().relayerCount.toFixedPointType())
        ).toUint256();
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

        // console2.log("Updating Protocol Rewards", block.timestamp, rs.lastUnpaidRewardUpdatedTimestamp);

        rs.unpaidProtocolRewards = _getUpdatedUnpaidProtocolRewards();
        rs.lastUnpaidRewardUpdatedTimestamp = block.timestamp;
    }

    function _protocolRewardRelayerSharePrice() internal view returns (FixedPointType) {
        RMStorage storage rs = getRMStorage();

        if (rs.totalShares == uint256(0).toFixedPointType()) {
            return uint256(1).toFixedPointType();
        }

        // console2.log("Total Stake", FixedPointType.unwrap(rs.totalStake.toFixedPointType()));
        // console2.log("Unpaid Rewards", FixedPointType.unwrap(rs.unpaidProtocolRewards.toFixedPointType()));
        // console2.log("Total Shares", FixedPointType.unwrap(rs.totalShares));

        return (rs.totalStake.toFixedPointType() + rs.unpaidProtocolRewards.toFixedPointType()) / rs.totalShares;
    }

    function _protocolRewardsEarnedByRelayer(RelayerAddress _relayer) internal view returns (uint256) {
        RMStorage storage rs = getRMStorage();

        FixedPointType totalValue = rs.relayerInfo[_relayer].rewardShares * _protocolRewardRelayerSharePrice();
        // console2.log("Reward Shares", FixedPointType.unwrap(rs.relayerInfo[_relayer].rewardShares));
        // console2.log("Share Price", FixedPointType.unwrap(_protocolRewardRelayerSharePrice()));
        // console2.log("Total value", FixedPointType.unwrap(totalValue));
        // console2.log("Stake", FixedPointType.unwrap(rs.relayerInfo[_relayer].stake.toFixedPointType()));

        FixedPointType rewards = totalValue - rs.relayerInfo[_relayer].stake.toFixedPointType();
        return rewards.toUint256();
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

        // console2.log("Pre rewards check", block.timestamp);

        uint256 rewards = _protocolRewardsEarnedByRelayer(_relayer);
        if (rewards == 0) {
            return (0, 0);
        }

        // console2.log("Post rewards check", block.timestamp, rewards);

        FixedPointType rewardShares = rewards.toFixedPointType() / _protocolRewardRelayerSharePrice();
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

    function _scaleStake(uint256 _stake) internal pure returns (uint32) {
        return (_stake / STAKE_SCALING_FACTOR).toUint32();
    }

    function _unscaleStake(uint32 _scaledStake) internal pure returns (uint256) {
        return _scaledStake * STAKE_SCALING_FACTOR;
    }
}
