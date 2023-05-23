// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

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
    /// @param _latestStakeArray current stake array for verification
    /// @param _stake amount to be staked
    /// @param _accounts list of accounts that the relayer will use for forwarding tx
    /// @param _endpoint that can be used by any app to send transactions to this relayer
    function register(
        uint32[] calldata _latestStakeArray,
        uint32[] calldata _latestDelegationArray,
        RelayerAddress[] calldata _latestActiveRelayers,
        uint256 _stake,
        RelayerAccountAddress[] calldata _accounts,
        string memory _endpoint,
        uint256 _delegatorPoolPremiumShare
    ) external override {
        _verifyExternalStateForCdfUpdation(_latestStakeArray, _latestDelegationArray, _latestActiveRelayers);

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
            if (node.status != RelayerStatus.Uninitialized) {
                revert RelayerAlreadyRegistered();
            }

            node.stake += _stake;
            node.endpoint = _endpoint;
            node.delegatorPoolPremiumShare = _delegatorPoolPremiumShare;
            node.rewardShares = _mintProtocolRewardShares(_stake);
            node.status = RelayerStatus.Active;
            _setRelayerAccountAddresses(relayerAddress, _accounts);

            // Update Active Relayer List
            RelayerAddress[] memory newActiveRelayers = _latestActiveRelayers.cd_append(relayerAddress);
            rms.activeRelayerListVersionManager.setPendingState(newActiveRelayers.m_hash(), _windowIndex(block.number));
            emit RelayerRegistered(relayerAddress, _endpoint, _accounts, _stake, _delegatorPoolPremiumShare);
        }

        // Update stake array and hash
        uint32[] memory newStakeArray = _latestStakeArray.cd_append(_scaleStake(_stake));
        uint32[] memory newDelegationArray = _latestDelegationArray.cd_append(0);
        _updateCdf(newStakeArray, true, newDelegationArray, true);
    }

    /// @notice a relayer un unregister, which removes it from the relayer list and a delay for withdrawal is imposed on funds
    function unRegister(
        uint32[] calldata _latestStakeArray,
        uint32[] calldata _latestDelegationArray,
        RelayerAddress[] calldata _latestActiveRelayers,
        uint256 _relayerIndex
    ) external override onlyStakedRelayer(RelayerAddress.wrap(msg.sender)) {
        _verifyExternalStateForCdfUpdation(_latestStakeArray, _latestDelegationArray, _latestActiveRelayers);

        // Verify relayer index
        RelayerAddress relayerAddress = RelayerAddress.wrap(msg.sender);
        if (_latestActiveRelayers[_relayerIndex] != relayerAddress) {
            revert InvalidRelayer(relayerAddress);
        }

        // TODO: claimProtocolReward();

        RMStorage storage rms = getRMStorage();
        RelayerInfo storage node = rms.relayerInfo[relayerAddress];

        rms.totalShares = rms.totalShares - node.rewardShares;
        _setRelayerAccountAddresses(relayerAddress, new RelayerAccountAddress[](0));

        // Update stake percentages array and hash
        uint32[] memory newStakeArray = _latestStakeArray.cd_remove(_relayerIndex);
        uint32[] memory newDelegationArray = _latestDelegationArray.cd_remove(_relayerIndex);
        _updateCdf(newStakeArray, true, newDelegationArray, true);

        // Queue Update to Active Relayers
        RelayerAddress[] memory newActiveRelayers = _latestActiveRelayers.cd_remove(_relayerIndex);
        rms.activeRelayerListVersionManager.setPendingState(newActiveRelayers.m_hash(), _windowIndex(block.number));

        // Set withdrawal Info
        node.status = RelayerStatus.Exiting;
        node.minExitBlockNumber = block.number + RELAYER_WITHDRAW_DELAY_IN_BLOCKS;

        emit RelayerUnRegistered(relayerAddress);
    }

    function withdraw() external override {
        RMStorage storage rms = getRMStorage();

        RelayerAddress relayerAddress = RelayerAddress.wrap(msg.sender);
        RelayerInfo storage node = rms.relayerInfo[relayerAddress];

        if (node.status != RelayerStatus.Exiting) {
            revert RelayerNotExiting();
        }

        if (node.stake == 0 || node.minExitBlockNumber > block.number) {
            revert InvalidWithdrawal(node.stake, block.number, node.minExitBlockNumber);
        }
        _transfer(TokenAddress.wrap(address(rms.bondToken)), msg.sender, node.stake);
        emit Withdraw(relayerAddress, node.stake);

        delete rms.relayerInfo[relayerAddress];
    }

    function _setRelayerAccountAddresses(RelayerAddress _relayerAddress, RelayerAccountAddress[] memory _accounts)
        internal
    {
        RelayerInfo storage node = getRMStorage().relayerInfo[_relayerAddress];

        // Delete old accounts
        uint256 length = node.relayerAccountAddresses.length;
        for (uint256 i; i != length;) {
            node.isAccount[node.relayerAccountAddresses[i]] = false;
            unchecked {
                ++i;
            }
        }

        // Add new accounts
        length = _accounts.length;
        for (uint256 i; i != length;) {
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

    function relayerInfo(RelayerAddress _relayerAddress) external view override returns (RelayerInfoView memory) {
        RMStorage storage rms = getRMStorage();
        RelayerInfo storage node = rms.relayerInfo[_relayerAddress];

        return RelayerInfoView({
            stake: node.stake,
            endpoint: node.endpoint,
            delegatorPoolPremiumShare: node.delegatorPoolPremiumShare,
            relayerAccountAddresses: node.relayerAccountAddresses,
            status: node.status,
            minExitBlockNumber: node.minExitBlockNumber,
            unpaidProtocolRewards: node.unpaidProtocolRewards,
            rewardShares: node.rewardShares
        });
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

    function latestActiveRelayerStakeArrayHash() external view override returns (bytes32) {
        return getRMStorage().latestActiveRelayerStakeArrayHash;
    }

    function bondTokenAddress() external view override returns (TokenAddress) {
        return TokenAddress.wrap(address(getRMStorage().bondToken));
    }

    ////////////////////////// Getters For Derived State //////////////////////////
    function getStakeArray(RelayerAddress[] calldata _latestActiveRelayers)
        public
        view
        override
        verifyLatestActiveRelayerList(_latestActiveRelayers)
        returns (uint32[] memory)
    {
        RMStorage storage ds = getRMStorage();

        uint256 length = _latestActiveRelayers.length;
        uint32[] memory stakeArray = new uint32[](length);
        for (uint256 i; i != length;) {
            RelayerAddress relayerAddress = _latestActiveRelayers[i];
            stakeArray[i] = _scaleStake(ds.relayerInfo[relayerAddress].stake);
            unchecked {
                ++i;
            }
        }
        return stakeArray;
    }

    function getCdfArray(RelayerAddress[] calldata _latestActiveRelayers)
        public
        view
        override
        verifyLatestActiveRelayerList(_latestActiveRelayers)
        returns (uint16[] memory)
    {
        uint32[] memory stakeArray = getStakeArray(_latestActiveRelayers);
        uint32[] memory delegationArray = ITADelegation(address(this)).getDelegationArray(_latestActiveRelayers);
        uint16[] memory cdfArray = _generateCdfArray(stakeArray, delegationArray);
        return cdfArray;
    }
}
