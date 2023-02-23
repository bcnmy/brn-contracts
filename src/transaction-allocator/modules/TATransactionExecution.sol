// SPDX-License-Identifier: MIT

pragma solidity 0.8.17;

import "../common/TAVerificationUtils.sol";
import "../../library/TAProxyStorage.sol";
import "../../interfaces/ITATransactionExecution.sol";

contract TATransactionExecution is TAVerificationUtils, ITATransactionExecution {
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
        TAStorage storage ps = TAProxyStorage.getProxyStorage();

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
        ps.attendance[_windowIdentifier(block.number)][ps.relayerIndexToRelayer[_cdfIndex]] = true;
        emit GenericGasConsumed("OtherOverhead", gasLeft - gasleft());

        return (successes, returndatas);
    }
}
