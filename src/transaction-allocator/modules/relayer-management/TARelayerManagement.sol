// SPDX-License-Identifier: MIT

pragma solidity 0.8.17;

import "openzeppelin-contracts/contracts/utils/math/SafeCast.sol";

import "./interfaces/ITARelayerManagement.sol";
import "./TARelayerManagementStorage.sol";
import "../transaction-allocation/TATransactionAllocationStorage.sol";
import "../../common/TAHelpers.sol";
import "../../common/TAConstants.sol";

import "forge-std/console2.sol";

contract TARelayerManagement is
    TAConstants,
    ITARelayerManagement,
    TARelayerManagementStorage,
    TAHelpers,
    TATransactionAllocationStorage
{
    using SafeCast for uint256;

    function _verifyPrevCdfHash(uint16[] calldata _array, uint256 _windowId, uint256 _cdfLogIndex)
        internal
        view
        returns (bool)
    {
        // Validate _cdfLogIndex
        RMStorage storage ds = getRMStorage();
        if (
            !(
                ds.cdfHashUpdateLog[_cdfLogIndex].windowId <= _windowId
                    && (
                        _cdfLogIndex == ds.cdfHashUpdateLog.length - 1
                            || ds.cdfHashUpdateLog[_cdfLogIndex + 1].windowId > _windowId
                    )
            )
        ) {
            return false;
        }

        return ds.cdfHashUpdateLog[_cdfLogIndex].cdfHash == keccak256(abi.encodePacked(_array));
    }

    function _stakeArrayToCdf(uint32[] memory _stakeArray) internal pure returns (uint16[] memory, bytes32 cdfHash) {
        uint16[] memory cdf = new uint16[](_stakeArray.length);
        uint256 totalStakeSum = 0;
        uint256 length = _stakeArray.length;
        for (uint256 i = 0; i < length;) {
            totalStakeSum += _stakeArray[i];
            unchecked {
                ++i;
            }
        }

        // Scale the values to get the CDF
        uint256 sum = 0;
        for (uint256 i = 0; i < length;) {
            sum += _stakeArray[i];
            cdf[i] = ((sum * CDF_PRECISION_MULTIPLIER) / totalStakeSum).toUint16();
            unchecked {
                ++i;
            }
        }

        return (cdf, keccak256(abi.encodePacked(cdf)));
    }

    function _appendStake(uint32[] calldata _stakeArray, uint256 _stake) internal pure returns (uint32[] memory) {
        uint256 stakeArrayLength = _stakeArray.length;
        uint32[] memory newStakeArray = new uint32[](stakeArrayLength + 1);

        // TODO: can this be optimized using calldatacopy?
        for (uint256 i = 0; i < stakeArrayLength;) {
            newStakeArray[i] = _stakeArray[i];
            unchecked {
                ++i;
            }
        }
        newStakeArray[stakeArrayLength] = (_stake / STAKE_SCALING_FACTOR).toUint32();

        return newStakeArray;
    }

    function _removeStake(uint32[] calldata _stakeArray, uint256 _index) internal pure returns (uint32[] memory) {
        uint256 newStakeArrayLength = _stakeArray.length - 1;
        uint32[] memory newStakeArray = new uint32[](newStakeArrayLength);

        // TODO: can this be optimized using calldatacopy?
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

    function _decreaseStake(uint32[] calldata _stakeArray, uint256 _index, uint32 _scaledAmount)
        internal
        pure
        returns (uint32[] memory)
    {
        // TODO: Is this optimal?
        uint32[] memory newStakeArray = _stakeArray;
        newStakeArray[_index] = newStakeArray[_index] - _scaledAmount;
        return newStakeArray;
    }

    function _updateStakeAccounting(uint32[] memory _newStakeArray) internal {
        RMStorage storage ds = getRMStorage();

        // Update Stake Array Hash
        ds.stakeArrayHash = keccak256(abi.encodePacked(_newStakeArray));

        // Update cdf hash
        (, bytes32 cdfHash) = _stakeArrayToCdf(_newStakeArray);
        uint256 currentWindowId = _windowIdentifier(block.number);
        if (
            ds.cdfHashUpdateLog.length == 0
                || ds.cdfHashUpdateLog[ds.cdfHashUpdateLog.length - 1].windowId != currentWindowId
        ) {
            ds.cdfHashUpdateLog.push(CdfHashUpdateInfo({windowId: _windowIdentifier(block.number), cdfHash: cdfHash}));
        } else {
            ds.cdfHashUpdateLog[ds.cdfHashUpdateLog.length - 1].cdfHash = cdfHash;
        }

        emit StakeArrayUpdated(ds.stakeArrayHash);
        emit CdfArrayUpdated(cdfHash);
    }

    function _sendPenalty(address _reporter, uint256 _amount) internal {
        (bool success,) = _reporter.call{value: _amount}("");
        if (!success) {
            revert ReporterTransferFailed(_reporter, _amount);
        }
    }

    function getStakeArray() public view returns (uint32[] memory) {
        RMStorage storage ds = getRMStorage();

        uint256 length = ds.relayerCount;
        uint32[] memory stakeArray = new uint32[](length);
        for (uint256 i = 0; i < length;) {
            stakeArray[i] = (ds.relayerInfo[ds.relayerIndexToRelayer[i]].stake / STAKE_SCALING_FACTOR).toUint32();
            unchecked {
                ++i;
            }
        }
        return stakeArray;
    }

    function getCdf() public view returns (uint16[] memory) {
        (uint16[] memory cdfArray,) = _stakeArrayToCdf(getStakeArray());
        return cdfArray;
    }

    /// @notice register a relayer
    /// @param _previousStakeArray current stake array for verification
    /// @param _stake amount to be staked
    /// @param _accounts list of accounts that the relayer will use for forwarding tx
    /// @param _endpoint that can be used by any app to send transactions to this relayer
    function register(
        uint32[] calldata _previousStakeArray,
        uint256 _stake,
        address[] calldata _accounts,
        string memory _endpoint
    ) external verifyStakeArrayHash(_previousStakeArray) {
        RMStorage storage ds = getRMStorage();

        if (_accounts.length == 0) {
            revert NoAccountsProvided();
        }
        if (_stake < MINIMUM_STAKE_AMOUNT) {
            revert InsufficientStake(_stake, MINIMUM_STAKE_AMOUNT);
        }

        RelayerInfo storage node = ds.relayerInfo[msg.sender];
        node.stake += _stake;
        node.endpoint = _endpoint;
        node.index = ds.relayerCount;
        uint256 length = _accounts.length;
        for (uint256 i = 0; i < length;) {
            node.isAccount[_accounts[i]] = true;
            unchecked {
                ++i;
            }
        }
        ds.relayerIndexToRelayer[node.index] = msg.sender;
        ++ds.relayerCount;

        // Update stake array and hash
        uint32[] memory newStakeArray = _appendStake(_previousStakeArray, _stake);
        _updateStakeAccounting(newStakeArray);

        // TODO: transfer stake amount to be stored in a vault.
        emit RelayerRegistered(msg.sender, _endpoint, _accounts, _stake);
    }

    /// @notice a relayer un unregister, which removes it from the relayer list and a delay for withdrawal is imposed on funds
    /// @param _previousStakeArray current stake array for verification
    function unRegister(uint32[] calldata _previousStakeArray) external verifyStakeArrayHash(_previousStakeArray) {
        RMStorage storage ds = getRMStorage();

        RelayerInfo storage node = ds.relayerInfo[msg.sender];
        uint256 n = ds.relayerCount - 1;
        uint256 stake = node.stake;
        uint256 nodeIndex = node.index;
        delete ds.relayerInfo[msg.sender];

        if (nodeIndex != n) {
            address lastRelayer = ds.relayerIndexToRelayer[n];
            ds.relayerIndexToRelayer[nodeIndex] = lastRelayer;
            ds.relayerInfo[lastRelayer].index = nodeIndex;
            ds.relayerIndexToRelayer[n] = address(0);
        }

        --ds.relayerCount;

        ds.withdrawalInfo[msg.sender] = WithdrawalInfo(stake, block.timestamp + ds.withdrawDelay);

        // Update stake percentages array and hash
        uint32[] memory newStakeArray = _removeStake(_previousStakeArray, nodeIndex);
        _updateStakeAccounting(newStakeArray);
        emit RelayerUnRegistered(msg.sender);
    }

    function withdraw() external {
        RMStorage storage ds = getRMStorage();

        WithdrawalInfo memory w = ds.withdrawalInfo[msg.sender];
        if (!(w.amount > 0 && w.time < block.timestamp)) {
            // TODO: Max Valid Time??
            revert InvalidWithdrawal(w.amount, block.timestamp, w.time, 0);
        }
        ds.withdrawalInfo[msg.sender] = WithdrawalInfo(0, 0);

        // todo: send w.amount to relayer

        emit Withdraw(msg.sender, w.amount);
    }

    function setRelayerAccountsStatus(address[] calldata _accounts, bool[] calldata _status) external {
        if (_accounts.length != _status.length) {
            revert ParameterLengthMismatch();
        }

        RMStorage storage ds = getRMStorage();
        RelayerInfo storage node = ds.relayerInfo[msg.sender];
        if (node.stake == 0) {
            revert InvalidRelayer(msg.sender);
        }

        uint256 length = _accounts.length;
        for (uint256 i = 0; i < length;) {
            node.isAccount[_accounts[i]] = _status[i];
            unchecked {
                ++i;
            }
        }

        emit RelayerAccountsUpdated(msg.sender, _accounts, _status);
    }

    function processAbsenceProof(
        AbsenceProofReporterData calldata _reporterData,
        AbsenceProofAbsenteeData calldata _absenteeData,
        uint32[] calldata _currentStakeArray
    ) public verifyCdfHash(_reporterData.cdf) verifyStakeArrayHash(_currentStakeArray) {
        uint256 gas = gasleft();

        address reporter_relayerAddress = msg.sender;

        if (
            !(_reporterData.relayerGenerationIterations.length == 1)
                || !(_reporterData.relayerGenerationIterations[0] == ABSENTEE_PROOF_REPORTER_GENERATION_ITERATION)
        ) {
            revert InvalidRelayerWindowForReporter();
        }

        // Verify Reporter Selection in Current Window
        if (
            !_verifyRelayerSelection(
                reporter_relayerAddress,
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
            uint256 absentee_windowId = _windowIdentifier(_absenteeData.blockNumber);
            if (!_verifyPrevCdfHash(_absenteeData.cdf, absentee_windowId, _absenteeData.latestStakeUpdationCdfLogIndex))
            {
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
                _absenteeData.relayerAddress,
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
        uint256 penalty = (getRMStorage().relayerInfo[_absenteeData.relayerAddress].stake * ABSENCE_PENALTY) / 10000;
        uint32[] memory newStakeArray =
            _decreaseStake(_currentStakeArray, _absenteeData.cdfIndex, (penalty / STAKE_SCALING_FACTOR).toUint32());
        _updateStakeAccounting(newStakeArray);
        // TODO: Enable once funds are accepted in registration flow
        // _sendPenalty(reporter_relayerAddress, penalty);

        emit AbsenceProofProcessed(
            _windowIdentifier(block.number),
            msg.sender,
            _absenteeData.relayerAddress,
            _windowIdentifier(_absenteeData.blockNumber),
            penalty
            );

        emit GenericGasConsumed("Process Penalty", gas - gasleft());
    }

    ////////////////////////// Getters //////////////////////////

    function relayerCount() external view override returns (uint256) {
        return getRMStorage().relayerCount;
    }

    function relayerInfo_Stake(address _relayer) external view override returns (uint256) {
        return getRMStorage().relayerInfo[_relayer].stake;
    }

    function relayerInfo_Endpoint(address _relayer) external view override returns (string memory) {
        return getRMStorage().relayerInfo[_relayer].endpoint;
    }

    function relayerInfo_Index(address _relayer) external view override returns (uint256) {
        return getRMStorage().relayerInfo[_relayer].index;
    }

    function relayerInfo_isAccount(address _relayer, address _account) external view override returns (bool) {
        return getRMStorage().relayerInfo[_relayer].isAccount[_account];
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

    function withdrawalInfo(address _relayer) external view override returns (WithdrawalInfo memory) {
        return getRMStorage().withdrawalInfo[_relayer];
    }

    function withdrawDelay() external view override returns (uint256) {
        return getRMStorage().withdrawDelay;
    }
}
