// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import "test/base/TATestBase.sol";
import "ta-transaction-allocation/interfaces/ITATransactionAllocationEventsErrors.sol";
import "ta-relayer-management/interfaces/ITARelayerManagementEventsErrors.sol";
import "ta-common/interfaces/ITAHelpers.sol";
import "mock/minimal-application/interfaces/IMinimalApplicationEventsErrors.sol";

contract RelayerLivenessAndJailingTest is
    TATestBase,
    ITATransactionAllocationEventsErrors,
    ITARelayerManagementEventsErrors,
    ITAHelpers,
    IMinimalApplicationEventsErrors
{
    using FixedPointTypeHelper for FixedPointType;
    using Uint256WrapperHelper for uint256;

    uint256 constant initialApplicationFunds = 10 ether;

    mapping(RelayerAddress => uint256) penalty;

    function setUp() public override {
        if (tx.gasprice == 0) {
            fail("Gas Price is 0. Please set it to 1 gwei or more.");
        }

        super.setUp();

        RelayerState memory currentState = latestRelayerState;
        _registerAllNonFoundationRelayers();
        _moveForwardToNextEpoch();
        _sendEmptyTransaction(currentState);
        _moveForwardByWindows(deployParams.relayerStateUpdateDelayInWindows);
    }

    function testMinimumTransactionForLivenessCalculation() external {
        FixedPointType minTransactions = ta.calculateMinimumTranasctionsForLiveness(
            10 ** 18, 2 * 10 ** 18, uint256(50).fp(), ta.livenessZParameter()
        );
        assertEq(minTransactions.u256(), 13);

        minTransactions = ta.calculateMinimumTranasctionsForLiveness(
            10 ** 18, 5 * 10 ** 18, uint256(50).fp(), ta.livenessZParameter()
        );
        assertEq(minTransactions.u256(), 0);
    }

    function testPenalizeActiveRelayerIfInsufficientTransactionAreSubmitted() external {
        RelayerAddress activeRelayer = relayerMainAddress[0];
        ta.debug_setTotalTransactionsProcessed(1000);
        ta.debug_setTransactionsProcessedByRelayer(activeRelayer, 100);
        uint256 totalStake = ta.totalStake();
        uint256 totalPenaly = 0;

        RelayerState memory currentState = latestRelayerState;

        for (uint256 i = 1; i < relayerCount; ++i) {
            RelayerAddress relayer = relayerMainAddress[i];

            uint256 stake = ta.relayerInfo(relayer).stake;
            penalty[relayer] = _calculatePenalty(stake);
            totalPenaly += penalty[relayer];

            assertEq(stake >= 2 * ta.minimumStakeAmount(), true);

            vm.expectEmit(true, true, true, false);
            emit RelayerPenalized(relayerMainAddress[i], stake - penalty[relayer], penalty[relayer]);
        }

        _moveForwardToNextEpoch();
        _sendEmptyTransaction(currentState);
        _moveForwardByWindows(deployParams.relayerStateUpdateDelayInWindows);

        // Verify new stake
        for (uint256 i = 0; i < relayerCount; ++i) {
            RelayerAddress relayer = relayerMainAddress[i];
            assertEq(ta.relayerInfo(relayer).stake, initialRelayerStake[relayer] - penalty[relayer]);
            assertEq(ta.relayerInfo(relayer).status == RelayerStatus.Active, true);
        }

        assertEq(ta.totalStake(), totalStake - totalPenaly);
        assertEq(ta.relayerCount(), relayerCount);

        // Verify that the CDF has changed
        assertEq(ta.debug_verifyRelayerStateAtWindow(currentState, ta.debug_currentWindowIndex()), false);

        // Verify the new CDF
        _updateLatestStateCdf();
        _checkCdfInLatestState();
    }

    function testPenalizeExitingRelayerIfInsufficientTransationsAreSubmitted() external {
        RelayerAddress inactiveRelayer = relayerMainAddress[1];
        uint256 totalStake = ta.totalStake();
        uint256 relayerCount = ta.relayerCount();

        ta.debug_setTotalTransactionsProcessed(540);
        for (uint256 i = 0; i < relayerCount; ++i) {
            if (relayerMainAddress[i] == inactiveRelayer) continue;
            ta.debug_setTransactionsProcessedByRelayer(relayerMainAddress[i], 10 * (i + 1));
        }

        RelayerState memory currentState = latestRelayerState;
        _prankRA(inactiveRelayer);
        ta.unregister(latestRelayerState, _findRelayerIndex(inactiveRelayer));
        _removeRelayerFromLatestState(inactiveRelayer);
        RelayerState memory postRemovalState = latestRelayerState;

        uint256 stake = ta.relayerInfo(inactiveRelayer).stake;
        penalty[inactiveRelayer] = _calculatePenalty(stake);
        assertTrue(stake > 0);
        assertTrue(penalty[inactiveRelayer] > 0);
        assertTrue(stake - penalty[inactiveRelayer] >= ta.minimumStakeAmount());
        assertTrue(ta.relayerInfo(inactiveRelayer).status == RelayerStatus.Exiting);
        assertEq(ta.totalStake(), totalStake - stake);
        assertEq(ta.relayerCount(), relayerCount - 1);

        vm.expectEmit(true, true, true, false);
        emit RelayerPenalized(inactiveRelayer, stake - penalty[inactiveRelayer], penalty[inactiveRelayer]);

        _moveForwardToNextEpoch();
        _sendEmptyTransaction(currentState);
        _moveForwardByWindows(deployParams.relayerStateUpdateDelayInWindows);

        // Verify new state
        assertEq(ta.totalStake(), totalStake - stake);
        assertEq(ta.relayerCount(), relayerCount - 1);

        assertEq(ta.relayerInfo(inactiveRelayer).stake, initialRelayerStake[inactiveRelayer] - penalty[inactiveRelayer]);
        assertTrue(ta.relayerInfo(inactiveRelayer).status == RelayerStatus.Exiting);
        for (uint256 i = 0; i < relayerCount; ++i) {
            if (relayerMainAddress[i] == inactiveRelayer) continue;
            RelayerAddress relayer = relayerMainAddress[i];
            assertEq(ta.relayerInfo(relayer).stake, initialRelayerStake[relayer]);
            assertTrue(ta.relayerInfo(relayer).status == RelayerStatus.Active);
        }

        // Verify that the pending CDF has not changed, since the relayer was already removed
        assertTrue(ta.debug_verifyRelayerStateAtWindow(postRemovalState, ta.debug_currentWindowIndex()));
        assertEq(postRemovalState.cdf.length, relayerCount - 1);
        assertEq(postRemovalState.relayers.length, relayerCount - 1);
    }

    function testJailActiveRelayerIfInsufficientTransationsAreSubmittedAndStakesBecomesLtMinStake() external {
        RelayerAddress inactiveRelayer = relayerMainAddress[0];
        uint256 totalStake = ta.totalStake();

        ta.debug_setTotalTransactionsProcessed(5400);
        for (uint256 i = 1; i < relayerCount; ++i) {
            ta.debug_setTransactionsProcessedByRelayer(relayerMainAddress[i], 100 * (i + 1));
        }

        RelayerState memory currentState = latestRelayerState;

        uint256 stake = ta.relayerInfo(inactiveRelayer).stake;
        penalty[inactiveRelayer] = _calculatePenalty(stake);
        uint256 jailedUntilTimestamp = block.timestamp + ta.jailTimeInSec();

        vm.expectEmit(true, true, true, false);
        emit RelayerPenalized(inactiveRelayer, stake - penalty[inactiveRelayer], penalty[inactiveRelayer]);
        vm.expectEmit(true, true, true, false);
        emit RelayerJailed(inactiveRelayer, jailedUntilTimestamp);

        _moveForwardToNextEpoch();
        _sendEmptyTransaction(currentState);
        _moveForwardByWindows(deployParams.relayerStateUpdateDelayInWindows);
        _removeRelayerFromLatestState(inactiveRelayer);

        // Verify new state
        assertEq(ta.totalStake(), totalStake - initialRelayerStake[inactiveRelayer]);
        assertEq(ta.relayerCount(), relayerCount - 1);

        assertEq(ta.relayerInfo(inactiveRelayer).stake, initialRelayerStake[inactiveRelayer] - penalty[inactiveRelayer]);
        assertTrue(ta.relayerInfo(inactiveRelayer).status == RelayerStatus.Jailed);
        for (uint256 i = 1; i < relayerCount; ++i) {
            RelayerAddress relayer = relayerMainAddress[i];
            assertEq(ta.relayerInfo(relayer).stake, initialRelayerStake[relayer]);
            assertTrue(ta.relayerInfo(relayer).status == RelayerStatus.Active);
        }

        // Verify that the CDF has changed
        assertTrue(ta.debug_verifyRelayerStateAtWindow(latestRelayerState, ta.debug_currentWindowIndex()));

        // Verify the new CDF
        assertEq(latestRelayerState.cdf.length, relayerCount - 1);
        assertEq(latestRelayerState.relayers.length, relayerCount - 1);
        _checkCdfInLatestState();
    }

    function testJailExitingRelayerIfInsufficientTransationsAreSubmittedAndStakesBecomesLtMinStake() external {
        RelayerAddress inactiveRelayer = relayerMainAddress[0];
        uint256 totalStake = ta.totalStake();
        uint256 relayerCount = ta.relayerCount();

        ta.debug_setTotalTransactionsProcessed(5400);
        for (uint256 i = 1; i < relayerCount; ++i) {
            ta.debug_setTransactionsProcessedByRelayer(relayerMainAddress[i], 100 * (i + 1));
        }

        RelayerState memory currentState = latestRelayerState;
        _prankRA(inactiveRelayer);
        ta.unregister(latestRelayerState, _findRelayerIndex(inactiveRelayer));
        _removeRelayerFromLatestState(inactiveRelayer);
        RelayerState memory postRemovalState = latestRelayerState;

        uint256 stake = ta.relayerInfo(inactiveRelayer).stake;
        penalty[inactiveRelayer] = _calculatePenalty(stake);
        assertTrue(stake > 0);
        assertTrue(penalty[inactiveRelayer] > 0);
        assertTrue(ta.relayerInfo(inactiveRelayer).status == RelayerStatus.Exiting);
        assertEq(ta.totalStake(), totalStake - stake);
        assertEq(ta.relayerCount(), relayerCount - 1);

        uint256 jailedUntilTimestamp = block.timestamp + ta.jailTimeInSec();

        vm.expectEmit(true, true, true, false);
        emit RelayerPenalized(inactiveRelayer, stake - penalty[inactiveRelayer], penalty[inactiveRelayer]);
        vm.expectEmit(true, true, true, false);
        emit RelayerJailed(inactiveRelayer, jailedUntilTimestamp);

        _moveForwardToNextEpoch();
        _sendEmptyTransaction(currentState);
        _moveForwardByWindows(deployParams.relayerStateUpdateDelayInWindows);

        // Verify new state
        assertEq(ta.totalStake(), totalStake - stake);
        assertEq(ta.relayerCount(), relayerCount - 1);

        assertEq(ta.relayerInfo(inactiveRelayer).stake, initialRelayerStake[inactiveRelayer] - penalty[inactiveRelayer]);
        assertTrue(ta.relayerInfo(inactiveRelayer).status == RelayerStatus.Jailed);
        for (uint256 i = 1; i < relayerCount; ++i) {
            RelayerAddress relayer = relayerMainAddress[i];
            assertEq(ta.relayerInfo(relayer).stake, initialRelayerStake[relayer]);
            assertTrue(ta.relayerInfo(relayer).status == RelayerStatus.Active);
        }

        // Verify that the pending CDF has not changed, since the relayer was already removed
        assertTrue(ta.debug_verifyRelayerStateAtWindow(postRemovalState, ta.debug_currentWindowIndex()));
        assertEq(postRemovalState.cdf.length, relayerCount - 1);
        assertEq(postRemovalState.relayers.length, relayerCount - 1);
    }

    function testJailedRelayerShouldBeAbleToUnjailAndReenterByAddingMoreStakeAfterCooldown() external {
        RelayerAddress inactiveRelayer = relayerMainAddress[0];
        uint256 totalStake = ta.totalStake();
        uint256 relayerCount = ta.relayerCount();
        uint256 expectedPenalty = _calculatePenalty(initialRelayerStake[inactiveRelayer]);

        // Jail the relayer
        ta.debug_setTotalTransactionsProcessed(5400);
        for (uint256 i = 1; i < relayerCount; ++i) {
            ta.debug_setTransactionsProcessedByRelayer(relayerMainAddress[i], 100 * (i + 1));
        }
        RelayerState memory currentState = latestRelayerState;
        _moveForwardToNextEpoch();
        _sendEmptyTransaction(currentState);
        _moveForwardByWindows(deployParams.relayerStateUpdateDelayInWindows);
        _removeRelayerFromLatestState(inactiveRelayer);
        uint256 jailedUntilTimestamp = block.timestamp + ta.jailTimeInSec();

        currentState = latestRelayerState;
        assertTrue(ta.relayerInfo(inactiveRelayer).status == RelayerStatus.Jailed);
        totalStake -= initialRelayerStake[inactiveRelayer];
        relayerCount -= 1;

        vm.warp(jailedUntilTimestamp);

        _startPrankRA(inactiveRelayer);
        bico.approve(address(ta), initialRelayerStake[inactiveRelayer]);
        vm.expectEmit(true, true, true, true);
        emit RelayerUnjailedAndReentered(inactiveRelayer);
        ta.unjailAndReenter(latestRelayerState, initialRelayerStake[inactiveRelayer]);
        vm.stopPrank();

        _moveForwardToNextEpoch();
        _sendEmptyTransaction(currentState);
        _moveForwardByWindows(deployParams.relayerStateUpdateDelayInWindows);
        _appendRelayerToLatestState(inactiveRelayer);
        currentState = latestRelayerState;

        // Verify relayer state
        assertEq(ta.relayerInfo(inactiveRelayer).stake, initialRelayerStake[inactiveRelayer] * 2 - expectedPenalty);
        assertTrue(ta.relayerInfo(inactiveRelayer).status == RelayerStatus.Active);

        // Verify that the CDF has changed
        assertTrue(ta.debug_verifyRelayerStateAtWindow(currentState, ta.debug_currentWindowIndex()));
        assertEq(currentState.cdf.length, relayerCount + 1);
        assertEq(currentState.relayers.length, relayerCount + 1);

        // Verify global counters
        assertEq(ta.totalStake(), totalStake + initialRelayerStake[inactiveRelayer] * 2 - expectedPenalty);
        assertEq(ta.relayerCount(), relayerCount + 1);
    }

    function testJailedRelayerShouldBeAbleToUnjailAndExitAfterCooldown() external {
        RelayerAddress inactiveRelayer = relayerMainAddress[0];
        uint256 totalStake = ta.totalStake();
        uint256 relayerCount = ta.relayerCount();

        // Jail the relayer
        ta.debug_setTotalTransactionsProcessed(5400);
        for (uint256 i = 1; i < relayerCount; ++i) {
            ta.debug_setTransactionsProcessedByRelayer(relayerMainAddress[i], 100 * (i + 1));
        }
        RelayerState memory currentState = latestRelayerState;
        _moveForwardToNextEpoch();
        _sendEmptyTransaction(currentState);
        _moveForwardByWindows(deployParams.relayerStateUpdateDelayInWindows);
        _removeRelayerFromLatestState(inactiveRelayer);
        uint256 jailedUntilTimestamp = block.timestamp + ta.jailTimeInSec();

        currentState = latestRelayerState;
        assertTrue(ta.relayerInfo(inactiveRelayer).status == RelayerStatus.Jailed);
        totalStake -= initialRelayerStake[inactiveRelayer];
        relayerCount -= 1;

        vm.warp(jailedUntilTimestamp);

        _startPrankRA(inactiveRelayer);
        uint256 balance = bico.balanceOf(RelayerAddress.unwrap(inactiveRelayer));
        uint256 stake = ta.relayerInfo(inactiveRelayer).stake;
        vm.expectEmit(true, true, true, true);
        emit Withdraw(inactiveRelayer, stake);
        ta.withdraw(relayerAccountAddresses[inactiveRelayer]);
        vm.stopPrank();

        _moveForwardToNextEpoch();
        _sendEmptyTransaction(currentState);
        _moveForwardByWindows(deployParams.relayerStateUpdateDelayInWindows);

        // Verify that stake has been returned
        assertEq(bico.balanceOf(RelayerAddress.unwrap(inactiveRelayer)), balance + stake);

        // Verify relayer state
        assertTrue(ta.relayerInfo(inactiveRelayer).status == RelayerStatus.Uninitialized);

        // Verify that the CDF has not changed
        assertTrue(ta.debug_verifyRelayerStateAtWindow(currentState, ta.debug_currentWindowIndex()));
        assertEq(currentState.cdf.length, relayerCount);
        assertEq(currentState.relayers.length, relayerCount);

        // Verify global counters
        assertEq(ta.totalStake(), totalStake);
        assertEq(ta.relayerCount(), relayerCount);
    }

    function testCannotUnjailAndReenterBeforeJailExpiry() external {
        RelayerAddress inactiveRelayer = relayerMainAddress[0];
        uint256 relayerCount = ta.relayerCount();

        // Jail the relayer
        ta.debug_setTotalTransactionsProcessed(5400);
        for (uint256 i = 1; i < relayerCount; ++i) {
            ta.debug_setTransactionsProcessedByRelayer(relayerMainAddress[i], 100 * (i + 1));
        }
        RelayerState memory currentState = latestRelayerState;
        _moveForwardToNextEpoch();
        _sendEmptyTransaction(currentState);
        _moveForwardByWindows(deployParams.relayerStateUpdateDelayInWindows);
        _removeRelayerFromLatestState(inactiveRelayer);
        uint256 jailedUntilTimestamp = block.timestamp + ta.jailTimeInSec();

        currentState = latestRelayerState;
        assertTrue(ta.relayerInfo(inactiveRelayer).status == RelayerStatus.Jailed);

        vm.warp(jailedUntilTimestamp - 1);

        _startPrankRA(inactiveRelayer);
        bico.approve(address(ta), initialRelayerStake[inactiveRelayer]);
        vm.expectRevert(abi.encodeWithSelector(RelayerJailNotExpired.selector, jailedUntilTimestamp));
        ta.unjailAndReenter(latestRelayerState, initialRelayerStake[inactiveRelayer]);
        vm.stopPrank();
    }

    function testCannotUnjailAndExitJailBeforeJailExpiry() external {
        RelayerAddress inactiveRelayer = relayerMainAddress[0];
        uint256 relayerCount = ta.relayerCount();

        // Jail the relayer
        ta.debug_setTotalTransactionsProcessed(5400);
        for (uint256 i = 1; i < relayerCount; ++i) {
            ta.debug_setTransactionsProcessedByRelayer(relayerMainAddress[i], 100 * (i + 1));
        }
        RelayerState memory currentState = latestRelayerState;
        _moveForwardToNextEpoch();
        _sendEmptyTransaction(currentState);
        _moveForwardByWindows(deployParams.relayerStateUpdateDelayInWindows);
        _removeRelayerFromLatestState(inactiveRelayer);
        uint256 jailedUntilTimestamp = block.timestamp + ta.jailTimeInSec();

        currentState = latestRelayerState;
        assertTrue(ta.relayerInfo(inactiveRelayer).status == RelayerStatus.Jailed);

        vm.warp(jailedUntilTimestamp - 1);

        _startPrankRA(inactiveRelayer);
        bico.approve(address(ta), initialRelayerStake[inactiveRelayer]);
        vm.expectRevert(abi.encodeWithSelector(RelayerJailNotExpired.selector, jailedUntilTimestamp));
        ta.withdraw(relayerAccountAddresses[inactiveRelayer]);
        vm.stopPrank();
    }

    function testCannotExitJailWithInsufficientStake() external {
        RelayerAddress inactiveRelayer = relayerMainAddress[0];
        uint256 relayerCount = ta.relayerCount();
        uint256 expectedPenalty = _calculatePenalty(initialRelayerStake[inactiveRelayer]);

        // Jail the relayer
        ta.debug_setTotalTransactionsProcessed(5400);
        for (uint256 i = 1; i < relayerCount; ++i) {
            ta.debug_setTransactionsProcessedByRelayer(relayerMainAddress[i], 100 * (i + 1));
        }
        RelayerState memory currentState = latestRelayerState;
        _moveForwardToNextEpoch();
        _sendEmptyTransaction(currentState);
        _moveForwardByWindows(deployParams.relayerStateUpdateDelayInWindows);
        _removeRelayerFromLatestState(inactiveRelayer);
        uint256 jailedUntilTimestamp = block.timestamp + ta.jailTimeInSec();

        currentState = latestRelayerState;
        assertTrue(ta.relayerInfo(inactiveRelayer).status == RelayerStatus.Jailed);

        vm.warp(jailedUntilTimestamp);

        _startPrankRA(inactiveRelayer);
        bico.approve(address(ta), expectedPenalty - 1);
        vm.expectRevert(
            abi.encodeWithSelector(
                InsufficientStake.selector, initialRelayerStake[inactiveRelayer] - 1, ta.minimumStakeAmount()
            )
        );
        ta.unjailAndReenter(latestRelayerState, expectedPenalty - 1);
        vm.stopPrank();
    }

    function testActiveRelayerCannotCallUnjail() external {
        RelayerAddress inactiveRelayer = relayerMainAddress[0];

        _startPrankRA(inactiveRelayer);
        bico.approve(address(ta), initialRelayerStake[inactiveRelayer]);
        vm.expectRevert(abi.encodeWithSelector(RelayerNotJailed.selector));
        ta.unjailAndReenter(latestRelayerState, initialRelayerStake[inactiveRelayer]);
        vm.stopPrank();
    }
}
