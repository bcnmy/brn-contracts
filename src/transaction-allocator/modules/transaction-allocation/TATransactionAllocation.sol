// SPDX-License-Identifier: MIT

pragma solidity 0.8.17;

import "./interfaces/ITATransactionAllocation.sol";
import "./TATransactionAllocationStorage.sol";
import "../relayer-management/TARelayerManagementStorage.sol";
import "../../common/TAHelpers.sol";

import "src/structs/Transaction.sol";
import "src/structs/TAStructs.sol";

contract TATransactionAllocation is ITATransactionAllocation, TAHelpers, TATransactionAllocationStorage {
    function _assignRelayer(bytes calldata _calldata) internal view returns (uint256 relayerIndex) {
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
        if (!_verifyRelayerSelection(msg.sender, _cdf, _cdfIndex, _relayerGenerationIteration, _blockNumber)) {
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
            uint256 relayerGenerationIteration = _assignRelayer(_txs[i].data);
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
    function execute(
        ForwardRequest[] calldata _reqs,
        uint16[] calldata _cdf,
        uint256[] calldata _relayerGenerationIterations,
        uint256 _cdfIndex
    ) public payable returns (bool[] memory, bytes[] memory) {
        RMStorage storage ds = getRMStorage();
        TAStorage storage ts = getTAStorage();

        uint256 gasLeft = gasleft();
        if (!_verifyLatestCdfHash(_cdf)) {
            revert InvalidCdfArrayHash();
        }
        if (!_verifyTransactionAllocation(_cdf, _cdfIndex, _relayerGenerationIterations, block.number, _reqs)) {
            revert InvalidRelayerWindow();
        }
        emit GenericGasConsumed("VerificationGas", gasLeft - gasleft());

        gasLeft = gasleft();

        uint256 length = _reqs.length;
        uint256 totalGas = 0;
        bool[] memory successes = new bool[](length);
        bytes[] memory returndatas = new bytes[](length);

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
        ts.attendance[_windowIdentifier(block.number)][ds.relayerIndexToRelayer[_cdfIndex]] = true;
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
    /// @param _blockNumber block number for which the relayers are to be generated
    /// @return selectedRelayers list of relayers selected of length relayersPerWindow, but
    ///                          there can be duplicates
    /// @return cdfIndex list of indices of the selected relayers in the cdf, used for verification
    function allocateRelayers(uint256 _blockNumber, uint16[] calldata _cdf)
        public
        view
        verifyCdfHash(_cdf)
        returns (address[] memory, uint256[] memory)
    {
        RMStorage storage ds = getRMStorage();

        if (_cdf.length == 0) {
            revert NoRelayersRegistered();
        }
        if (ds.relayerCount < ds.relayersPerWindow) {
            revert InsufficientRelayersRegistered();
        }
        if (_blockNumber == 0) {
            _blockNumber = block.number;
        }

        // Generate `relayersPerWindow` pseudo-random distinct relayers
        address[] memory selectedRelayers = new address[](ds.relayersPerWindow);
        uint256[] memory cdfIndex = new uint256[](ds.relayersPerWindow);

        uint256 cdfLength = _cdf.length;
        if (_cdf[cdfLength - 1] == 0) {
            revert NoRelayersRegistered();
        }

        for (uint256 i = 0; i < ds.relayersPerWindow;) {
            uint256 randomCdfNumber = _randomCdfNumber(_blockNumber, i, _cdf[cdfLength - 1]);
            cdfIndex[i] = _lowerBound(_cdf, randomCdfNumber);
            RelayerInfo storage relayer = ds.relayerInfo[ds.relayerIndexToRelayer[cdfIndex[i]]];
            uint256 relayerIndex = relayer.index;
            address relayerAddress = ds.relayerIndexToRelayer[relayerIndex];
            selectedRelayers[i] = relayerAddress;

            unchecked {
                ++i;
            }
        }
        return (selectedRelayers, cdfIndex);
    }

    /// @notice determine what transactions can be relayed by the sender
    /// @param _relayer Address of the relayer to allocate transactions for
    /// @param _blockNumber block number for which the relayers are to be generated
    /// @param _txnCalldata list with all transactions calldata to be filtered
    /// @return txnAllocated list of transactions that can be relayed by the relayer
    /// @return relayerGenerationIteration list of iterations of the relayer generation corresponding
    ///                                    to the selected transactions
    /// @return selectedRelayersCdfIndex index of the selected relayer in the cdf
    function allocateTransaction(
        address _relayer,
        uint256 _blockNumber,
        bytes[] calldata _txnCalldata,
        uint16[] calldata _cdf
    ) public view verifyCdfHash(_cdf) returns (bytes[] memory, uint256[] memory, uint256) {
        RMStorage storage ds = getRMStorage();

        if (_blockNumber == 0) {
            _blockNumber = block.number;
        }

        (address[] memory relayersAllocated, uint256[] memory relayerStakePrefixSumIndex) =
            allocateRelayers(_blockNumber, _cdf);
        if (relayersAllocated.length != ds.relayersPerWindow) {
            revert RelayerAllocationResultLengthMismatch(ds.relayersPerWindow, relayersAllocated.length);
        }

        // Filter the transactions
        uint256 selectedRelayerCdfIndex;
        bytes[] memory txnAllocated = new bytes[](_txnCalldata.length);
        uint256[] memory relayerGenerationIteration = new uint256[](
            _txnCalldata.length
        );
        uint256 j;

        // Filter the transactions
        for (uint256 i = 0; i < _txnCalldata.length;) {
            uint256 relayerIndex = _assignRelayer(_txnCalldata[i]);
            address relayerAddress = relayersAllocated[relayerIndex];
            RelayerInfo storage node = ds.relayerInfo[relayerAddress];

            // If the transaction can be processed by this relayer, store it's info
            if (node.isAccount[_relayer] || relayerAddress == _relayer) {
                relayerGenerationIteration[j] = relayerIndex;
                txnAllocated[j] = _txnCalldata[i];
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
        uint256 extraLength = _txnCalldata.length - j;
        assembly {
            mstore(txnAllocated, sub(mload(txnAllocated), extraLength))
            mstore(relayerGenerationIteration, sub(mload(relayerGenerationIteration), extraLength))
        }

        return (txnAllocated, relayerGenerationIteration, selectedRelayerCdfIndex);
    }

    ////////////////////////// Getters //////////////////////////

    function attendance(uint256 _windowIndex, address _relayer) external view override returns (bool) {
        return getTAStorage().attendance[_windowIndex][_relayer];
    }
}
