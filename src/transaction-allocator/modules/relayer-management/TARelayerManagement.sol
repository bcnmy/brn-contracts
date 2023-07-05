// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import {SafeERC20, IERC20} from "openzeppelin-contracts/token/ERC20/utils/SafeERC20.sol";

import {RelayerAddress, RelayerAccountAddress, RelayerStatus, TokenAddress} from "ta-common/TATypes.sol";
import {ITARelayerManagement} from "./interfaces/ITARelayerManagement.sol";
import {TARelayerManagementGetters} from "./TARelayerManagementGetters.sol";
import {TATransactionAllocationStorage} from "ta-transaction-allocation/TATransactionAllocationStorage.sol";
import {VersionManager} from "src/library/VersionManager.sol";
import {U256ArrayHelper} from "src/library/arrays/U256ArrayHelper.sol";
import {RAArrayHelper} from "src/library/arrays/RAArrayHelper.sol";
import {RelayerStateManager} from "ta-common/RelayerStateManager.sol";
import {
    Uint256WrapperHelper, FixedPointTypeHelper, FixedPointType, FP_ZERO
} from "src/library/FixedPointArithmetic.sol";

/// @title TARelayerManagement
/// @dev This contract manages the relayers and their state.
///
/// The relayer state transition diagram
///
///                                                                  ┌─────────────────────────────┐
///                                                                  │                             │
///                                                                  │                             │
///                                               Register           │                             │           Withdraw
///                              ┌───────────────────────────────────┤       Uninitialized         ◄─────────────────────────────────┐
///                              │                                   │                             │                                 │
///                              │                                   │                             │                                 │
///                              │                                   │                             │                                 │
///                              │                                   └──────────────▲──────────────┘                                 │
///                              │                                                  │                                                │
///                              │                                                  │                                                │
///                              │                                                  │                                                │
///                              │                                                  │                                                │
///                              │                                                  │                                                │
///                              │                                                  │                                                │       ┌───────────────────►┐
///                              │                                                  │                                                │       │                    │
///                              │                                                  │                                                │       │                    │
///                              │                                                  │                                                │       │                    │
///                              │                                                  │                                                │       │                    │
///                              │                                                  │                                                │       │                    │
///                              │                                                  │ Unjail and Exit                                │       │                    │
///                              │                                                  │                                                │       │                    │
///                              │                                                  │                                                │       │                    │
///                ┌─────────────▼───────────────┐                                  │                                 ┌──────────────┴───────┴──────┐             │
///                │                             │                                  │                                 │                             │             │
///                │                             │                                  │                                 │                             │             │
///                │                             │        Unregister                │                                 │                             │             │
///    ┌───────────►           Active            ├──────────────────────────────────┼────────────────────────────────►│           Exiting           │◄────────────┘
///    │           │                             │                                  │                                 │                             │            Penalisation
///    │           │                             │                                  │                                 │                             │
///    │           │                             │                                  │                                 │                             │
///    │           └─────────────┬──┬──────▲─────┘                                  │                                 └──────────────┬──────────────┘
///    │                         │  │      │                                        │                                                │
///    │                         │  │      │                                        │                                                │
///    │                         │  │      │                                        │                                                │
///    │                         │  │      │                                        │                                                │
///    │                         │  │      │                                        │                                                │
///    │                         │  │      │                                        │                                                │
///    │                         │  │      │                                        │                                                │
///    │                         │  │      │                                        │                                                │
///     ◄────────────────────────┘  │      │Unjail and Re-enter                     │                                                │
/// Penalisation                    │      │                                        │                                                │
///                                 │      │                                        │                                                │
///                                 │      │                                        │                                                │
///                                 │      │                                        │                                                │
///                                 │      │                                        │                                                │
///                                 │      │                                        │                                                │
///                                 │      │                                        │                                                │
///                                 │      │                                        │                                                │
///                                 │      └─────────────────────────┬──────────────┴──────────────┐                                 │
///                                 │                                │                             │                                 │
///                                 │                                │                             │                                 │
///                                 │                                │                             │                                 │
///                                 └───────────────────────────────►│           Jailed            │◄────────────────────────────────┘
///                                        Penalisation              │                             │                  Penalisation
///                                                                  │                             │
///                                                                  │                             │
///                                                                  └─────────────────────────────┘
///                                                                                                                                         Made with https://asciiflow.com/#/
///
contract TARelayerManagement is ITARelayerManagement, TATransactionAllocationStorage, TARelayerManagementGetters {
    using SafeERC20 for IERC20;
    using Uint256WrapperHelper for uint256;
    using FixedPointTypeHelper for FixedPointType;
    using VersionManager for VersionManager.VersionManagerState;
    using U256ArrayHelper for uint256[];
    using RAArrayHelper for RelayerAddress[];
    using RelayerStateManager for RelayerStateManager.RelayerState;

    ////////////////////////// Relayer Registration //////////////////////////

    /// @inheritdoc ITARelayerManagement
    function register(
        RelayerStateManager.RelayerState calldata _latestState,
        uint256 _stake,
        RelayerAccountAddress[] calldata _accounts,
        string calldata _endpoint,
        uint256 _delegatorPoolPremiumShare
    ) external override noSelfCall {
        _verifyExternalStateForRelayerStateUpdation(_latestState);
        getRMStorage().totalUnpaidProtocolRewards = _getLatestTotalUnpaidProtocolRewardsAndUpdateUpdatedTimestamp();

        // Register Relayer
        RelayerAddress relayerAddress = RelayerAddress.wrap(msg.sender);
        _register(relayerAddress, _stake, _accounts, _endpoint, _delegatorPoolPremiumShare);

        // Queue Update for Active Relayer List
        bytes32 newRelayerStateHash = _latestState.addNewRelayer(relayerAddress, _stake).hash();
        _updateLatestRelayerState(newRelayerStateHash);
        emit RelayerRegistered(relayerAddress, _endpoint, _accounts, _stake, _delegatorPoolPremiumShare);
    }

    /// @inheritdoc ITARelayerManagement
    function registerFoundationRelayer(
        RelayerAddress _foundationRelayerAddress,
        uint256 _stake,
        RelayerAccountAddress[] calldata _accounts,
        string calldata _endpoint,
        uint256 _delegatorPoolPremiumShare
    ) external override {
        RMStorage storage rms = getRMStorage();

        if (rms.relayerCount != 0) {
            revert FoundationRelayerAlreadyRegistered();
        }

        _register(_foundationRelayerAddress, _stake, _accounts, _endpoint, _delegatorPoolPremiumShare);

        // Set Initial Relayer State
        RelayerStateManager.RelayerState memory initialState =
            RelayerStateManager.RelayerState({cdf: new uint256[](1), relayers: new RelayerAddress[](1)});
        initialState.cdf[0] = _stake;
        initialState.relayers[0] = _foundationRelayerAddress;
        rms.relayerStateVersionManager.initialize(initialState.hash());
    }

    /// @notice Updates teh state for registering a relayer
    /// @param _relayerAddress The address of the relayer to register.
    /// @param _stake The amount of tokens to stake in the bond token (bico).
    /// @param _accounts The accounts to register for the relayer.
    /// @param _endpoint The rpc endpoint of the relayer.
    /// @param _delegatorPoolPremiumShare The percentage of the delegator pool rewards to be shared with the relayer.
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
            revert RelayerIsNotActive(_relayerAddress);
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

    /// @inheritdoc ITARelayerManagement
    function unregister(RelayerStateManager.RelayerState calldata _latestState, uint256 _relayerIndex)
        external
        override
        noSelfCall
        onlyActiveRelayer(RelayerAddress.wrap(msg.sender))
    {
        _verifyExternalStateForRelayerStateUpdation(_latestState);

        if (_latestState.cdf.length == 1) {
            revert CannotUnregisterLastRelayer();
        }

        // Verify relayer index
        RelayerAddress relayerAddress = RelayerAddress.wrap(msg.sender);
        if (_latestState.relayers[_relayerIndex] != relayerAddress) {
            revert RelayerIsNotActive(relayerAddress);
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
        bytes32 newRelayerStateHash = _latestState.removeRelayer(_relayerIndex).hash();
        _updateLatestRelayerState(newRelayerStateHash);

        // Set withdrawal Info
        node.status = RelayerStatus.Exiting;
        node.minExitTimestamp = block.timestamp + rms.withdrawDelayInSec;

        // Set Global Counters
        --rms.relayerCount;
        rms.totalStake -= node.stake;
        rms.totalProtocolRewardShares = rms.totalProtocolRewardShares - nodeRewardShares;

        emit RelayerUnRegistered(relayerAddress);
    }

    /// @inheritdoc ITARelayerManagement
    function withdraw(RelayerAccountAddress[] calldata _relayerAccountsToRemove) external override noSelfCall {
        RMStorage storage rms = getRMStorage();

        RelayerAddress relayerAddress = RelayerAddress.wrap(msg.sender);
        RelayerInfo storage node = rms.relayerInfo[relayerAddress];

        if (node.status == RelayerStatus.Active || node.status == RelayerStatus.Uninitialized) {
            revert RelayerNotExiting();
        }

        // Normal Exit
        if (node.status == RelayerStatus.Exiting && node.minExitTimestamp > block.timestamp) {
            revert ExitCooldownNotExpired(node.stake, block.timestamp, node.minExitTimestamp);
        }

        // Exit After Jail
        if (node.status == RelayerStatus.Jailed && node.minExitTimestamp > block.timestamp) {
            revert RelayerJailNotExpired(node.minExitTimestamp);
        }

        delete node.status;

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

    /// @inheritdoc ITARelayerManagement
    function unjailAndReenter(RelayerStateManager.RelayerState calldata _latestState, uint256 _stake)
        external
        override
        noSelfCall
    {
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
        _verifyExternalStateForRelayerStateUpdation(_latestState);
        rms.totalUnpaidProtocolRewards = _getLatestTotalUnpaidProtocolRewardsAndUpdateUpdatedTimestamp();

        // Transfer stake amount
        rms.bondToken.safeTransferFrom(msg.sender, address(this), _stake);

        // Update RelayerInfo
        delete node.minExitTimestamp;
        node.status = RelayerStatus.Active;
        uint256 totalNodeStake = node.stake + _stake;
        node.stake = totalNodeStake;
        node.rewardShares = node.stake.fp() / _protocolRewardRelayerSharePrice(rms.totalUnpaidProtocolRewards);

        // Update Global Counters
        // When jailing, the full stake and reward shares are removed, they need to be added back
        ++rms.relayerCount;
        rms.totalStake += totalNodeStake;
        rms.totalProtocolRewardShares = rms.totalProtocolRewardShares + node.rewardShares;

        // Schedule CDF Update
        bytes32 newRelayerStateHash = _latestState.addNewRelayer(relayerAddress, totalNodeStake).hash();
        _updateLatestRelayerState(newRelayerStateHash);

        emit RelayerUnjailedAndReentered(relayerAddress);
    }

    ////////////////////////// Relayer Configuration //////////////////////////

    /// @inheritdoc ITARelayerManagement
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

    /// @inheritdoc ITARelayerManagement
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

    /// @inheritdoc ITARelayerManagement
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
