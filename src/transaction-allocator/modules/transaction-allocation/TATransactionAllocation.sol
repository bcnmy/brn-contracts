// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import "src/transaction-allocator/common/TAStructs.sol";
import "src/transaction-allocator/common/TAHelpers.sol";
import "src/transaction-allocator/common/TATypes.sol";
import "./interfaces/ITATransactionAllocation.sol";
import "./TATransactionAllocationStorage.sol";
import "../relayer-management/TARelayerManagementStorage.sol";

import "forge-std/console.sol";

contract TATransactionAllocation is ITATransactionAllocation, TAHelpers, TATransactionAllocationStorage {
    function _getHashedModIndex(bytes calldata _calldata) internal view returns (uint256 relayerIndex) {
        RMStorage storage ds = getRMStorage();
        relayerIndex = uint256(keccak256(abi.encodePacked(_calldata))) % ds.relayersPerWindow;
    }

    /// @notice returns true if the current sender is allowed to relay transaction in this block
    function _verifyTransactionAllocation(
        Transaction[] calldata _txs,
        uint16[] calldata _cdf,
        uint256 _cdfUpdationLogIndex,
        uint256 _cdfIndex,
        uint256 _relayerIndexUpdationLogIndex,
        uint256[] calldata _relayerGenerationIterations,
        uint256 _blockNumber
    ) internal view returns (bool) {
        if (
            !_verifyRelayerSelection(
                msg.sender,
                _cdf,
                _cdfUpdationLogIndex,
                _cdfIndex,
                _relayerIndexUpdationLogIndex,
                _relayerGenerationIterations,
                _blockNumber
            )
        ) {
            return false;
        }

        // Store all relayerGenerationIterations in a bitmap to efficiently check for existence in _relayerGenerationIteration
        // ASSUMPTION: Max no. of iterations required to generate 'relayersPerWindow' unique relayers <= 256
        uint256 bitmap = 0;
        uint256 length = _relayerGenerationIterations.length;
        for (uint256 i = 0; i < length;) {
            bitmap |= (1 << _relayerGenerationIterations[i]);
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
    function _executeTx(Transaction calldata _req, uint256 _index)
        internal
        returns (
            bool, /* success */
            bool, /* refundSuccess */
            bytes memory, /* returndata */
            uint256, /* totalGasConsumed */
            uint256, /* relayerPayment */
            uint256, /* premiumsGenerated */
            TokenAddress /* paymentTokenAddress */
        )
    {
        uint256 gas = gasleft();
        uint256 preExecutionGas = gasleft();

        // TODO: Non native token support
        // TODO: Study ERC4337 EP implementation to get any insights on this process

        uint256 expectedGasConsumed = _req.gasLimit + _req.prePaymentGasLimit + _req.fixedGas + _req.refundGasLimit;
        uint256 gasPremium = expectedGasConsumed * RELAYER_PREMIUM_PERCENTAGE / (100 * PERCENTAGE_MULTIPLIER);
        TokenAddress paymentTokenAddress;

        // Ask the application to prepay gas
        uint256 prePayment = address(this).balance;
        uint256 relayerRefund = 0;
        try _req.to.prepayGas{gas: _req.prePaymentGasLimit}(_req, expectedGasConsumed + gasPremium) returns (
            address _paymentTokenAddress
        ) {
            uint256 expectedPrepayment = (expectedGasConsumed + gasPremium) * tx.gasprice;
            paymentTokenAddress = TokenAddress.wrap(_paymentTokenAddress);

            if (!getRMStorage().isGasTokenSupported[paymentTokenAddress]) {
                return (
                    false,
                    false,
                    abi.encodeWithSelector(GasTokenNotSuported.selector, paymentTokenAddress),
                    gas - gasleft(),
                    0,
                    0,
                    paymentTokenAddress
                );
            }

            // TODO: Non native token support
            prePayment = address(this).balance - prePayment;
            if (prePayment != expectedPrepayment) {
                return (
                    false,
                    false,
                    abi.encodeWithSelector(InsufficientPrepayment.selector, expectedPrepayment, prePayment),
                    gas - gasleft(),
                    prePayment,
                    0,
                    paymentTokenAddress
                );
            }
            relayerRefund = prePayment - gasPremium * tx.gasprice;
            emit PrepaymentReceived(_index, prePayment, paymentTokenAddress);
        } catch (bytes memory reason) {
            return (
                false,
                false,
                abi.encodeWithSelector(PrepaymentFailed.selector, reason),
                gas - gasleft(),
                0,
                0,
                TokenAddress.wrap(address(0))
            );
        }

        emit GenericGasConsumed("PrepaymentGas", gas - gasleft());
        gas = gasleft();

        // Execute the transaction
        (bool success, bytes memory returndata) = address(_req.to).call{gas: _req.gasLimit}(_req.data);

        emit GenericGasConsumed("ExecutionGas", gas - gasleft());
        gas = gasleft();

        // Refund the excess gas if needed
        uint256 actualGasConsumed = preExecutionGas - gasleft() + _req.fixedGas + gasPremium + _req.refundGasLimit;
        bool refundSuccess;
        if (expectedGasConsumed > actualGasConsumed) {
            uint256 refundAmount = (expectedGasConsumed - actualGasConsumed) * tx.gasprice;

            try _req.to.refundGas{value: refundAmount, gas: _req.refundGasLimit}() {
                refundSuccess = true;
                relayerRefund -= refundAmount;
                emit GasFeeRefunded(_index, expectedGasConsumed, actualGasConsumed, paymentTokenAddress);
            } catch (bytes memory reason) {
                returndata = abi.encodeWithSelector(GasFeeRefundFailed.selector, reason);
                return (
                    success,
                    refundSuccess,
                    returndata,
                    gas - gasleft(),
                    relayerRefund,
                    gasPremium * tx.gasprice,
                    paymentTokenAddress
                );
            }
        }

        emit GenericGasConsumed("RefundGas", gas - gasleft());

        return (
            success,
            refundSuccess,
            returndata,
            gas - gasleft(),
            relayerRefund,
            gasPremium * tx.gasprice,
            paymentTokenAddress
        );
    }

    /// @notice allows relayer to execute a tx on behalf of a client
    /// @param _reqs requested txs to be forwarded
    /// @param _relayerGenerationIterations index at which relayer was selected
    /// @param _cdfIndex index of relayer in cdf
    // TODO: can we decrease calldata cost by using merkle proofs or square root decomposition?
    // TODO: Non Reentrant?
    // TODO: check if _cdfIndex is needed, since it's always going to be relayer.index
    function execute(
        Transaction[] calldata _reqs,
        uint16[] calldata _cdf,
        uint256[] calldata _relayerGenerationIterations,
        uint256 _cdfIndex,
        uint256 _currentCdfLogIndex,
        uint256 _relayerIndexUpdationLogIndex
    ) public override returns (bool[] memory successes, bytes[] memory returndatas) {
        uint256 gasLeft = gasleft();
        if (
            !_verifyTransactionAllocation(
                _reqs,
                _cdf,
                _currentCdfLogIndex,
                _cdfIndex,
                _relayerIndexUpdationLogIndex,
                _relayerGenerationIterations,
                block.number
            )
        ) {
            revert InvalidRelayerWindow();
        }
        emit GenericGasConsumed("VerificationGas", gasLeft - gasleft());
        gasLeft = gasleft();

        uint256 length = _reqs.length;
        uint256 totalGas = 0;
        // TODO: Non native token support
        uint256 totalRefund = 0;
        uint256 totalPremiums = 0;

        successes = new bool[](length);
        returndatas = new bytes[](length);

        // Execute all transactions
        for (uint256 i = 0; i < length;) {
            Transaction calldata _req = _reqs[i];

            // TODO: Relayer Premiums and relayer refund
            (
                bool success,
                bool refundSuccess,
                bytes memory returndata,
                uint256 totalGasConsumed,
                uint256 relayerRefund,
                uint256 premiumsGenerated,
            ) = _executeTx(_req, i);

            emit TransactionStatus(
                i, success, refundSuccess, returndata, totalGasConsumed, relayerRefund, premiumsGenerated
            );

            successes[i] = success;
            returndatas[i] = returndata;
            totalGas += totalGasConsumed;

            if (refundSuccess) {
                totalRefund += relayerRefund;
                totalPremiums += premiumsGenerated;
            }

            unchecked {
                ++i;
            }
        }

        gasLeft = gasleft();
        TAStorage storage ts = getTAStorage();
        RMStorage storage ds = getRMStorage();

        // Mark Attendance
        RelayerIndexToRelayerUpdateInfo[] storage updateInfo = ds.relayerIndexToRelayerUpdationLog[_cdfIndex];
        RelayerAddress relayerAddress = updateInfo[updateInfo.length - 1].relayerAddress;
        ts.attendance[_windowIndex(block.number)][relayerAddress] = true;

        // Split the premiums b/w the relayer and the delegator
        uint256 delegatorPremiums =
            totalPremiums * ds.relayerInfo[relayerAddress].delegatorPoolPremiumShare / (100 * PERCENTAGE_MULTIPLIER);

        // Refund the relayer. TODO: Non native token support
        _transfer(NATIVE_TOKEN, msg.sender, totalRefund + (totalPremiums - delegatorPremiums));

        // Add the premiums to the delegator pool
        _addDelegatorRewards(relayerAddress, NATIVE_TOKEN, delegatorPremiums);

        emit GenericGasConsumed("OtherOverhead", gasLeft - gasleft());

        // TODO: Check how to update this logic
        // Validate that the relayer has sent enough gas for the call.
        // if (gasleft() <= totalGas / 63) {
        //     assembly {
        //         invalid()
        //     }
        // }

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
        returns (RelayerAddress[] memory, uint256[] memory)
    {
        RMStorage storage ds = getRMStorage();

        if (!_verifyCdfHashAtWindow(_cdf, _windowIndex(block.number), _currentCdfLogIndex)) {
            revert InvalidCdfArrayHash();
        }

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

            // Find the relayer address corresponding to the cdf index
            RelayerIndexToRelayerUpdateInfo[] storage updateInfo = ds.relayerIndexToRelayerUpdationLog[cdfIndex[i]];
            RelayerAddress relayerAddress;
            for (uint256 j = updateInfo.length - 1; j >= 0;) {
                if (_verifyRelayerUpdationLogIndexAtBlock(cdfIndex[i], block.number, j)) {
                    relayerAddress = updateInfo[j].relayerAddress;
                    break;
                }

                if (j == 0) {
                    revert UnknownError();
                }

                unchecked {
                    --j;
                }
            }

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
        returns (Transaction[] memory, uint256[] memory, uint256)
    {
        (RelayerAddress[] memory relayersAllocated, uint256[] memory relayerStakePrefixSumIndex) =
            allocateRelayers(_data.cdf, _data.currentCdfLogIndex);
        if (relayersAllocated.length != getRMStorage().relayersPerWindow) {
            revert RelayerAllocationResultLengthMismatch(getRMStorage().relayersPerWindow, relayersAllocated.length);
        }

        // Filter the transactions
        uint256 selectedRelayerCdfIndex;
        Transaction[] memory txnAllocated = new Transaction[](_data.requests.length);
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
