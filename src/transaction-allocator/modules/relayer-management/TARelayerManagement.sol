// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import "openzeppelin-contracts/token/ERC20/utils/SafeERC20.sol";

import {CDF_PRECISION_MULTIPLIER} from "ta-common/TAConstants.sol";
import "./interfaces/ITARelayerManagement.sol";
import "./TARelayerManagementStorage.sol";
import "ta-transaction-allocation/TATransactionAllocationStorage.sol";
import "src/library/VersionManager.sol";
import "src/library/arrays/U32ArrayHelper.sol";
import {TARelayerManagementGetters} from "./TARelayerManagementGetters.sol";
import {U16ArrayHelper} from "src/library/arrays/U16ArrayHelper.sol";
import {RAArrayHelper} from "src/library/arrays/RAArrayHelper.sol";

contract TARelayerManagement is ITARelayerManagement, TATransactionAllocationStorage, TARelayerManagementGetters {
    using SafeERC20 for IERC20;
    using Uint256WrapperHelper for uint256;
    using FixedPointTypeHelper for FixedPointType;
    using VersionManager for VersionManager.VersionManagerState;
    using U16ArrayHelper for uint16[];
    using U32ArrayHelper for uint32[];
    using RAArrayHelper for RelayerAddress[];

    ////////////////////////// Relayer Registration //////////////////////////
    function register(
        RelayerState calldata _latestState,
        uint256 _stake,
        RelayerAccountAddress[] calldata _accounts,
        string calldata _endpoint,
        uint256 _delegatorPoolPremiumShare
    ) external override noSelfCall {
        _verifyExternalStateForRelayerStateUpdation(_latestState.cdf.cd_hash(), _latestState.relayers.cd_hash());
        getRMStorage().totalUnpaidProtocolRewards = _getLatestTotalUnpaidProtocolRewardsAndUpdateUpdatedTimestamp();

        // Register Relayer
        RelayerAddress relayerAddress = RelayerAddress.wrap(msg.sender);
        _register(relayerAddress, _stake, _accounts, _endpoint, _delegatorPoolPremiumShare);

        // Queue Update for Active Relayer List
        RelayerAddress[] memory newActiveRelayers = _latestState.relayers.cd_append(relayerAddress);
        _updateCdf_m(newActiveRelayers);
        emit RelayerRegistered(relayerAddress, _endpoint, _accounts, _stake, _delegatorPoolPremiumShare);
    }

    function registerFoundationRelayer(
        RelayerAddress _foundationRelayerAddress,
        uint256 _stake,
        RelayerAccountAddress[] calldata _accounts,
        string calldata _endpoint,
        uint256 _delegatorPoolPremiumShare
    ) external override {
        RMStorage storage rms = getRMStorage();

        // TODO: Check if this is the right way to protect this function
        if (rms.relayerCount != 0) {
            revert FoundationRelayerAlreadyRegistered();
        }

        _register(_foundationRelayerAddress, _stake, _accounts, _endpoint, _delegatorPoolPremiumShare);

        // Set Initial Relayer State
        uint16[] memory cdf = new uint16[](1);
        cdf[0] = CDF_PRECISION_MULTIPLIER;
        RelayerAddress[] memory relayers = new RelayerAddress[](1);
        relayers[0] = _foundationRelayerAddress;
        rms.relayerStateVersionManager.initialize(keccak256(abi.encodePacked(cdf.m_hash(), relayers.m_hash())));
    }

    function _register(
        RelayerAddress _relayerAddress,
        uint256 _stake,
        RelayerAccountAddress[] calldata _accounts,
        string calldata _endpoint,
        uint256 _delegatorPoolPremiumShare
    ) internal {
        RMStorage storage rms = getRMStorage();
        RelayerInfo storage node = rms.relayerInfo[_relayerAddress];

        if (_relayerAddress == RelayerAddress.wrap(address(0))) {
            revert InvalidRelayer(_relayerAddress);
        }
        if (_accounts.length == 0) {
            revert NoAccountsProvided();
        }
        if (_stake < rms.minimumStakeAmount) {
            revert InsufficientStake(_stake, rms.minimumStakeAmount);
        }
        if (node.status != RelayerStatus.Uninitialized) {
            revert RelayerAlreadyRegistered();
        }

        // Transfer stake amount
        rms.bondToken.safeTransferFrom(RelayerAddress.unwrap(_relayerAddress), address(this), _stake);

        // Store relayer info
        node.stake += _stake;
        node.endpoint = _endpoint;
        node.delegatorPoolPremiumShare = _delegatorPoolPremiumShare;
        node.rewardShares = _stake.fp() / _protocolRewardRelayerSharePrice(rms.totalUnpaidProtocolRewards);
        node.status = RelayerStatus.Active;
        _setRelayerAccountStatus(_relayerAddress, _accounts, true);

        // Update Global Counters
        ++rms.relayerCount;
        rms.totalStake += _stake;
        rms.totalProtocolRewardShares = rms.totalProtocolRewardShares + node.rewardShares;
    }

    /// @notice a relayer un unregister, which removes it from the relayer list and a delay for withdrawal is imposed on funds
    function unregister(RelayerState calldata _latestState, uint256 _relayerIndex)
        external
        override
        noSelfCall
        onlyActiveRelayer(RelayerAddress.wrap(msg.sender))
    {
        _verifyExternalStateForRelayerStateUpdation(_latestState.cdf.cd_hash(), _latestState.relayers.cd_hash());

        if (_latestState.cdf.length == 1) {
            revert CannotUnregisterLastRelayer();
        }

        // Verify relayer index
        RelayerAddress relayerAddress = RelayerAddress.wrap(msg.sender);
        if (_latestState.relayers[_relayerIndex] != relayerAddress) {
            revert InvalidRelayer(relayerAddress);
        }

        RMStorage storage rms = getRMStorage();
        RelayerInfo storage node = rms.relayerInfo[relayerAddress];

        /* Transfer any pending rewards to the relayers and delegators */
        FixedPointType nodeRewardShares = node.rewardShares;
        {
            uint256 updatedTotalUnpaidProtocolRewards = _getLatestTotalUnpaidProtocolRewardsAndUpdateUpdatedTimestamp();

            // Calculate Rewards
            (uint256 relayerReward, uint256 delegatorRewards,) =
                _getPendingProtocolRewardsData(relayerAddress, updatedTotalUnpaidProtocolRewards);

            // Process Delegator Rewards
            _addDelegatorRewards(relayerAddress, TokenAddress.wrap(address(rms.bondToken)), delegatorRewards);

            // Process Relayer Rewards
            rms.totalUnpaidProtocolRewards = updatedTotalUnpaidProtocolRewards - relayerReward - delegatorRewards;
            relayerReward += node.unpaidProtocolRewards;
            delete node.unpaidProtocolRewards;
            node.rewardShares = FP_ZERO;

            if (relayerReward > 0) {
                _transfer(TokenAddress.wrap(address(rms.bondToken)), msg.sender, relayerReward);
                emit RelayerProtocolRewardsClaimed(relayerAddress, relayerReward);
            }
        }

        // Update the CDF
        RelayerAddress[] memory newActiveRelayers = _latestState.relayers.cd_remove(_relayerIndex);
        _updateCdf_m(newActiveRelayers);

        // Set withdrawal Info
        node.status = RelayerStatus.Exiting;
        node.minExitTimestamp = block.timestamp + rms.withdrawDelayInSec;

        // Set Global Counters
        --rms.relayerCount;
        rms.totalStake -= node.stake;
        rms.totalProtocolRewardShares = rms.totalProtocolRewardShares - nodeRewardShares;

        emit RelayerUnRegistered(relayerAddress);
    }

    function withdraw(RelayerAccountAddress[] calldata _relayerAccountsToRemove) external override noSelfCall {
        RMStorage storage rms = getRMStorage();

        RelayerAddress relayerAddress = RelayerAddress.wrap(msg.sender);
        RelayerInfo storage node = rms.relayerInfo[relayerAddress];

        if (node.status == RelayerStatus.Active || node.status == RelayerStatus.Uninitialized) {
            revert RelayerNotExiting();
        }

        // Normal Exit
        if (node.status == RelayerStatus.Exiting && (node.minExitTimestamp > block.timestamp)) {
            revert InvalidWithdrawal(node.stake, block.timestamp, node.minExitTimestamp);
        }

        // Exit After Jail
        if (node.status == RelayerStatus.Jailed && (node.minExitTimestamp > block.timestamp)) {
            revert RelayerJailNotExpired(node.minExitTimestamp);
        }

        _deleteRelayerAccountAddresses(relayerAddress, _relayerAccountsToRemove);
        _transfer(TokenAddress.wrap(address(rms.bondToken)), msg.sender, node.stake);
        emit Withdraw(relayerAddress, node.stake);

        delete rms.relayerInfo[relayerAddress];
    }

    function _deleteRelayerAccountAddresses(
        RelayerAddress _relayerAddress,
        RelayerAccountAddress[] calldata _relayerAccountAddresses
    ) internal {
        RelayerInfo storage node = getRMStorage().relayerInfo[_relayerAddress];
        uint256 length = _relayerAccountAddresses.length;
        for (uint256 i; i != length;) {
            delete node.isAccount[_relayerAccountAddresses[i]];
            unchecked {
                ++i;
            }
        }
    }

    function unjailAndReenter(RelayerState calldata _latestState, uint256 _stake) external override noSelfCall {
        RMStorage storage rms = getRMStorage();
        RelayerAddress relayerAddress = RelayerAddress.wrap(msg.sender);
        RelayerInfo storage node = rms.relayerInfo[relayerAddress];

        if (node.status != RelayerStatus.Jailed) {
            revert RelayerNotJailed();
        }
        if (node.minExitTimestamp > block.timestamp) {
            revert RelayerJailNotExpired(node.minExitTimestamp);
        }
        if (node.stake + _stake < rms.minimumStakeAmount) {
            revert InsufficientStake(node.stake + _stake, rms.minimumStakeAmount);
        }
        _verifyExternalStateForRelayerStateUpdation(_latestState.cdf.cd_hash(), _latestState.relayers.cd_hash());
        rms.totalUnpaidProtocolRewards = _getLatestTotalUnpaidProtocolRewardsAndUpdateUpdatedTimestamp();

        // Transfer stake amount
        rms.bondToken.safeTransferFrom(msg.sender, address(this), _stake);

        // Update RelayerInfo
        delete node.minExitTimestamp;
        node.status = RelayerStatus.Active;
        node.stake += _stake;
        node.rewardShares = node.stake.fp() / _protocolRewardRelayerSharePrice(rms.totalUnpaidProtocolRewards);

        // Update Global Counters
        // When jailing, the full stake and reward shares are removed, they need to be added back
        ++rms.relayerCount;
        rms.totalStake += node.stake;
        rms.totalProtocolRewardShares = rms.totalProtocolRewardShares + node.rewardShares;

        // Schedule CDF Update
        RelayerAddress[] memory newActiveRelayers = _latestState.relayers.cd_append(relayerAddress);
        _updateCdf_m(newActiveRelayers);

        emit RelayerUnjailedAndReentered(relayerAddress);
    }

    ////////////////////////// Relayer Configuration //////////////////////////
    function setRelayerAccountsStatus(RelayerAccountAddress[] calldata _accounts, bool[] calldata _status)
        external
        override
        noSelfCall
        onlyActiveRelayer(RelayerAddress.wrap(msg.sender))
    {
        RelayerAddress relayerAddress = RelayerAddress.wrap(msg.sender);
        _setRelayerAccountStatus(relayerAddress, _accounts, _status);
        emit RelayerAccountsUpdated(relayerAddress, _accounts);
    }

    function _setRelayerAccountStatus(
        RelayerAddress _relayerAddress,
        RelayerAccountAddress[] memory _accounts,
        bool[] calldata _status
    ) internal {
        RelayerInfo storage node = getRMStorage().relayerInfo[_relayerAddress];

        if (_accounts.length != _status.length) {
            revert ParameterLengthMismatch();
        }

        // Add new accounts
        uint256 length = _accounts.length;
        for (uint256 i; i != length;) {
            node.isAccount[_accounts[i]] = _status[i];
            unchecked {
                ++i;
            }
        }
    }

    function _setRelayerAccountStatus(
        RelayerAddress _relayerAddress,
        RelayerAccountAddress[] memory _accounts,
        bool _status
    ) internal {
        RelayerInfo storage node = getRMStorage().relayerInfo[_relayerAddress];
        uint256 length = _accounts.length;
        for (uint256 i; i != length;) {
            node.isAccount[_accounts[i]] = _status;
            unchecked {
                ++i;
            }
        }
    }

    ////////////////////////// Protocol Rewards //////////////////////////
    function claimProtocolReward() external override noSelfCall onlyActiveRelayer(RelayerAddress.wrap(msg.sender)) {
        uint256 updatedTotalUnpaidProtocolRewards = _getLatestTotalUnpaidProtocolRewardsAndUpdateUpdatedTimestamp();

        RelayerAddress relayerAddress = RelayerAddress.wrap(msg.sender);

        // Calculate Rewards
        (uint256 relayerReward, uint256 delegatorRewards, FixedPointType sharesToBurn) =
            _getPendingProtocolRewardsData(relayerAddress, updatedTotalUnpaidProtocolRewards);

        // Process Delegator Rewards
        RMStorage storage rs = getRMStorage();
        _addDelegatorRewards(relayerAddress, TokenAddress.wrap(address(rs.bondToken)), delegatorRewards);

        // Process Relayer Rewards
        rs.totalUnpaidProtocolRewards = updatedTotalUnpaidProtocolRewards - relayerReward - delegatorRewards;
        rs.totalProtocolRewardShares = rs.totalProtocolRewardShares - sharesToBurn;
        rs.relayerInfo[relayerAddress].rewardShares = rs.relayerInfo[relayerAddress].rewardShares - sharesToBurn;
        relayerReward += rs.relayerInfo[relayerAddress].unpaidProtocolRewards;
        rs.relayerInfo[relayerAddress].unpaidProtocolRewards = 0;

        if (relayerReward > 0) {
            _transfer(TokenAddress.wrap(address(rs.bondToken)), msg.sender, relayerReward);
            emit RelayerProtocolRewardsClaimed(relayerAddress, relayerReward);
        }
    }

    function relayerClaimableProtocolRewards(RelayerAddress _relayerAddress)
        external
        view
        override
        noSelfCall
        returns (uint256)
    {
        RMStorage storage rs = getRMStorage();
        RelayerInfo storage node = rs.relayerInfo[_relayerAddress];
        if (node.status == RelayerStatus.Jailed) {
            return 0;
        }

        uint256 updatedTotalUnpaidProtocolRewards = _getLatestTotalUnpaidProtocolRewards();

        (uint256 relayerReward,,) = _getPendingProtocolRewardsData(_relayerAddress, updatedTotalUnpaidProtocolRewards);

        return relayerReward + node.unpaidProtocolRewards;
    }
}
