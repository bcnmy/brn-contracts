// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import "test/base/TATestBase.sol";
import "ta-common/TAConstants.sol";
import "ta-transaction-allocation/interfaces/ITATransactionAllocationEventsErrors.sol";
import "ta-common/interfaces/ITAHelpers.sol";
import "mock/minimal-application/interfaces/IMinimalApplicationEventsErrors.sol";

contract TransactionAllocationTest is
    TATestBase,
    ITATransactionAllocationEventsErrors,
    ITAHelpers,
    IMinimalApplicationEventsErrors
{
    using FixedPointTypeHelper for FixedPointType;
    using Uint256WrapperHelper for uint256;

    bytes[] private txns;

    function setUp() public override {
        if (tx.gasprice == 0) {
            fail("Gas Price is 0. Please set it to 1 gwei or more.");
        }

        super.setUp();

        RelayerStateManager.RelayerState memory currentState = latestRelayerState;
        _registerAllNonFoundationRelayers();
        _moveForwardToNextEpoch();
        _sendEmptyTransaction(currentState);
        _moveForwardByWindows(deployParams.relayerStateUpdateDelayInWindows);

        for (uint256 i = 0; i < userCount; i++) {
            txns.push(abi.encodeCall(IMinimalApplication.executeMinimalApplication, (keccak256(abi.encodePacked(i)))));
        }
    }

    function _allocateTransactions(
        RelayerAddress _relayerAddress,
        bytes[] memory _txns,
        RelayerStateManager.RelayerState memory _relayerState
    ) internal view override returns (bytes[] memory, uint256, uint256) {
        return ta.allocateMinimalApplicationTransaction(_relayerAddress, _txns, _relayerState);
    }

    function testTransactionExecution() external {
        uint256 executionCount = 0;
        uint256 relayersSelected = 0;
        uint256 submissionCount = 0;

        for (uint256 i = 0; i < relayerMainAddress.length; i++) {
            RelayerAddress relayerAddress = relayerMainAddress[i];
            (bytes[] memory allotedTransactions, uint256 relayerGenerationIterations, uint256 selectedRelayerCdfIndex) =
                _allocateTransactions(relayerAddress, txns, latestRelayerState);

            if (allotedTransactions.length == 0) {
                continue;
            }

            relayersSelected += 1;

            _startPrankRAA(relayerAccountAddresses[relayerMainAddress[i]][0]);
            ta.execute(
                ITATransactionAllocation.ExecuteParams({
                    reqs: allotedTransactions,
                    forwardedNativeAmounts: new uint256[](allotedTransactions.length),
                    relayerIndex: selectedRelayerCdfIndex,
                    relayerGenerationIterationBitmap: relayerGenerationIterations,
                    activeState: latestRelayerState,
                    latestState: latestRelayerState
                })
            );
            vm.stopPrank();

            executionCount += allotedTransactions.length;
            submissionCount += _countSetBits(relayerGenerationIterations);
            assertEq(ta.transactionsSubmittedByRelayer(relayerAddress), _countSetBits(relayerGenerationIterations));
        }

        assertEq(executionCount, txns.length);
        assertEq(ta.count(), executionCount);
        assertEq(ta.totalTransactionsSubmitted(), submissionCount);
    }

    function testCannotCallApplicationDirectly() external {
        vm.expectRevert(IApplicationBase.ExternalCallsNotAllowed.selector);
        (bool status,) = address(ta).call(txns[0]);
        status;
    }

    function testCannotExecuteTransactionWithInvalidCdf() external {
        // Corrupt the CDF
        RelayerStateManager.RelayerState memory corruptedState = latestRelayerState;
        corruptedState.cdf[0] += 1;

        for (uint256 i = 0; i < relayerMainAddress.length; i++) {
            RelayerAddress relayerAddress = relayerMainAddress[i];
            (bytes[] memory allotedTransactions, uint256 relayerGenerationIterations, uint256 selectedRelayerCdfIndex) =
                _allocateTransactions(relayerAddress, txns, latestRelayerState);

            if (allotedTransactions.length == 0) {
                continue;
            }

            _startPrankRAA(relayerAccountAddresses[relayerMainAddress[i]][0]);
            vm.expectRevert(InvalidActiveRelayerState.selector);
            ta.execute(
                ITATransactionAllocation.ExecuteParams({
                    reqs: allotedTransactions,
                    forwardedNativeAmounts: new uint256[](allotedTransactions.length),
                    relayerIndex: selectedRelayerCdfIndex,
                    relayerGenerationIterationBitmap: relayerGenerationIterations,
                    activeState: corruptedState,
                    latestState: latestRelayerState
                })
            );
            vm.stopPrank();
        }
    }

    function testCannotCallExecuteMultipleTimesInTheSameWindow() external {
        for (uint256 i = 0; i < relayerMainAddress.length; i++) {
            RelayerAddress relayerAddress = relayerMainAddress[i];
            (bytes[] memory allotedTransactions, uint256 relayerGenerationIterations, uint256 selectedRelayerCdfIndex) =
                _allocateTransactions(relayerAddress, txns, latestRelayerState);

            if (allotedTransactions.length == 0) {
                continue;
            }

            _startPrankRAA(relayerAccountAddresses[relayerMainAddress[i]][0]);
            ta.execute(
                ITATransactionAllocation.ExecuteParams({
                    reqs: allotedTransactions,
                    forwardedNativeAmounts: new uint256[](allotedTransactions.length),
                    relayerIndex: selectedRelayerCdfIndex,
                    relayerGenerationIterationBitmap: relayerGenerationIterations,
                    activeState: latestRelayerState,
                    latestState: latestRelayerState
                })
            );
            vm.expectRevert(
                abi.encodeWithSelector(
                    RelayerAlreadySubmittedTransaction.selector, relayerAddress, ta.debug_currentWindowIndex()
                )
            );
            ta.execute(
                ITATransactionAllocation.ExecuteParams({
                    reqs: allotedTransactions,
                    forwardedNativeAmounts: new uint256[](allotedTransactions.length),
                    relayerIndex: selectedRelayerCdfIndex,
                    relayerGenerationIterationBitmap: relayerGenerationIterations,
                    activeState: latestRelayerState,
                    latestState: latestRelayerState
                })
            );
            vm.stopPrank();
        }
    }

    function testCannotExecuteTransactionFromUnselectedRelayer() external {
        for (uint256 i = 0; i < relayerMainAddress.length; i++) {
            RelayerAddress relayerAddress = relayerMainAddress[i];
            (bytes[] memory allotedTransactions, uint256 relayerGenerationIterations, uint256 selectedRelayerCdfIndex) =
                _allocateTransactions(relayerAddress, txns, latestRelayerState);

            if (allotedTransactions.length == 0) {
                continue;
            }

            uint256 testRelayerIndex = (i + 1) % relayerMainAddress.length;

            _startPrankRAA(relayerAccountAddresses[relayerMainAddress[testRelayerIndex]][0]);
            vm.expectRevert(RelayerIndexDoesNotPointToSelectedCdfInterval.selector);
            ta.execute(
                ITATransactionAllocation.ExecuteParams({
                    reqs: allotedTransactions,
                    forwardedNativeAmounts: new uint256[](allotedTransactions.length),
                    relayerIndex: selectedRelayerCdfIndex + 1,
                    relayerGenerationIterationBitmap: relayerGenerationIterations,
                    activeState: latestRelayerState,
                    latestState: latestRelayerState
                })
            );
            vm.stopPrank();
        }
    }

    function testCannotExecuteTransactionFromSelectedButNotAllotedRelayer() external {
        (RelayerAddress[] memory selectedRelayers,) = ta.allocateRelayers(latestRelayerState);
        bool testRun = false;

        bytes[] memory allotedTransactions;

        for (uint256 i = 0; i < relayerMainAddress.length; i++) {
            RelayerAddress relayerAddress = relayerMainAddress[i];
            (bytes[] memory _allotedTransactions, uint256 relayerGenerationIterations, uint256 selectedRelayerIndex) =
                _allocateTransactions(relayerAddress, txns, latestRelayerState);

            if (_allotedTransactions.length == 0) {
                continue;
            }

            if (allotedTransactions.length == 0) {
                allotedTransactions = _allotedTransactions;
                continue;
            }

            if (selectedRelayers[0] == relayerAddress) {
                continue;
            }

            testRun = true;

            _startPrankRAA(relayerAccountAddresses[relayerAddress][0]);
            vm.expectRevert(
                abi.encodeWithSelector(
                    TransactionExecutionFailed.selector,
                    0,
                    abi.encodeWithSelector(IApplicationBase.RelayerNotAssignedToTransaction.selector)
                )
            );
            ta.execute(
                ITATransactionAllocation.ExecuteParams({
                    reqs: allotedTransactions,
                    forwardedNativeAmounts: new uint256[](allotedTransactions.length),
                    relayerIndex: selectedRelayerIndex,
                    relayerGenerationIterationBitmap: relayerGenerationIterations,
                    activeState: latestRelayerState,
                    latestState: latestRelayerState
                })
            );
            vm.stopPrank();
        }

        assertEq(testRun, true);
    }

    function testCannotExecuteTransactionFromWithIncorrectForwardedNativeAmount() external {
        for (uint256 i = 0; i < relayerMainAddress.length; i++) {
            RelayerAddress relayerAddress = relayerMainAddress[i];
            (bytes[] memory allotedTransactions, uint256 relayerGenerationIterations, uint256 selectedRelayerCdfIndex) =
                _allocateTransactions(relayerAddress, txns, latestRelayerState);

            if (allotedTransactions.length == 0) {
                continue;
            }

            uint256 testRelayerIndex = (i + 1) % relayerMainAddress.length;

            _startPrankRAA(relayerAccountAddresses[relayerMainAddress[testRelayerIndex]][0]);
            vm.expectRevert(ParameterLengthMismatch.selector);
            ta.execute(
                ITATransactionAllocation.ExecuteParams({
                    reqs: allotedTransactions,
                    forwardedNativeAmounts: new uint256[](allotedTransactions.length + 1),
                    relayerIndex: selectedRelayerCdfIndex + 1,
                    relayerGenerationIterationBitmap: relayerGenerationIterations,
                    activeState: latestRelayerState,
                    latestState: latestRelayerState
                })
            );
            vm.stopPrank();
        }
    }
}
