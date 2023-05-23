// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import "openzeppelin-contracts/contracts/utils/math/SafeCast.sol";
import "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";

import "./interfaces/ITARelayerManagement.sol";
import "../delegation/interfaces/ITADelegation.sol";
import "./TARelayerManagementStorage.sol";
import "../transaction-allocation/TATransactionAllocationStorage.sol";
import "../../common/TAHelpers.sol";
import "../../common/TAConstants.sol";
import "src/library/FixedPointArithmetic.sol";
import "src/library/VersionManager.sol";

contract TARelayerManagement is
    ITARelayerManagement,
    TARelayerManagementStorage,
    TAHelpers,
    TATransactionAllocationStorage
{
    using SafeCast for uint256;
    using SafeERC20 for IERC20;
    using Uint256WrapperHelper for uint256;
    using FixedPointTypeHelper for FixedPointType;
    using VersionManager for VersionManager.VersionManagerState;
    using U32ArrayHelper for uint32[];
    using RAArrayHelper for RelayerAddress[];

    ////////////////////////// Relayer Registration //////////////////////////

    // TODO: Implement a way to increase the relayer's stake
    // TODO: Cannot stake until the previous stake is withdrawn
    /// @notice register a relayer
    /// @param _previousStakeArray current stake array for verification
    /// @param _stake amount to be staked
    /// @param _accounts list of accounts that the relayer will use for forwarding tx
    /// @param _endpoint that can be used by any app to send transactions to this relayer
    function register(
        uint32[] calldata _previousStakeArray,
        uint32[] calldata _currentDelegationArray,
        RelayerAddress[] calldata _activeRelayers,
        uint256 _stake,
        RelayerAccountAddress[] calldata _accounts,
        string memory _endpoint,
        uint256 _delegatorPoolPremiumShare
    ) external override {
        _verifyExternalStateForCdfUpdation(_previousStakeArray, _currentDelegationArray, _activeRelayers);

        RMStorage storage rms = getRMStorage();

        if (_accounts.length == 0) {
            revert NoAccountsProvided();
        }
        if (_stake < MINIMUM_STAKE_AMOUNT) {
            revert InsufficientStake(_stake, MINIMUM_STAKE_AMOUNT);
        }

        rms.bondToken.safeTransferFrom(msg.sender, address(this), _stake);
        {
            // Store relayer info
            RelayerAddress relayerAddress = RelayerAddress.wrap(msg.sender);
            RelayerInfo storage node = rms.relayerInfo[relayerAddress];
            node.stake += _stake;
            node.endpoint = _endpoint;
            node.delegatorPoolPremiumShare = _delegatorPoolPremiumShare;
            node.rewardShares = _mintProtocolRewardShares(_stake);
            _setRelayerAccountAddresses(relayerAddress, _accounts);
            rms.totalStake += _stake;
            ++rms.relayerCount;

            // Update Active Relayer List
            RelayerAddress[] memory newActiveRelayers = _activeRelayers.cd_append(relayerAddress);
            rms.activeRelayerListVersionManager.setPendingState(newActiveRelayers.m_hash());
            emit RelayerRegistered(relayerAddress, _endpoint, _accounts, _stake, _delegatorPoolPremiumShare);
        }

        // Update stake array and hash
        uint32[] memory newStakeArray = _previousStakeArray.cd_append(_scaleStake(_stake));
        uint32[] memory newDelegationArray = _currentDelegationArray.cd_append(0);
        _updateCdf(newStakeArray, true, newDelegationArray, true);
    }

    /// @notice a relayer un unregister, which removes it from the relayer list and a delay for withdrawal is imposed on funds
    function unRegister(
        uint32[] calldata _previousStakeArray,
        uint32[] calldata _previousDelegationArray,
        RelayerAddress[] calldata _activeRelayers,
        uint256 _relayerIndex
    ) external override onlyStakedRelayer(RelayerAddress.wrap(msg.sender)) {
        _verifyExternalStateForCdfUpdation(_previousStakeArray, _previousDelegationArray, _activeRelayers);

        // Verify relayer index
        RelayerAddress relayerAddress = RelayerAddress.wrap(msg.sender);
        if (_activeRelayers[_relayerIndex] != relayerAddress) {
            revert InvalidRelayer(relayerAddress);
        }

        RMStorage storage rms = getRMStorage();

        // TODO: claimProtocolReward();

        RelayerInfo storage node = rms.relayerInfo[relayerAddress];
        rms.totalShares = rms.totalShares - node.rewardShares;
        uint256 stake = node.stake;
        _setRelayerAccountAddresses(relayerAddress, new RelayerAccountAddress[](0));
        delete rms.relayerInfo[relayerAddress];

        --rms.relayerCount;
        rms.totalStake -= stake;

        // Update stake percentages array and hash
        uint32[] memory newStakeArray = _previousStakeArray.cd_remove(_relayerIndex);
        uint32[] memory newDelegationArray = _previousDelegationArray.cd_remove(_relayerIndex);
        _updateCdf(newStakeArray, true, newDelegationArray, true);

        // Update Active Relayers
        RelayerAddress[] memory newActiveRelayers = _activeRelayers.cd_remove(_relayerIndex);
        rms.activeRelayerListVersionManager.setPendingState(newActiveRelayers.m_hash());

        // Create withdrawal Info
        rms.withdrawalInfo[relayerAddress] = WithdrawalInfo(stake, block.number + RELAYER_WITHDRAW_DELAY_IN_BLOCKS);

        emit RelayerUnRegistered(relayerAddress);
    }

    function withdraw() external override {
        RMStorage storage ds = getRMStorage();

        RelayerAddress relayerAddress = RelayerAddress.wrap(msg.sender);

        WithdrawalInfo memory w = ds.withdrawalInfo[relayerAddress];
        delete ds.withdrawalInfo[relayerAddress];

        if (w.amount == 0 || w.minBlockNumber > block.number) {
            revert InvalidWithdrawal(w.amount, block.number, w.minBlockNumber);
        }
        _transfer(TokenAddress.wrap(address(ds.bondToken)), msg.sender, w.amount);
        emit Withdraw(relayerAddress, w.amount);
    }

    function _setRelayerAccountAddresses(RelayerAddress _relayerAddress, RelayerAccountAddress[] memory _accounts)
        internal
    {
        RelayerInfo storage node = getRMStorage().relayerInfo[_relayerAddress];

        // Delete old accounts
        uint256 length = node.relayerAccountAddresses.length;
        for (uint256 i = 0; i < length;) {
            node.isAccount[node.relayerAccountAddresses[i]] = false;
            unchecked {
                ++i;
            }
        }

        // Add new accounts
        length = _accounts.length;
        for (uint256 i = 0; i < length;) {
            node.isAccount[_accounts[i]] = true;
            unchecked {
                ++i;
            }
        }
        node.relayerAccountAddresses = _accounts;
    }

    function setRelayerAccounts(RelayerAccountAddress[] calldata _accounts)
        external
        override
        onlyStakedRelayer(RelayerAddress.wrap(msg.sender))
    {
        RelayerAddress relayerAddress = RelayerAddress.wrap(msg.sender);
        _setRelayerAccountAddresses(relayerAddress, _accounts);
        emit RelayerAccountsUpdated(relayerAddress, _accounts);
    }

    ////////////////////////// Relayer Configuration //////////////////////////
    // TODO: Jailed relayers should not be able to update their configuration

    ////////////////////////// Constant Rate Rewards //////////////////////////
    function claimProtocolReward() public override onlyStakedRelayer(RelayerAddress.wrap(msg.sender)) {
        _updateProtocolRewards();

        // Calculate Rewards
        (uint256 relayerReward, uint256 delegatorRewards) =
            _burnRewardSharesForRelayerAndGetRewards(RelayerAddress.wrap(msg.sender));

        // Process Delegator Rewards
        RMStorage storage rs = getRMStorage();
        _addDelegatorRewards(
            RelayerAddress.wrap(msg.sender), TokenAddress.wrap(address(rs.bondToken)), delegatorRewards
        );

        // Process Relayer Rewards
        relayerReward += rs.relayerInfo[RelayerAddress.wrap(msg.sender)].unpaidProtocolRewards;
        rs.relayerInfo[RelayerAddress.wrap(msg.sender)].unpaidProtocolRewards = 0;
        _transfer(TokenAddress.wrap(address(rs.bondToken)), msg.sender, relayerReward);

        emit RelayerProtocolRewardsClaimed(RelayerAddress.wrap(msg.sender), relayerReward);
    }

    function _mintProtocolRewardShares(uint256 _amount) internal returns (FixedPointType) {
        _updateProtocolRewards();

        RMStorage storage rs = getRMStorage();

        FixedPointType rewardShares = _amount.fp() / _protocolRewardRelayerSharePrice();
        rs.totalShares = rs.totalShares + rewardShares;

        emit RelayerProtocolRewardMinted(rewardShares);

        return rewardShares;
    }

    ////////////////////////// Getters //////////////////////////
    function relayerCount() external view override returns (uint256) {
        return getRMStorage().relayerCount;
    }

    function relayerInfo_Stake(RelayerAddress _relayerAddress) external view override returns (uint256) {
        return getRMStorage().relayerInfo[_relayerAddress].stake;
    }

    function relayerInfo_Endpoint(RelayerAddress _relayerAddress) external view override returns (string memory) {
        return getRMStorage().relayerInfo[_relayerAddress].endpoint;
    }

    function relayerInfo_isAccount(RelayerAddress _relayerAddress, RelayerAccountAddress _account)
        external
        view
        override
        returns (bool)
    {
        return getRMStorage().relayerInfo[_relayerAddress].isAccount[_account];
    }

    function relayerInfo_delegatorPoolPremiumShare(RelayerAddress _relayerAddress) external view returns (uint256) {
        return getRMStorage().relayerInfo[_relayerAddress].delegatorPoolPremiumShare;
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

    // TODO
    // function cdfHashUpdateLog(uint256 _index) external view override returns (CdfHashUpdateInfo memory) {
    //     return getRMStorage().cdfHashUpdateLog[_index];
    // }

    function latestActiveRelayerStakeArrayHash() external view override returns (bytes32) {
        return getRMStorage().latestActiveRelayerStakeArrayHash;
    }

    function penaltyDelayBlocks() external view override returns (uint256) {
        return getRMStorage().penaltyDelayBlocks;
    }

    function withdrawalInfo(RelayerAddress _relayerAddress) external view override returns (WithdrawalInfo memory) {
        return getRMStorage().withdrawalInfo[_relayerAddress];
    }

    function bondTokenAddress() external view override returns (TokenAddress) {
        return TokenAddress.wrap(address(getRMStorage().bondToken));
    }

    ////////////////////////// Getters For Derived State //////////////////////////
    function getStakeArray(RelayerAddress[] calldata _activeRelayers)
        public
        view
        override
        verifyLatestActiveRelayerList(_activeRelayers)
        returns (uint32[] memory)
    {
        RMStorage storage ds = getRMStorage();

        uint256 length = _activeRelayers.length;
        uint32[] memory stakeArray = new uint32[](length);
        for (uint256 i = 0; i < length;) {
            RelayerAddress relayerAddress = _activeRelayers[i];
            stakeArray[i] = _scaleStake(ds.relayerInfo[relayerAddress].stake);
            unchecked {
                ++i;
            }
        }
        return stakeArray;
    }

    function getCdfArray(RelayerAddress[] calldata _activeRelayers)
        public
        view
        override
        verifyLatestActiveRelayerList(_activeRelayers)
        returns (uint16[] memory)
    {
        uint32[] memory stakeArray = getStakeArray(_activeRelayers);
        uint32[] memory delegationArray = ITADelegation(address(this)).getDelegationArray(_activeRelayers);
        uint16[] memory cdfArray = _generateCdfArray(stakeArray, delegationArray);
        return cdfArray;
    }
}
