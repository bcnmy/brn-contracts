// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import "src/transaction-allocator/common/TAStructs.sol";
import "src/transaction-allocator/common/TAHelpers.sol";
import "src/transaction-allocator/common/TATypes.sol";
import "./interfaces/ITATransactionAllocation.sol";
import "./TATransactionAllocationStorage.sol";
import "../relayer-management/TARelayerManagementStorage.sol";

contract TATransactionAllocation is ITATransactionAllocation, TAHelpers, TATransactionAllocationStorage {
    function _getHashedModIndex(bytes calldata _calldata) internal view returns (uint256 relayerIndex) {
        RMStorage storage ds = getRMStorage();
        relayerIndex = uint256(keccak256(abi.encodePacked(_calldata))) % ds.relayersPerWindow;
    }

    /// @notice returns true if the current sender is allowed to relay transaction in this block
    function _verifyTransactionAllocation(
        uint16[] calldata _cdf,
        uint256 _cdfIndex,
        uint256[] calldata _relayerGenerationIteration,
        uint256 _blockNumber,
        ForwardRequest[] calldata _txs
    ) internal view returns (bool) {
        RMStorage storage ds = getRMStorage();

        if (
            !_verifyRelayerSelection(
                msg.sender,
                _cdf,
                _cdfIndex,
                _relayerGenerationIteration,
                _blockNumber,
                ds.relayerIndexToRelayerUpdationLog[_cdfIndex].length - 1
            )
        ) {
            return false;
        }

        // Store all relayerGenerationIterations in a bitmap to efficiently check for existence in _relayerGenerationIteration
        // ASSUMPTION: Max no. of iterations required to generate 'relayersPerWindow' unique relayers <= 256
        uint256 bitmap = 0;
        uint256 length = _relayerGenerationIteration.length;
        for (uint256 i = 0; i < length;) {
            bitmap |= (1 << _relayerGenerationIteration[i]);
            unchecked {
                ++i;
            }
        }

        // Verify if the transaction was alloted to the relayer
        length = _txs.length;
        for (uint256 i = 0; i < length;) {
            uint256 relayerGenerationIteration = _getHashedModIndex(_txs[i].data);
            if ((bitmap & (1 << relayerGenerationIteration)) == 0) {
                return false;
            }
            unchecked {
                ++i;
            }
        }

        return true;
    }

    ///////////////////////////////// Transaction Execution ///////////////////////////////
    function _executeTx(ForwardRequest calldata _req) internal returns (bool, bytes memory, uint256) {
        uint256 gas = gasleft();

        (bool success, bytes memory returndata) = _req.to.call{gas: _req.gasLimit}(_req.data);
        uint256 executionGas = gas - gasleft();
        emit GenericGasConsumed("executionGas", executionGas);

        // TODO: Verify reimbursement and forward to relayer
        return (success, returndata, executionGas);
    }

    /// @notice allows relayer to execute a tx on behalf of a client
    /// @param _reqs requested txs to be forwarded
    /// @param _relayerGenerationIterations index at which relayer was selected
    /// @param _cdfIndex index of relayer in cdf
    // TODO: can we decrease calldata cost by using merkle proofs or square root decomposition?
    // TODO: Non Reentrant?
    // TODO: Why payable? to save gas?
    function execute(
        ForwardRequest[] calldata _reqs,
        uint16[] calldata _cdf,
        uint256[] calldata _relayerGenerationIterations,
        uint256 _cdfIndex,
        uint256 _currentCdfLogIndex
    ) public override returns (bool[] memory successes, bytes[] memory returndatas) {
        uint256 gasLeft = gasleft();
        if (!_verifyCdfHashAtWindow(_cdf, _windowIndex(block.number), _currentCdfLogIndex)) {
            revert InvalidCdfArrayHash();
        }
        if (!_verifyTransactionAllocation(_cdf, _cdfIndex, _relayerGenerationIterations, block.number, _reqs)) {
            revert InvalidRelayerWindow();
        }
        emit GenericGasConsumed("VerificationGas", gasLeft - gasleft());
        gasLeft = gasleft();

        // Execute all transactions
        uint256 length = _reqs.length;
        uint256 totalGas = 0;
        successes = new bool[](length);
        returndatas = new bytes[](length);
        for (uint256 i = 0; i < length;) {
            ForwardRequest calldata _req = _reqs[i];

            (bool success, bytes memory returndata, uint256 executionGas) = _executeTx(_req);

            successes[i] = success;
            returndatas[i] = returndata;
            totalGas += executionGas;

            unchecked {
                ++i;
            }
        }

        // Validate that the relayer has sent enough gas for the call.
        if (gasleft() <= totalGas / 63) {
            assembly {
                invalid()
            }
        }
        emit GenericGasConsumed("ExecutionGas", gasLeft - gasleft());

        gasLeft = gasleft();
        TAStorage storage ts = getTAStorage();
        RMStorage storage ds = getRMStorage();

        // Mark Attendance
        RelayerIndexToRelayerUpdateInfo[] storage updateInfo = ds.relayerIndexToRelayerUpdationLog[_cdfIndex];
        RelayerAddress relayerAddress = updateInfo[updateInfo.length - 1].relayerAddress;
        ts.attendance[_windowIndex(block.number)][relayerAddress] = true;
        emit GenericGasConsumed("OtherOverhead", gasLeft - gasleft());

        return (successes, returndatas);
    }

    /////////////////////////////// Allocation Helpers ///////////////////////////////
    function _lowerBound(uint16[] calldata arr, uint256 target) internal pure returns (uint256) {
        uint256 low = 0;
        uint256 high = arr.length;
        unchecked {
            while (low < high) {
                uint256 mid = (low + high) / 2;
                if (arr[mid] < target) {
                    low = mid + 1;
                } else {
                    high = mid;
                }
            }
        }
        return low;
    }

    /// @notice Given a block number, the function generates a list of pseudo-random relayers
    ///         for the window of which the block in a part of. The generated list of relayers
    ///         is pseudo-random but deterministic
    /// @return selectedRelayers list of relayers selected of length relayersPerWindow, but
    ///                          there can be duplicates
    /// @return cdfIndex list of indices of the selected relayers in the cdf, used for verification
    function allocateRelayers(uint16[] calldata _cdf, uint256 _currentCdfLogIndex)
        public
        view
        override
        verifyCdfHashAtWindow(_cdf, _windowIndex(block.number), _currentCdfLogIndex)
        returns (RelayerAddress[] memory, uint256[] memory)
    {
        RMStorage storage ds = getRMStorage();

        if (_cdf.length == 0) {
            revert NoRelayersRegistered();
        }

        // Generate `relayersPerWindow` pseudo-random distinct relayers
        RelayerAddress[] memory selectedRelayers = new RelayerAddress[](ds.relayersPerWindow);
        uint256[] memory cdfIndex = new uint256[](ds.relayersPerWindow);

        uint256 cdfLength = _cdf.length;
        if (_cdf[cdfLength - 1] == 0) {
            revert NoRelayersRegistered();
        }

        for (uint256 i = 0; i < ds.relayersPerWindow;) {
            uint256 randomCdfNumber = _randomCdfNumber(block.number, i, _cdf[cdfLength - 1]);
            cdfIndex[i] = _lowerBound(_cdf, randomCdfNumber);
            RelayerIndexToRelayerUpdateInfo[] storage updateInfo = ds.relayerIndexToRelayerUpdationLog[cdfIndex[i]];
            RelayerAddress relayerAddress = updateInfo[updateInfo.length - 1].relayerAddress;
            selectedRelayers[i] = relayerAddress;
            unchecked {
                ++i;
            }
        }
        return (selectedRelayers, cdfIndex);
    }

    /// @notice determine what transactions can be relayed by the sender
    /// @param _data data for the allocation
    /// @return relayerGenerationIteration list of iterations of the relayer generation corresponding
    ///                                    to the selected transactions
    /// @return selectedRelayersCdfIndex index of the selected relayer in the cdf
    function allocateTransaction(AllocateTransactionParams calldata _data)
        external
        view
        override
        verifyCdfHashAtWindow(_data.cdf, _windowIndex(block.number), _data.currentCdfLogIndex)
        returns (ForwardRequest[] memory, uint256[] memory, uint256)
    {
        (RelayerAddress[] memory relayersAllocated, uint256[] memory relayerStakePrefixSumIndex) =
            allocateRelayers(_data.cdf, _data.currentCdfLogIndex);
        if (relayersAllocated.length != getRMStorage().relayersPerWindow) {
            revert RelayerAllocationResultLengthMismatch(getRMStorage().relayersPerWindow, relayersAllocated.length);
        }

        // Filter the transactions
        uint256 selectedRelayerCdfIndex;
        ForwardRequest[] memory txnAllocated = new ForwardRequest[](_data.requests.length);
        uint256[] memory relayerGenerationIteration = new uint256[](
            _data.requests.length
        );
        uint256 j;
        for (uint256 i = 0; i < _data.requests.length;) {
            // If the transaction can be processed by this relayer, store it's info
            uint256 relayerIndex = _getHashedModIndex(_data.requests[i].data);
            if (relayersAllocated[relayerIndex] == _data.relayerAddress) {
                relayerGenerationIteration[j] = relayerIndex;
                txnAllocated[j] = _data.requests[i];
                selectedRelayerCdfIndex = relayerStakePrefixSumIndex[relayerIndex];
                unchecked {
                    ++j;
                }
            }

            unchecked {
                ++i;
            }
        }

        // Reduce the array sizes if needed
        uint256 extraLength = _data.requests.length - j;
        assembly {
            mstore(txnAllocated, sub(mload(txnAllocated), extraLength))
            mstore(relayerGenerationIteration, sub(mload(relayerGenerationIteration), extraLength))
        }

        return (txnAllocated, relayerGenerationIteration, selectedRelayerCdfIndex);
    }

    ////////////////////////// Getters //////////////////////////

    function attendance(uint256 _windowIndex, RelayerAddress _relayerAddress) external view override returns (bool) {
        return getTAStorage().attendance[_windowIndex][_relayerAddress];
    }
}
