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

import "forge-std/console2.sol";

contract TARelayerManagement is
    ITARelayerManagement,
    TARelayerManagementStorage,
    TAHelpers,
    TATransactionAllocationStorage
{
    using SafeCast for uint256;
    using SafeERC20 for IERC20;

    function _scaleStake(uint256 _stake) internal pure returns (uint32) {
        return (_stake / STAKE_SCALING_FACTOR).toUint32();
    }

    function _addNewRelayerToDelegationArray(uint32[] calldata _delegationArray)
        internal
        pure
        returns (uint32[] memory)
    {
        uint256 delegationArrayLength = _delegationArray.length;
        uint32[] memory newDelegationArrayLength = new uint32[](delegationArrayLength + 1);

        for (uint256 i = 0; i < delegationArrayLength;) {
            newDelegationArrayLength[i] = _delegationArray[i];
            unchecked {
                ++i;
            }
        }
        newDelegationArrayLength[delegationArrayLength] = 0;

        return newDelegationArrayLength;
    }

    function _addNewRelayerToStakeArray(uint32[] calldata _stakeArray, uint256 _stake)
        internal
        pure
        returns (uint32[] memory)
    {
        uint256 stakeArrayLength = _stakeArray.length;
        uint32[] memory newStakeArray = new uint32[](stakeArrayLength + 1);

        for (uint256 i = 0; i < stakeArrayLength;) {
            newStakeArray[i] = _stakeArray[i];
            unchecked {
                ++i;
            }
        }
        newStakeArray[stakeArrayLength] = _scaleStake(_stake);

        return newStakeArray;
    }

    function _removeRelayerFromStakeArray(uint32[] calldata _stakeArray, uint256 _index)
        internal
        pure
        returns (uint32[] memory)
    {
        uint256 newStakeArrayLength = _stakeArray.length - 1;
        uint32[] memory newStakeArray = new uint32[](newStakeArrayLength);

        for (uint256 i = 0; i < newStakeArrayLength;) {
            if (i == _index) {
                // Remove the node's stake from the array by substituting it with the last element
                newStakeArray[i] = _stakeArray[newStakeArrayLength];
            } else {
                newStakeArray[i] = _stakeArray[i];
            }
            unchecked {
                ++i;
            }
        }

        return newStakeArray;
    }

    function _removeRelayerFromDelegationArray(uint32[] calldata _delegationArray, uint256 _index)
        internal
        pure
        returns (uint32[] memory)
    {
        uint256 newDelegationArrayLength = _delegationArray.length - 1;
        uint32[] memory newDelegationArray = new uint32[](newDelegationArrayLength);

        for (uint256 i = 0; i < newDelegationArrayLength;) {
            if (i == _index) {
                // Remove the node's stake from the array by substituting it with the last element
                newDelegationArray[i] = _delegationArray[newDelegationArrayLength];
            } else {
                newDelegationArray[i] = _delegationArray[i];
            }
            unchecked {
                ++i;
            }
        }

        return newDelegationArray;
    }

    function _decreaseRelayerStakeInStakeArray(uint32[] calldata _stakeArray, uint256 _index, uint32 _scaledAmount)
        internal
        pure
        returns (uint32[] memory)
    {
        uint32[] memory newStakeArray = _stakeArray;
        newStakeArray[_index] = newStakeArray[_index] - _scaledAmount;
        return newStakeArray;
    }

    // TODO: Implement a way to increase the relayer's stake
    /// @notice register a relayer
    /// @param _previousStakeArray current stake array for verification
    /// @param _stake amount to be staked
    /// @param _accounts list of accounts that the relayer will use for forwarding tx
    /// @param _endpoint that can be used by any app to send transactions to this relayer
    function register(
        uint32[] calldata _previousStakeArray,
        uint32[] calldata _currentDelegationArray,
        uint256 _stake,
        RelayerAccountAddress[] calldata _accounts,
        string memory _endpoint
    )
        external
        override
        verifyStakeArrayHash(_previousStakeArray)
        verifyDelegationArrayHash(_currentDelegationArray)
        returns (RelayerAddress)
    {
        RMStorage storage ds = getRMStorage();

        if (_accounts.length == 0) {
            revert NoAccountsProvided();
        }
        if (_stake < MINIMUM_STAKE_AMOUNT) {
            revert InsufficientStake(_stake, MINIMUM_STAKE_AMOUNT);
        }

        ds.bondToken.safeTransferFrom(msg.sender, address(this), _stake);

        RelayerAddress relayerAddress = RelayerAddress.wrap(msg.sender);
        RelayerInfo storage node = ds.relayerInfo[relayerAddress];
        node.stake += _stake;
        node.endpoint = _endpoint;
        node.index = ds.relayerCount;
        _setRelayerAccountAddresses(relayerAddress, _accounts);
        ds.relayerIndexToRelayer[node.index] = relayerAddress;
        ++ds.relayerCount;

        // Update stake array and hash
        uint32[] memory newStakeArray = _addNewRelayerToStakeArray(_previousStakeArray, _stake);
        uint32[] memory newDelegationArray = _addNewRelayerToDelegationArray(_currentDelegationArray);
        _updateAccountingState(newStakeArray, true, newDelegationArray, true);

        emit RelayerRegistered(relayerAddress, _endpoint, _accounts, _stake);

        return relayerAddress;
    }

    /// @notice a relayer un unregister, which removes it from the relayer list and a delay for withdrawal is imposed on funds
    function unRegister(uint32[] calldata _previousStakeArray, uint32[] calldata _previousDelegationArray)
        external
        override
        verifyStakeArrayHash(_previousStakeArray)
        verifyDelegationArrayHash(_previousDelegationArray)
        onlyStakedRelayer(RelayerAddress.wrap(msg.sender))
    {
        RMStorage storage ds = getRMStorage();
        TADStorage storage tad = getTADStorage();

        RelayerAddress relayerAddress = RelayerAddress.wrap(msg.sender);
        RelayerInfo storage node = ds.relayerInfo[relayerAddress];
        uint256 n = ds.relayerCount - 1;
        uint256 nodeIndex = node.index;
        uint256 stake = node.stake;
        _setRelayerAccountAddresses(relayerAddress, new RelayerAccountAddress[](0));

        TokenAddress[] storage supportedPools = tad.supportedPools[relayerAddress];
        uint256 length = supportedPools.length;
        for (uint256 i = 0; i < length;) {
            delete node.isGasTokenSupported[supportedPools[i]];
            unchecked {
                ++i;
            }
        }

        delete ds.relayerInfo[relayerAddress];

        if (nodeIndex != n) {
            RelayerAddress lastRelayer = ds.relayerIndexToRelayer[n];
            ds.relayerIndexToRelayer[nodeIndex] = lastRelayer;
            ds.relayerInfo[lastRelayer].index = nodeIndex;
            ds.relayerIndexToRelayer[n] = RelayerAddress.wrap(address(0));
        }

        --ds.relayerCount;

        // Update stake percentages array and hash
        uint32[] memory newStakeArray = _removeRelayerFromStakeArray(_previousStakeArray, nodeIndex);
        uint32[] memory newDelegationArray = _removeRelayerFromDelegationArray(_previousDelegationArray, nodeIndex);
        uint256 updateEffectiveAtWindowId = _updateAccountingState(newStakeArray, true, newDelegationArray, true);
        ds.withdrawalInfo[relayerAddress] =
            WithdrawalInfo(stake, _windowIndexToStartingBlock(updateEffectiveAtWindowId));
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

    function setRelayerAccountsStatus(RelayerAccountAddress[] calldata _accounts)
        external
        override
        onlyStakedRelayer(RelayerAddress.wrap(msg.sender))
    {
        RelayerAddress relayerAddress = RelayerAddress.wrap(msg.sender);
        _setRelayerAccountAddresses(relayerAddress, _accounts);
        emit RelayerAccountsUpdated(relayerAddress, _accounts);
    }

    function processAbsenceProof(
        AbsenceProofReporterData calldata _reporterData,
        AbsenceProofAbsenteeData calldata _absenteeData,
        uint32[] calldata _currentStakeArray,
        uint32[] calldata _currentDelegationArray,
        uint256 _currentCdfLogIndex
    )
        public
        override
        verifyCdfHashAtWindow(_reporterData.cdf, _windowIndex(block.number), _currentCdfLogIndex)
        verifyStakeArrayHash(_currentStakeArray)
        verifyDelegationArrayHash(_currentDelegationArray)
    {
        uint256 gas = gasleft();

        RelayerAccountAddress reporter_relayerAddress = RelayerAccountAddress.wrap(msg.sender);
        RelayerInfo storage absence_relayerInfo = getRMStorage().relayerInfo[_absenteeData.relayerAddress];

        if (
            !(_reporterData.relayerGenerationIterations.length == 1)
                || !(_reporterData.relayerGenerationIterations[0] == ABSENTEE_PROOF_REPORTER_GENERATION_ITERATION)
        ) {
            revert InvalidRelayerWindowForReporter();
        }

        // Verify Reporter Selection in Current Window
        if (
            !_verifyRelayerSelection(
                RelayerAccountAddress.unwrap(reporter_relayerAddress),
                _reporterData.cdf,
                _reporterData.cdfIndex,
                _reporterData.relayerGenerationIterations,
                block.number
            )
        ) {
            revert InvalidRelayerWindowForReporter();
        }

        {
            RMStorage storage ds = getRMStorage();

            // Absentee block must not be in a point before the contract was deployed
            if (_absenteeData.blockNumber < ds.penaltyDelayBlocks) {
                revert InvalidAbsenteeBlockNumber();
            }

            {
                // The Absentee block must not be in the current window
                uint256 currentWindowStartBlock = block.number - (block.number % ds.blocksPerWindow);
                if (_absenteeData.blockNumber >= currentWindowStartBlock) {
                    revert InvalidAbsenteeBlockNumber();
                }
            }
        }

        {
            // Verify CDF hash of the Absentee Window
            uint256 absentee_windowId = _windowIndex(_absenteeData.blockNumber);
            if (
                !_verifyCdfHashAtWindow(
                    _absenteeData.cdf, absentee_windowId, _absenteeData.latestStakeUpdationCdfLogIndex
                )
            ) {
                revert InvalidAbsenteeCdfArrayHash();
            }

            // Verify Absence of the relayer
            TAStorage storage ts = getTAStorage();
            if (ts.attendance[absentee_windowId][_absenteeData.relayerAddress]) {
                revert AbsenteeWasPresent(absentee_windowId);
            }
        }

        // Verify Relayer Selection in Absentee Window
        if (
            !_verifyRelayerSelection(
                RelayerAddress.unwrap(_absenteeData.relayerAddress),
                _absenteeData.cdf,
                _absenteeData.cdfIndex,
                _absenteeData.relayerGenerationIterations,
                _absenteeData.blockNumber
            )
        ) {
            revert InvalidRelayerWindowForAbsentee();
        }

        emit GenericGasConsumed("Verification", gas - gasleft());
        gas = gasleft();

        // Process penalty
        uint256 penalty = (absence_relayerInfo.stake * ABSENCE_PENALTY) / 10000;
        if (_isStakedRelayer(_absenteeData.relayerAddress)) {
            // If the relayer is still registered at this point of time, then we need to update the stake array and CDF
            uint32[] memory newStakeArray =
                _decreaseRelayerStakeInStakeArray(_currentStakeArray, _absenteeData.cdfIndex, _scaleStake(penalty));
            _updateAccountingState(newStakeArray, true, _currentDelegationArray, false);
            getRMStorage().relayerInfo[_absenteeData.relayerAddress].stake -= penalty;
        } else {
            // If the relayer un-registerd itself, then we just subtract from their withdrawl info
            // TODO: Test
            getRMStorage().withdrawalInfo[_absenteeData.relayerAddress].amount -= penalty;
        }
        _transfer(
            TokenAddress.wrap(address(getRMStorage().bondToken)),
            RelayerAccountAddress.unwrap(reporter_relayerAddress),
            penalty
        );

        emit AbsenceProofProcessed(
            _windowIndex(block.number),
            RelayerAccountAddress.unwrap(reporter_relayerAddress),
            _absenteeData.relayerAddress,
            _windowIndex(_absenteeData.blockNumber),
            penalty
        );

        emit GenericGasConsumed("Process Penalty", gas - gasleft());
    }

    ////////////////////////// Relayer Configuration //////////////////////////
    // TODO: Jailed relayers should not be able to update their configuration

    function addSupportedGasTokens(RelayerAddress _relayerAddress, TokenAddress[] calldata _tokens)
        external
        override
        onlyStakedRelayer(_relayerAddress)
    {
        RMStorage storage ds = getRMStorage();
        TADStorage storage tds = getTADStorage();

        RelayerInfo storage node = ds.relayerInfo[_relayerAddress];

        uint256 length = _tokens.length;
        for (uint256 i = 0; i < length;) {
            TokenAddress token = _tokens[i];

            if (node.isGasTokenSupported[token]) {
                revert GasTokenAlreadySupported(token);
            }

            // Update Mapping
            node.isGasTokenSupported[token] = true;

            // TODO: Optimize? One time operation, Max length of this array is 4-5
            // Update supported pools array
            uint256 _length = tds.supportedPools[_relayerAddress].length;
            bool found = false;
            for (uint256 j = 0; j < _length;) {
                if (tds.supportedPools[_relayerAddress][j] == token) {
                    found = true;
                    break;
                }

                unchecked {
                    ++j;
                }
            }
            if (!found) {
                tds.supportedPools[_relayerAddress].push(token);
            }

            unchecked {
                ++i;
            }
        }

        emit GasTokensAdded(_relayerAddress, _tokens);
    }

    function removeSupportedGasTokens(RelayerAddress _relayerAddress, TokenAddress[] calldata _tokens)
        external
        override
        onlyStakedRelayer(_relayerAddress)
    {
        RMStorage storage ds = getRMStorage();
        RelayerInfo storage node = ds.relayerInfo[_relayerAddress];

        uint256 length = _tokens.length;
        for (uint256 i = 0; i < length;) {
            TokenAddress token = _tokens[i];

            if (!node.isGasTokenSupported[token]) {
                revert GasTokenNotSupported(token);
            }

            // Update Mapping
            node.isGasTokenSupported[token] = false;

            // Do not remove the token from the suppported pools array
            // since it is used to keep track of delegator rewards

            unchecked {
                ++i;
            }
        }

        emit GasTokensRemoved(_relayerAddress, _tokens);
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

    function relayerInfo_Index(RelayerAddress _relayerAddress) external view override returns (uint256) {
        return getRMStorage().relayerInfo[_relayerAddress].index;
    }

    function relayerInfo_isAccount(RelayerAddress _relayerAddress, RelayerAccountAddress _account)
        external
        view
        override
        returns (bool)
    {
        return getRMStorage().relayerInfo[_relayerAddress].isAccount[_account];
    }

    function relayerInfo_isGasTokenSupported(RelayerAddress _relayerAddress, TokenAddress _token)
        external
        view
        override
        returns (bool)
    {
        return getRMStorage().relayerInfo[_relayerAddress].isGasTokenSupported[_token];
    }

    function relayersPerWindow() external view override returns (uint256) {
        return getRMStorage().relayersPerWindow;
    }

    function blocksPerWindow() external view override returns (uint256) {
        return getRMStorage().blocksPerWindow;
    }

    function cdfHashUpdateLog(uint256 _index) external view override returns (CdfHashUpdateInfo memory) {
        return getRMStorage().cdfHashUpdateLog[_index];
    }

    function stakeArrayHash() external view override returns (bytes32) {
        return getRMStorage().stakeArrayHash;
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
    function getStakeArray() public view override returns (uint32[] memory) {
        RMStorage storage ds = getRMStorage();

        uint256 length = ds.relayerCount;
        uint32[] memory stakeArray = new uint32[](length);
        for (uint256 i = 0; i < length;) {
            stakeArray[i] = _scaleStake(ds.relayerInfo[ds.relayerIndexToRelayer[i]].stake);
            unchecked {
                ++i;
            }
        }
        return stakeArray;
    }

    function getCdfArray() public view override returns (uint16[] memory) {
        uint32[] memory stakeArray = getStakeArray();
        uint32[] memory delegationArray = ITADelegation(address(this)).getDelegationArray();
        (uint16[] memory cdfArray,) = _generateCdfArray(stakeArray, delegationArray);
        return cdfArray;
    }
}
