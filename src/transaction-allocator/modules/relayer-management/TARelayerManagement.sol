// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import "openzeppelin-contracts/token/ERC20/utils/SafeERC20.sol";

import "./interfaces/ITARelayerManagement.sol";
import "./TARelayerManagementStorage.sol";
import "ta-delegation/interfaces/ITADelegation.sol";
import "ta-transaction-allocation/TATransactionAllocationStorage.sol";
import "ta-common/TAHelpers.sol";
import "ta-common/TAConstants.sol";
import "src/library/FixedPointArithmetic.sol";
import "src/library/VersionManager.sol";

contract TARelayerManagement is
    ITARelayerManagement,
    TARelayerManagementStorage,
    TAHelpers,
    TATransactionAllocationStorage
{
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
    ) external override measureGas("register") {
        _verifyExternalStateForRelayerStateUpdation(_latestState.cdf.cd_hash(), _latestState.relayers.cd_hash());
        _updateProtocolRewards();

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
        node.rewardShares = _stake.fp() / _protocolRewardRelayerSharePrice();
        node.status = RelayerStatus.Active;
        _setRelayerAccountStatus(_relayerAddress, _accounts, true);

        // Update Global Counters
        ++rms.relayerCount;
        rms.totalStake += _stake;
        rms.totalShares = rms.totalShares + node.rewardShares;
    }

    /// @notice a relayer un unregister, which removes it from the relayer list and a delay for withdrawal is imposed on funds
    function unregister(RelayerState calldata _latestState, uint256 _relayerIndex)
        external
        override
        measureGas("unregister")
        onlyActiveRelayer(RelayerAddress.wrap(msg.sender))
    {
        _verifyExternalStateForRelayerStateUpdation(_latestState.cdf.cd_hash(), _latestState.relayers.cd_hash());
        _updateProtocolRewards();

        if (_latestState.cdf.length == 1) {
            revert CannotUnregisterLastRelayer();
        }

        // Verify relayer index
        RelayerAddress relayerAddress = RelayerAddress.wrap(msg.sender);
        if (_latestState.relayers[_relayerIndex] != relayerAddress) {
            revert InvalidRelayer(relayerAddress);
        }

        // Transfer any pending rewards to the relayers and delegators
        claimProtocolReward();

        RMStorage storage rms = getRMStorage();
        RelayerInfo storage node = rms.relayerInfo[relayerAddress];

        // Update the CDF
        RelayerAddress[] memory newActiveRelayers = _latestState.relayers.cd_remove(_relayerIndex);
        _updateCdf_m(newActiveRelayers);

        // Set withdrawal Info
        node.status = RelayerStatus.Exiting;
        node.minExitTimestamp = block.timestamp + rms.withdrawDelayInSec;

        // Set Global Counters
        --rms.relayerCount;
        rms.totalStake -= node.stake;
        rms.totalShares = rms.totalShares - node.rewardShares;

        emit RelayerUnRegistered(relayerAddress);
    }

    // TODO: Allow relayers to provide a list of relayer account addresses to be deleted, which could result in potential gas refunds
    function withdraw() external override measureGas("withdraw") {
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

        _transfer(TokenAddress.wrap(address(rms.bondToken)), msg.sender, node.stake);
        emit Withdraw(relayerAddress, node.stake);

        delete rms.relayerInfo[relayerAddress];
    }

    function unjailAndReenter(RelayerState calldata _latestState, uint256 _stake)
        external
        override
        measureGas("unjailAndReenter")
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
        _verifyExternalStateForRelayerStateUpdation(_latestState.cdf.cd_hash(), _latestState.relayers.cd_hash());
        _updateProtocolRewards();

        // Transfer stake amount
        rms.bondToken.safeTransferFrom(msg.sender, address(this), _stake);

        // Update RelayerInfo
        delete node.minExitTimestamp;
        node.status = RelayerStatus.Active;
        node.stake += _stake;
        node.rewardShares = node.stake.fp() / _protocolRewardRelayerSharePrice();

        // Update Global Counters
        // When jailing, the full stake and reward shares are removed, they need to be added back
        ++rms.relayerCount;
        rms.totalStake += node.stake;
        rms.totalShares = rms.totalShares + node.rewardShares;

        // Schedule CDF Update
        RelayerAddress[] memory newActiveRelayers = _latestState.relayers.cd_append(relayerAddress);
        _updateCdf_m(newActiveRelayers);

        emit RelayerUnjailedAndReentered(relayerAddress);
    }

    ////////////////////////// Relayer Configuration //////////////////////////
    function setRelayerAccountsStatus(RelayerAccountAddress[] calldata _accounts, bool[] calldata _status)
        external
        override
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
    ) internal measureGas("_setRelayerAccountStatus") {
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
    ) internal measureGas("_setRelayerAccountStatus") {
        RelayerInfo storage node = getRMStorage().relayerInfo[_relayerAddress];
        uint256 length = _accounts.length;
        for (uint256 i; i != length;) {
            node.isAccount[_accounts[i]] = _status;
            unchecked {
                ++i;
            }
        }
    }

    ////////////////////////// Constant Rate Rewards //////////////////////////
    function claimProtocolReward() public override onlyActiveRelayer(RelayerAddress.wrap(msg.sender)) {
        _updateProtocolRewards();

        RelayerAddress relayerAddress = RelayerAddress.wrap(msg.sender);

        // Calculate Rewards
        (uint256 relayerReward, uint256 delegatorRewards) = _burnRewardSharesForRelayerAndGetRewards(relayerAddress);

        // Process Delegator Rewards
        RMStorage storage rs = getRMStorage();
        _addDelegatorRewards(relayerAddress, TokenAddress.wrap(address(rs.bondToken)), delegatorRewards);

        // Process Relayer Rewards
        relayerReward += rs.relayerInfo[relayerAddress].unpaidProtocolRewards;
        rs.relayerInfo[relayerAddress].unpaidProtocolRewards = 0;
        if (relayerReward > 0) {
            _transfer(TokenAddress.wrap(address(rs.bondToken)), msg.sender, relayerReward);
            emit RelayerProtocolRewardsClaimed(relayerAddress, relayerReward);
        }
    }

    ////////////////////////// Getters //////////////////////////
    function relayerCount() external view override returns (uint256) {
        return getRMStorage().relayerCount;
    }

    function totalStake() external view override returns (uint256) {
        return getRMStorage().totalStake;
    }

    function relayerInfo(RelayerAddress _relayerAddress) external view override returns (RelayerInfoView memory) {
        RMStorage storage rms = getRMStorage();
        RelayerInfo storage node = rms.relayerInfo[_relayerAddress];

        return RelayerInfoView({
            stake: node.stake,
            endpoint: node.endpoint,
            delegatorPoolPremiumShare: node.delegatorPoolPremiumShare,
            status: node.status,
            minExitTimestamp: node.minExitTimestamp,
            unpaidProtocolRewards: node.unpaidProtocolRewards,
            rewardShares: node.rewardShares
        });
    }

    function relayerInfo_isAccount(RelayerAddress _relayerAddress, RelayerAccountAddress _account)
        external
        view
        override
        returns (bool)
    {
        return getRMStorage().relayerInfo[_relayerAddress].isAccount[_account];
    }

    function isGasTokenSupported(TokenAddress _token) external view override returns (bool) {
        return getRMStorage().isGasTokenSupported[_token];
    }

    function relayersPerWindow() external view override returns (uint256) {
        return getRMStorage().relayersPerWindow;
    }

    function blocksPerWindow() external view override returns (uint256) {
        return getRMStorage().blocksPerWindow;
    }

    function bondTokenAddress() external view override returns (TokenAddress) {
        return TokenAddress.wrap(address(getRMStorage().bondToken));
    }

    function getLatestCdfArray(RelayerAddress[] calldata _latestActiveRelayers)
        external
        view
        override
        returns (uint16[] memory)
    {
        uint16[] memory cdfArray = _generateCdfArray_c(_latestActiveRelayers);
        _verifyExternalStateForRelayerStateUpdation(cdfArray.m_hash(), _latestActiveRelayers.cd_hash());

        return cdfArray;
    }

    function jailTimeInSec() external view override returns (uint256) {
        return getRMStorage().jailTimeInSec;
    }

    function withdrawDelayInSec() external view override returns (uint256) {
        return getRMStorage().withdrawDelayInSec;
    }

    function absencePenaltyPercentage() external view override returns (uint256) {
        return getRMStorage().absencePenaltyPercentage;
    }

    function minimumStakeAmount() external view override returns (uint256) {
        return getRMStorage().minimumStakeAmount;
    }

    function relayerStateUpdateDelayInWindows() external view override returns (uint256) {
        return getRMStorage().relayerStateUpdateDelayInWindows;
    }

    function relayerStateHash() external view returns (bytes32 activeStateHash, bytes32 pendingStateHash) {
        RMStorage storage rms = getRMStorage();
        activeStateHash = rms.relayerStateVersionManager.activeStateHash(_windowIndex(block.number));
        pendingStateHash = rms.relayerStateVersionManager.pendingStateHash();
    }
}
