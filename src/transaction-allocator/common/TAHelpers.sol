// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import {IERC20} from "openzeppelin-contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "openzeppelin-contracts/token/ERC20/utils/SafeERC20.sol";
import {SafeCast} from "openzeppelin-contracts/utils/math/SafeCast.sol";
import {Address} from "openzeppelin-contracts/utils/Address.sol";

import {ITAHelpers} from "./interfaces/ITAHelpers.sol";
import {TARelayerManagementStorage} from "ta-relayer-management/TARelayerManagementStorage.sol";
import {TADelegationStorage} from "ta-delegation/TADelegationStorage.sol";
import {RAArrayHelper} from "src/library/arrays/RAArrayHelper.sol";
import {U16ArrayHelper} from "src/library/arrays/U16ArrayHelper.sol";
import {
    Uint256WrapperHelper,
    FixedPointTypeHelper,
    FixedPointType,
    FP_ZERO,
    FP_ONE
} from "src/library/FixedPointArithmetic.sol";
import {VersionManager} from "src/library/VersionManager.sol";
import {RelayerAddress, TokenAddress, RelayerState, RelayerStatus} from "./TATypes.sol";
import {
    CDF_PRECISION_MULTIPLIER,
    BOND_TOKEN_DECIMAL_MULTIPLIER,
    NATIVE_TOKEN,
    PERCENTAGE_MULTIPLIER
} from "./TAConstants.sol";

/// @title TAHelpers
/// @dev Common contract inherited by all core modules of the Transaction Allocator. Provides varios helper functions.
abstract contract TAHelpers is TARelayerManagementStorage, TADelegationStorage, ITAHelpers {
    using SafeERC20 for IERC20;
    using SafeCast for uint256;
    using Address for address payable;
    using Uint256WrapperHelper for uint256;
    using FixedPointTypeHelper for FixedPointType;
    using VersionManager for VersionManager.VersionManagerState;
    using U16ArrayHelper for uint16[];
    using RAArrayHelper for RelayerAddress[];

    ////////////////////////////// Verification Helpers //////////////////////////////
    modifier onlyActiveRelayer(RelayerAddress _relayer) {
        if (!_isActiveRelayer(_relayer)) {
            revert RelayerIsNotActive(_relayer);
        }
        _;
    }

    /// @dev Returns true if the relayer is active in the pending/latest state.
    ///      A relayer which has requested unregistration or jailing could be active in the current state, but not in the pending/latest state.
    /// @param _relayer The relayer address
    /// @return true if the relayer is active
    function _isActiveRelayer(RelayerAddress _relayer) internal view returns (bool) {
        return getRMStorage().relayerInfo[_relayer].status == RelayerStatus.Active;
    }

    /// @dev Hash function used to generate the hash of the relayer state.
    /// @param _cdfHash The hash of the CDF array
    /// @param _relayerArrayHash The hash of the relayer array
    /// @return The hash of the relayer state
    function _getRelayerStateHash(bytes32 _cdfHash, bytes32 _relayerArrayHash) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked(_cdfHash, _relayerArrayHash));
    }

    /// @dev Verifies that the passed relayer state corresponds to the latest/pending state.
    ///      Updates to the Relayer State must take into account already queued updates, hence the verification against the latest state.
    ///      Reverts if the state verification fails.
    /// @param _cdfHash The hash of the CDF array
    /// @param _relayersHash The hash of the relayer array
    function _verifyExternalStateForRelayerStateUpdation(bytes32 _cdfHash, bytes32 _relayersHash) internal view {
        if (
            !getRMStorage().relayerStateVersionManager.verifyHashAgainstLatestState(
                _getRelayerStateHash(_cdfHash, _relayersHash)
            )
        ) {
            revert InvalidLatestRelayerState();
        }
    }

    /// @dev Verifies that the passed relayer state corresponds to the currently active state.
    ///      Reverts if the state verification fails.
    /// @param _cdfHash The hash of the CDF array
    /// @param _relayersHash The hash of the relayer array
    function _verifyExternalStateForTransactionAllocation(bytes32 _cdfHash, bytes32 _relayersHash, uint256 _blockNumber)
        internal
        view
    {
        // The unit of time for the relayer state is the window index.
        uint256 windowIndex = _windowIndex(_blockNumber);

        if (
            !getRMStorage().relayerStateVersionManager.verifyHashAgainstActiveState(
                _getRelayerStateHash(_cdfHash, _relayersHash), windowIndex
            )
        ) {
            revert InvalidActiveRelayerState();
        }
    }

    ////////////////////////////// Relayer Selection //////////////////////////////

    /// @dev A non-decreasing numerical identifier for a given window. A window is a contigous set of blocks of length blocksPerWindow.
    /// @param _blockNumber The block number for which the window index is to be calculated
    /// @return The index of window in which _blockNumber falls
    function _windowIndex(uint256 _blockNumber) internal view returns (uint256) {
        return _blockNumber / getRMStorage().blocksPerWindow;
    }

    /// @dev Given a block number, returns the window index a future window in which any relayer state updates should be applied.
    /// @param _blockNumber The block number for which the next update window index is to be calculated
    /// @return The index of the window in which the relayer state updates should be applied
    function _nextWindowForUpdate(uint256 _blockNumber) internal view returns (uint256) {
        return _windowIndex(_blockNumber) + getRMStorage().relayerStateUpdateDelayInWindows;
    }

    ////////////////////////////// Relayer State //////////////////////////////

    /// @dev For each relayer in the passed array, return the an array representing the cumulative sum of each relayer's stake and delegation.
    ///      The array is scaled to fit uint16.
    /// @param _relayers List of relayers against which the CDF is to be generated
    /// @return The CDF array
    function _generateCdfArray_c(RelayerAddress[] calldata _relayers) internal view returns (uint16[] memory) {
        RMStorage storage rs = getRMStorage();
        TADStorage storage ds = getTADStorage();

        uint256 length = _relayers.length;
        uint16[] memory cdf = new uint16[](length);
        uint256 totalStakeSum;

        // Calculate the total stake sum
        for (uint256 i; i != length;) {
            RelayerAddress relayerAddress = _relayers[i];
            totalStakeSum += rs.relayerInfo[relayerAddress].stake + ds.totalDelegation[relayerAddress];
            unchecked {
                ++i;
            }
        }

        // Scale the values to fit uint16 and get the CDF
        uint256 sum;
        for (uint256 i; i != length;) {
            RelayerAddress relayerAddress = _relayers[i];
            sum += rs.relayerInfo[relayerAddress].stake + ds.totalDelegation[relayerAddress];
            cdf[i] = ((sum * CDF_PRECISION_MULTIPLIER) / totalStakeSum).toUint16();
            unchecked {
                ++i;
            }
        }

        return cdf;
    }

    /// @dev For each relayer in the passed array, return the an array representing the cumulative sum of each relayer's stake and delegation.
    ///      The array is scaled to fit uint16.
    /// @param _relayers List of relayers against which the CDF is to be generated
    /// @return The CDF array
    function _generateCdfArray_m(RelayerAddress[] memory _relayers) internal view returns (uint16[] memory) {
        RMStorage storage rs = getRMStorage();
        TADStorage storage ds = getTADStorage();

        uint256 length = _relayers.length;
        uint16[] memory cdf = new uint16[](length);
        uint256 totalStakeSum;

        // Scale the values to fit uint16 and get the CDF
        for (uint256 i; i != length;) {
            RelayerAddress relayerAddress = _relayers[i];
            totalStakeSum += rs.relayerInfo[relayerAddress].stake + ds.totalDelegation[relayerAddress];
            unchecked {
                ++i;
            }
        }

        // Scale the values to fit uint16 and get the CDF
        uint256 sum;
        for (uint256 i; i != length;) {
            RelayerAddress relayerAddress = _relayers[i];
            sum += rs.relayerInfo[relayerAddress].stake + ds.totalDelegation[relayerAddress];
            cdf[i] = ((sum * CDF_PRECISION_MULTIPLIER) / totalStakeSum).toUint16();
            unchecked {
                ++i;
            }
        }

        return cdf;
    }

    /// @dev Given a list of relayers, compute the new CDF and Relayer State, then set the state as the new pending/latest state.
    ///      The new relayer state is not scheduled for activation.
    /// @param _relayerAddresses List of relayers against which the CDF is to be generate
    function _updateCdf_c(RelayerAddress[] calldata _relayerAddresses) internal {
        uint16[] memory cdf = _generateCdfArray_c(_relayerAddresses);
        bytes32 relayerStateHash = _getRelayerStateHash(cdf.m_hash(), _relayerAddresses.cd_hash());

        emit NewRelayerState(relayerStateHash);

        getRMStorage().relayerStateVersionManager.setLatestState(relayerStateHash, _windowIndex(block.number));
    }

    /// @dev Given a list of relayers, compute the new CDF and Relayer State, then set the state as the new pending/latest state.
    ///      The new relayer state is not scheduled for activation.
    /// @param _relayerAddresses List of relayers against which the CDF is to be generate
    function _updateCdf_m(RelayerAddress[] memory _relayerAddresses) internal {
        uint16[] memory cdf = _generateCdfArray_m(_relayerAddresses);
        bytes32 relayerStateHash = _getRelayerStateHash(cdf.m_hash(), _relayerAddresses.m_hash());

        emit NewRelayerState(relayerStateHash);

        getRMStorage().relayerStateVersionManager.setLatestState(relayerStateHash, _windowIndex(block.number));
    }

    ////////////////////////////// Delegation ////////////////////////

    /// @dev Records the rewards to be distributed to delegators of the given relayer
    /// @param _relayer The relayer whose delegators are to be rewarded
    /// @param _token The token in which the rewards are to be distributed
    /// @param _amount The amount of rewards to be distributed
    function _addDelegatorRewards(RelayerAddress _relayer, TokenAddress _token, uint256 _amount) internal {
        if (_amount == 0) {
            return;
        }
        getTADStorage().unclaimedRewards[_relayer][_token] += _amount;
        emit DelegatorRewardsAdded(_relayer, _token, _amount);
    }

    ////////////////////////// Constant Rate Rewards //////////////////////////

    /// @dev The BRN generates "protocol rewards" in the form of bond tokens (BICO) at a rate R.
    ///      The base reward factor (B) is a constant that is set by the BRN.
    ///      An increment (b) is defined as the Minimum amount of stake required by relayers.
    ///      Assuming S is the total stake, the reward rate is given by:
    ///         Base Reward Per Increment/s (I) = B * b / sqrt(S)
    ///         Total Reward Rate/s (R) = I * S / b = B * sqrt(S)
    ///
    /// @return The current reward generation rate R in bond Token (BICO) wei/sec
    function _protocolRewardRate() internal view returns (uint256) {
        RMStorage storage rs = getRMStorage();
        FixedPointType rate =
            rs.totalStake.fp().div(BOND_TOKEN_DECIMAL_MULTIPLIER).sqrt().mul(rs.baseRewardRatePerMinimumStakePerSec);
        return rate.u256();
    }

    /// @dev Returns the total amount of protocol rewards generated by the BRN since the last update.
    /// @return updatedTotalUnpaidProtocolRewards
    function _getLatestTotalUnpaidProtocolRewards() internal view returns (uint256 updatedTotalUnpaidProtocolRewards) {
        RMStorage storage rs = getRMStorage();

        if (block.timestamp == rs.lastUnpaidRewardUpdatedTimestamp) {
            return rs.totalUnpaidProtocolRewards;
        }

        return rs.totalUnpaidProtocolRewards
            + _protocolRewardRate() * (block.timestamp - rs.lastUnpaidRewardUpdatedTimestamp);
    }

    /// @dev Returns the total amount of protocol rewards generated by the BRN since the last update and updates the last update timestamp in storage.
    ///      The unpaidRewards are not updated in storage yet, it is expected that the calling function would perform the update,
    ///      after performing any other necessary operations and deductions from this amount.
    /// @return updatedTotalUnpaidProtocolRewards
    function _getLatestTotalUnpaidProtocolRewardsAndUpdateUpdatedTimestamp()
        internal
        returns (uint256 updatedTotalUnpaidProtocolRewards)
    {
        uint256 unpaidRewards = _getLatestTotalUnpaidProtocolRewards();
        getRMStorage().lastUnpaidRewardUpdatedTimestamp = block.timestamp;
        return unpaidRewards;
    }

    /// @dev Protocol rewards are distributed to the relayers through a shares mechanism.
    ///      During registration, a relayer is assigned a number of shares proportional to the amount of stake they have,
    ///      based on a non-decreasing share price.
    ///      The share price increases as more protocol rewards are generated.
    /// @param _unpaidRewards The total amount of protocol rewards that are generated but not distributed to the relayers.
    /// @return The share price of the protocol rewards.
    function _protocolRewardRelayerSharePrice(uint256 _unpaidRewards) internal view returns (FixedPointType) {
        RMStorage storage rs = getRMStorage();

        if (rs.totalProtocolRewardShares == FP_ZERO) {
            return FP_ONE;
        }
        return (rs.totalStake + _unpaidRewards).fp() / rs.totalProtocolRewardShares;
    }

    /// @dev Returns the amount of unclaimed protocol rewards earned by the given relayer.
    /// @param _relayer The relayer whose unclaimed protocol rewards are to be returned.
    /// @param _unpaidRewards The total amount of protocol rewards that are generated but not distributed to the relayers.
    /// @return The amount of unclaimed protocol rewards earned by the given relayer.
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

    /// @dev Utility function to calculate the protocol reward split between the relayer and the delegators.
    /// @param _totalRewards The total amount of protocol rewards earned by the relayer to be split.
    /// @param _delegatorRewardSharePercentage The percentage of the total rewards to be given to the delegators.
    /// @return The amount of rewards to be given to the relayer
    /// @return The amount of rewards to be given to the delegators
    function _calculateProtocolRewardSplit(uint256 _totalRewards, uint256 _delegatorRewardSharePercentage)
        internal
        pure
        returns (uint256, uint256)
    {
        uint256 delegatorRewards = (_totalRewards * _delegatorRewardSharePercentage) / (100 * PERCENTAGE_MULTIPLIER);
        return (_totalRewards - delegatorRewards, delegatorRewards);
    }

    /// @dev Calculates the amount of unclaimed protocol rewards earned by the given relayer, then calculates the split b/w the
    ///      relayer and the delegators, and finally calculates the amount of shares to be burned to claim these rewards.
    /// @param _relayer The relayer whose unclaimed protocol rewards are to be returned.
    /// @param _unpaidRewards The total amount of protocol rewards that are generated but not distributed to the relayers.
    /// @return relayerRewards The amount of rewards to be given to the relayer
    /// @return delegatorRewards The amount of rewards to be given to the delegators
    /// @return sharesToBurn The amount of shares to be burned to claim these rewards.
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
            _calculateProtocolRewardSplit(rewards, getRMStorage().relayerInfo[_relayer].delegatorPoolPremiumShare);
    }

    ////////////////////////////// Misc //////////////////////////////

    /// @dev Utility function to transfer tokens from TransactionAllocator to the given address.
    /// @param _token The token to transfer.
    /// @param _to The address to transfer the tokens to.
    /// @param _amount The amount of tokens to transfer.
    function _transfer(TokenAddress _token, address _to, uint256 _amount) internal {
        if (_token == NATIVE_TOKEN) {
            payable(_to).sendValue(_amount);
        } else {
            IERC20(TokenAddress.unwrap(_token)).safeTransfer(_to, _amount);
        }
    }
}
