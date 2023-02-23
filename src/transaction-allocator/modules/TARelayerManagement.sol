// SPDX-License-Identifier: MIT

pragma solidity 0.8.17;

import "openzeppelin-contracts/contracts/utils/math/SafeCast.sol";

import "../common/TAVerificationUtils.sol";
import "../../constants/TransactionAllocationConstants.sol";
import "../../library/TAProxyStorage.sol";
import "../../interfaces/ITARelayerManagement.sol";

contract TARelayerManagement is TAVerificationUtils, TransactionAllocationConstants, ITARelayerManagement {
    using SafeCast for uint256;

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
        TAStorage storage ps = TAProxyStorage.getProxyStorage();

        // Update Stake Array Hash
        ps.stakeArrayHash = keccak256(abi.encodePacked(_newStakeArray));

        // Update cdf hash
        (, bytes32 cdfHash) = _stakeArrayToCdf(_newStakeArray);
        uint256 currentWindowId = _windowIdentifier(block.number);
        if (
            ps.cdfHashUpdateLog.length == 0
                || ps.cdfHashUpdateLog[ps.cdfHashUpdateLog.length - 1].windowId != currentWindowId
        ) {
            ps.cdfHashUpdateLog.push(CdfHashUpdateInfo({windowId: _windowIdentifier(block.number), cdfHash: cdfHash}));
        } else {
            ps.cdfHashUpdateLog[ps.cdfHashUpdateLog.length - 1].cdfHash = cdfHash;
        }

        emit StakeArrayUpdated(ps.stakeArrayHash);
        emit CdfArrayUpdated(cdfHash);
    }

    function getStakeArray() public view returns (uint32[] memory) {
        TAStorage storage ps = TAProxyStorage.getProxyStorage();

        uint256 length = ps.relayerCount;
        uint32[] memory stakeArray = new uint32[](length);
        for (uint256 i = 0; i < length;) {
            stakeArray[i] = (ps.relayerInfo[ps.relayerIndexToRelayer[i]].stake / STAKE_SCALING_FACTOR).toUint32();
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
        TAStorage storage ps = TAProxyStorage.getProxyStorage();

        if (_accounts.length == 0) {
            revert NoAccountsProvided();
        }
        if (_stake < MINIMUM_STAKE_AMOUNT) {
            revert InsufficientStake(_stake, MINIMUM_STAKE_AMOUNT);
        }

        RelayerInfo storage node = ps.relayerInfo[msg.sender];
        node.stake += _stake;
        node.endpoint = _endpoint;
        node.index = ps.relayerCount;
        for (uint256 i = 0; i < _accounts.length; i++) {
            node.isAccount[_accounts[i]] = true;
        }
        ps.relayerIndexToRelayer[node.index] = msg.sender;
        ++ps.relayerCount;

        // Update stake array and hash
        uint32[] memory newStakeArray = _appendStake(_previousStakeArray, _stake);
        _updateStakeAccounting(newStakeArray);

        // TODO: transfer stake amount to be stored in a vault.
        emit RelayerRegistered(msg.sender, _endpoint, _accounts, _stake);
    }

    /// @notice a relayer un unregister, which removes it from the relayer list and a delay for withdrawal is imposed on funds
    /// @param _previousStakeArray current stake array for verification
    function unRegister(uint32[] calldata _previousStakeArray) external verifyStakeArrayHash(_previousStakeArray) {
        TAStorage storage ps = TAProxyStorage.getProxyStorage();

        RelayerInfo storage node = ps.relayerInfo[msg.sender];
        uint256 n = ps.relayerCount - 1;
        uint256 stake = node.stake;
        uint256 nodeIndex = node.index;

        if (nodeIndex != n) {
            address lastRelayer = ps.relayerIndexToRelayer[n];
            ps.relayerIndexToRelayer[nodeIndex] = lastRelayer;
            ps.relayerInfo[lastRelayer].index = nodeIndex;
            ps.relayerIndexToRelayer[n] = address(0);
        }

        --ps.relayerCount;

        ps.withdrawalInfo[msg.sender] = WithdrawalInfo(stake, block.timestamp + ps.withdrawDelay);

        // Update stake percentages array and hash
        uint32[] memory newStakeArray = _removeStake(_previousStakeArray, nodeIndex);
        _updateStakeAccounting(newStakeArray);
        emit RelayerUnRegistered(msg.sender);
    }

    function withdraw(address relayer) external {
        TAStorage storage ps = TAProxyStorage.getProxyStorage();

        WithdrawalInfo memory w = ps.withdrawalInfo[relayer];
        if (!(w.amount > 0 && w.time < block.timestamp)) {
            revert InvalidWithdrawal(w.amount, w.time, 0, block.timestamp);
        }
        ps.withdrawalInfo[relayer] = WithdrawalInfo(0, 0);

        // todo: send w.amount to relayer

        emit Withdraw(relayer, w.amount);
    }

    function processAbsenceProof(
        // Reporter selection proof in current window
        uint16[] calldata _reporter_cdf,
        uint256 _reporter_cdfIndex,
        uint256[] calldata _reporter_relayerGenerationIterations,
        // Absentee selection proof in arbitrary past window
        address _absentee_relayerAddress,
        uint256 _absentee_blockNumber,
        uint256 _absentee_latestStakeUpdationCdfLogIndex,
        uint16[] calldata _absentee_cdf,
        uint256[] calldata _absentee_relayerGenerationIterations,
        uint256 _absentee_cdfIndex,
        // Other stuff
        uint32[] calldata _currentStakeArray
    ) public verifyCdfHash(_reporter_cdf) verifyStakeArrayHash(_currentStakeArray) {
        TAStorage storage ps = TAProxyStorage.getProxyStorage();
        uint256 gas = gasleft();
        address reporter_relayerAddress = msg.sender;

        if (
            !(_reporter_relayerGenerationIterations.length == 1)
                || !(_reporter_relayerGenerationIterations[0] == ABSENTEE_PROOF_REPORTER_GENERATION_ITERATION)
        ) {
            revert InvalidRelayerWindowForReporter();
        }

        // Verify Reporter Selection in Current Window
        if (
            !_verifyRelayerSelection(
                reporter_relayerAddress,
                _reporter_cdf,
                _reporter_cdfIndex,
                _reporter_relayerGenerationIterations,
                block.number
            )
        ) {
            revert InvalidRelayerWindowForReporter();
        }

        // Absentee block must not be in a point before the contract was deployed
        if (_absentee_blockNumber < ps.MIN_PENATLY_BLOCK_NUMBER) {
            revert InvalidAbsenteeBlockNumber();
        }

        // The Absentee block must not be in the current window
        uint256 currentWindowStartBlock = block.number - (block.number % ps.blocksWindow);
        if (_absentee_blockNumber >= currentWindowStartBlock) {
            revert InvalidAbsenteeBlockNumber();
        }

        // Verify CDF hash of the Absentee Window
        uint256 absentee_windowId = _windowIdentifier(_absentee_blockNumber);
        if (!_verifyPrevCdfHash(_absentee_cdf, absentee_windowId, _absentee_latestStakeUpdationCdfLogIndex)) {
            revert InvalidAbsenteeCdfArrayHash();
        }

        // Verify Relayer Selection in Absentee Window
        if (
            !_verifyRelayerSelection(
                _absentee_relayerAddress,
                _absentee_cdf,
                _absentee_cdfIndex,
                _absentee_relayerGenerationIterations,
                _absentee_blockNumber
            )
        ) {
            revert InvalidRelayeWindowForAbsentee();
        }

        // Verify Absence of the relayer
        if (ps.attendance[absentee_windowId][_absentee_relayerAddress]) {
            revert AbsenteeWasPresent(absentee_windowId);
        }

        emit GenericGasConsumed("Verification", gas - gasleft());
        gas = gasleft();

        // Process penalty
        uint256 penalty = (ps.relayerInfo[_absentee_relayerAddress].stake * ABSENCE_PENATLY) / 10000;
        uint32[] memory newStakeArray =
            _decreaseStake(_currentStakeArray, _absentee_cdfIndex, (penalty / STAKE_SCALING_FACTOR).toUint32());
        _updateStakeAccounting(newStakeArray);
        // TODO: Enable once funds are accepted in registration flow
        // _sendPenalty(reporter_relayerAddress, penalty);

        emit AbsenceProofProcessed(
            _windowIdentifier(block.number),
            msg.sender,
            _absentee_relayerAddress,
            _windowIdentifier(_absentee_blockNumber),
            penalty
            );

        emit GenericGasConsumed("Process Penalty", gas - gasleft());
    }

    function _sendPenalty(address _reporter, uint256 _amount) internal {
        (bool success,) = _reporter.call{value: _amount}("");
        if (!success) {
            revert ReporterTransferFailed(_reporter, _amount);
        }
    }
}
