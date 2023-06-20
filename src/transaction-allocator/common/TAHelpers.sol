// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import "openzeppelin-contracts/token/ERC20/IERC20.sol";
import "openzeppelin-contracts/token/ERC20/utils/SafeERC20.sol";
import "openzeppelin-contracts/utils/math/SafeCast.sol";
import "openzeppelin-contracts/utils/Address.sol";

import "./interfaces/ITAHelpers.sol";
import "./TAConstants.sol";
import "ta-relayer-management/TARelayerManagementStorage.sol";
import "ta-delegation/TADelegationStorage.sol";
import "src/library/arrays/U32ArrayHelper.sol";
import "src/library/arrays/RAArrayHelper.sol";
import "src/library/arrays/U16ArrayHelper.sol";

abstract contract TAHelpers is TARelayerManagementStorage, TADelegationStorage, ITAHelpers {
    using SafeERC20 for IERC20;
    using SafeCast for uint256;
    using Address for address payable;
    using Uint256WrapperHelper for uint256;
    using FixedPointTypeHelper for FixedPointType;
    using VersionManager for VersionManager.VersionManagerState;
    using U32ArrayHelper for uint32[];
    using U16ArrayHelper for uint16[];
    using RAArrayHelper for RelayerAddress[];

    modifier noSelfCall() {
        if (msg.sender == address(this)) {
            revert NoSelfCall();
        }
        _;
    }

    ////////////////////////////// Verification Helpers //////////////////////////////
    modifier onlySelf() {
        if (msg.sender != address(this)) {
            revert OnlySelf();
        }
        _;
    }

    modifier onlyActiveRelayer(RelayerAddress _relayer) {
        if (!_isActiveRelayer(_relayer)) {
            revert InvalidRelayer(_relayer);
        }
        _;
    }

    function _isActiveRelayer(RelayerAddress _relayer) internal view returns (bool) {
        return getRMStorage().relayerInfo[_relayer].status == RelayerStatus.Active;
    }

    function _getRelayerStateHash(bytes32 _cdfHash, bytes32 _relayerArrayHash) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked(_cdfHash, _relayerArrayHash));
    }

    function _verifyExternalStateForRelayerStateUpdation(bytes32 _cdfHash, bytes32 _activeRelayersHash) internal view {
        RMStorage storage rs = getRMStorage();

        if (
            !rs.relayerStateVersionManager.verifyHashAgainstLatestState(
                _getRelayerStateHash(_cdfHash, _activeRelayersHash)
            )
        ) {
            revert InvalidLatestRelayerState();
        }
    }

    function _verifyExternalStateForTransactionAllocation(
        bytes32 _cdfHash,
        bytes32 _activeRelayersHash,
        uint256 _blockNumber
    ) internal view {
        RMStorage storage rs = getRMStorage();
        uint256 windowIndex = _windowIndex(_blockNumber);

        if (
            !rs.relayerStateVersionManager.verifyHashAgainstActiveState(
                _getRelayerStateHash(_cdfHash, _activeRelayersHash), windowIndex
            )
        ) {
            revert InvalidActiveRelayerState();
        }
    }

    ////////////////////////////// Relayer Selection //////////////////////////////
    function _windowIndex(uint256 _blockNumber) internal view returns (uint256) {
        return _blockNumber / getRMStorage().blocksPerWindow;
    }

    function _nextWindowForUpdate(uint256 _blockNumber) internal view returns (uint256) {
        return _windowIndex(_blockNumber) + getRMStorage().relayerStateUpdateDelayInWindows;
    }

    ////////////////////////////// Relayer State //////////////////////////////
    function _generateCdfArray_c(RelayerAddress[] calldata _activeRelayers) internal view returns (uint16[] memory) {
        RMStorage storage rs = getRMStorage();
        TADStorage storage ds = getTADStorage();

        uint256 length = _activeRelayers.length;
        uint16[] memory cdf = new uint16[](length);
        uint256 totalStakeSum;

        for (uint256 i; i != length;) {
            RelayerAddress relayerAddress = _activeRelayers[i];
            totalStakeSum += rs.relayerInfo[relayerAddress].stake + ds.totalDelegation[relayerAddress];
            unchecked {
                ++i;
            }
        }

        // Scale the values to fit uint16 and get the CDF
        uint256 sum;
        for (uint256 i; i != length;) {
            RelayerAddress relayerAddress = _activeRelayers[i];
            sum += rs.relayerInfo[relayerAddress].stake + ds.totalDelegation[relayerAddress];
            cdf[i] = ((sum * CDF_PRECISION_MULTIPLIER) / totalStakeSum).toUint16();
            unchecked {
                ++i;
            }
        }

        return cdf;
    }

    function _generateCdfArray_m(RelayerAddress[] memory _activeRelayers) internal view returns (uint16[] memory) {
        RMStorage storage rs = getRMStorage();
        TADStorage storage ds = getTADStorage();

        uint256 length = _activeRelayers.length;
        uint16[] memory cdf = new uint16[](length);
        uint256 totalStakeSum;

        for (uint256 i; i != length;) {
            RelayerAddress relayerAddress = _activeRelayers[i];
            totalStakeSum += rs.relayerInfo[relayerAddress].stake + ds.totalDelegation[relayerAddress];
            unchecked {
                ++i;
            }
        }

        // Scale the values to fit uint16 and get the CDF
        uint256 sum;
        for (uint256 i; i != length;) {
            RelayerAddress relayerAddress = _activeRelayers[i];
            sum += rs.relayerInfo[relayerAddress].stake + ds.totalDelegation[relayerAddress];
            cdf[i] = ((sum * CDF_PRECISION_MULTIPLIER) / totalStakeSum).toUint16();
            unchecked {
                ++i;
            }
        }

        return cdf;
    }

    function _updateCdf_c(RelayerAddress[] calldata _relayerAddresses) internal {
        uint16[] memory cdf = _generateCdfArray_c(_relayerAddresses);
        bytes32 relayerStateHash = _getRelayerStateHash(cdf.m_hash(), _relayerAddresses.cd_hash());

        emit NewRelayerState(relayerStateHash, RelayerState({cdf: cdf, relayers: _relayerAddresses}));

        getRMStorage().relayerStateVersionManager.setPendingState(relayerStateHash, _windowIndex(block.number));
    }

    function _updateCdf_m(RelayerAddress[] memory _relayerAddresses) internal {
        uint16[] memory cdf = _generateCdfArray_m(_relayerAddresses);
        bytes32 relayerStateHash = _getRelayerStateHash(cdf.m_hash(), _relayerAddresses.m_hash());

        emit NewRelayerState(relayerStateHash, RelayerState({cdf: cdf, relayers: _relayerAddresses}));

        getRMStorage().relayerStateVersionManager.setPendingState(relayerStateHash, _windowIndex(block.number));
    }

    ////////////////////////////// Delegation ////////////////////////
    function _addDelegatorRewards(RelayerAddress _relayer, TokenAddress _token, uint256 _amount) internal {
        if (_amount == 0) {
            return;
        }
        getTADStorage().unclaimedRewards[_relayer][_token] += _amount;
        emit DelegatorRewardsAdded(_relayer, _token, _amount);
    }

    ////////////////////////// Constant Rate Rewards //////////////////////////
    function _protocolRewardRate() internal view returns (uint256) {
        RMStorage storage rs = getRMStorage();
        FixedPointType rate =
            rs.totalStake.fp().div(BOND_TOKEN_DECIMAL_MULTIPLIER).sqrt().mul(rs.baseRewardRatePerMinimumStakePerSec);
        return rate.u256();
    }

    function _getLatestTotalUnpaidProtocolRewards() internal view returns (uint256 updatedTotalUnpaidProtocolRewards) {
        RMStorage storage rs = getRMStorage();

        if (block.timestamp == rs.lastUnpaidRewardUpdatedTimestamp) {
            return rs.totalUnpaidProtocolRewards;
        }

        return rs.totalUnpaidProtocolRewards
            + _protocolRewardRate() * (block.timestamp - rs.lastUnpaidRewardUpdatedTimestamp);
    }

    function _getLatestTotalUnpaidProtocolRewardsAndUpdateUpdatedTimestamp()
        internal
        returns (uint256 updatedTotalUnpaidProtocolRewards)
    {
        uint256 unpaidRewards = _getLatestTotalUnpaidProtocolRewards();
        getRMStorage().lastUnpaidRewardUpdatedTimestamp = block.timestamp;
        return unpaidRewards;
    }

    function _protocolRewardRelayerSharePrice(uint256 _unpaidRewards) internal view returns (FixedPointType) {
        RMStorage storage rs = getRMStorage();

        if (rs.totalProtocolRewardShares == FP_ZERO) {
            return FP_ONE;
        }
        return (rs.totalStake + _unpaidRewards).fp() / rs.totalProtocolRewardShares;
    }

    function _protocolRewardsEarnedByRelayer(RelayerAddress _relayer, uint256 _unpaidRewards)
        internal
        view
        returns (uint256)
    {
        RMStorage storage rs = getRMStorage();
        uint256 totalValue =
            (rs.relayerInfo[_relayer].rewardShares * _protocolRewardRelayerSharePrice(_unpaidRewards)).u256();

        unchecked {
            uint256 rewards =
                totalValue >= rs.relayerInfo[_relayer].stake ? totalValue - rs.relayerInfo[_relayer].stake : 0;
            return rewards;
        }
    }

    function _splitRewards(uint256 _totalRewards, uint256 _delegatorRewardSharePercentage)
        internal
        pure
        returns (uint256, uint256)
    {
        uint256 delegatorRewards = (_totalRewards * _delegatorRewardSharePercentage) / (100 * PERCENTAGE_MULTIPLIER);
        return (_totalRewards - delegatorRewards, delegatorRewards);
    }

    function _getPendingProtocolRewardsData(RelayerAddress _relayer, uint256 _unpaidRewards)
        internal
        view
        returns (uint256 relayerRewards, uint256 delegatorRewards, FixedPointType sharesToBurn)
    {
        uint256 rewards = _protocolRewardsEarnedByRelayer(_relayer, _unpaidRewards);
        if (rewards == 0) {
            return (0, 0, FP_ZERO);
        }

        sharesToBurn = rewards.fp() / _protocolRewardRelayerSharePrice(_unpaidRewards);

        (relayerRewards, delegatorRewards) =
            _splitRewards(rewards, getRMStorage().relayerInfo[_relayer].delegatorPoolPremiumShare);
    }

    ////////////////////////////// Misc //////////////////////////////
    function _transfer(TokenAddress _token, address _to, uint256 _amount) internal {
        if (_token == NATIVE_TOKEN) {
            payable(_to).sendValue(_amount);
        } else {
            IERC20(TokenAddress.unwrap(_token)).safeTransfer(_to, _amount);
        }
    }
}
