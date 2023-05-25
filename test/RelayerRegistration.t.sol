// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import "./base/TATestBase.sol";
import "ta-common/TAConstants.sol";
import "ta-relayer-management/interfaces/ITARelayerManagementEventsErrors.sol";
import "ta-common/interfaces/ITAHelpers.sol";

contract RelayerRegistrationTest is TATestBase, ITARelayerManagementEventsErrors, ITAHelpers {
    function testRelayerRegistration() external {
        RelayerState memory currentState = latestRelayerState;
        uint256 totalStake = initialRelayerStake[relayerMainAddress[0]];

        for (uint256 i = 1; i < relayerCount; i++) {
            RelayerAddress relayerAddress = relayerMainAddress[i];

            _prankRA(relayerAddress);
            bico.approve(address(ta), initialRelayerStake[relayerAddress]);

            vm.expectEmit(true, true, true, true);
            emit RelayerRegistered(
                relayerAddress,
                endpoint,
                relayerAccountAddresses[relayerAddress],
                initialRelayerStake[relayerAddress],
                delegatorPoolPremiumShare
            );
            _prankRA(relayerAddress);
            ta.register(
                latestRelayerState,
                initialRelayerStake[relayerAddress],
                relayerAccountAddresses[relayerAddress],
                endpoint,
                delegatorPoolPremiumShare
            );
            _appendRelayerToLatestState(relayerAddress);

            // Relayer State
            assertEq(ta.relayerInfo(relayerAddress).stake, initialRelayerStake[relayerAddress]);
            assertEq(ta.relayerInfo(relayerAddress).endpoint, endpoint);
            assertEq(ta.relayerInfo(relayerAddress).status == RelayerStatus.Active, true);
            assertEq(ta.relayerInfo(relayerAddress).delegatorPoolPremiumShare == delegatorPoolPremiumShare, true);

            for (uint256 j = 0; j < relayerAccountAddresses[relayerAddress].length; j++) {
                assertEq(ta.relayerInfo_isAccount(relayerAddress, relayerAccountAddresses[relayerAddress][j]), true);
            }

            // Global Counters
            totalStake += initialRelayerStake[relayerAddress];
            assertEq(ta.relayerCount(), i + 1);
            assertEq(ta.totalStake(), totalStake);

            // Check if the CDF Entries are correct
            _checkCdfInLatestState();
        }

        assertEq(latestRelayerState.cdf.length, relayerCount);
        assertEq(latestRelayerState.relayers.length, relayerCount);

        // Verify that at this point of time, CDF hash has not been updated
        assertEq(ta.debug_verifyRelayerStateAtWindow(currentState, ta.debug_currentWindowIndex()), true);
        assertEq(ta.debug_verifyRelayerStateAtWindow(latestRelayerState, ta.debug_currentWindowIndex()), false);

        _moveForwardToNextEpoch();
        _sendEmptyTransaction(currentState);
        _moveForwardByWindows(deployParams.relayerStateUpdateDelayInWindows);

        // CDF hash should be updated now
        assertEq(ta.debug_verifyRelayerStateAtWindow(currentState, ta.debug_currentWindowIndex()), false);
        assertEq(ta.debug_verifyRelayerStateAtWindow(latestRelayerState, ta.debug_currentWindowIndex()), true);
    }

    function testRelayerUnRegistration() external {
        RelayerState memory currentState = latestRelayerState;

        _registerAllNonFoundationRelayers();

        _moveForwardToNextEpoch();
        _sendEmptyTransaction(currentState);
        _moveForwardByWindows(deployParams.relayerStateUpdateDelayInWindows);

        currentState = latestRelayerState;
        uint256 relayersUnregistered;
        uint256 totalStake;

        // Calculate total stake
        for (uint256 i = 0; i < relayerCount; i++) {
            totalStake += initialRelayerStake[relayerMainAddress[i]];
        }

        // De-register relayers with odd index
        for (uint256 i = 1; i < relayerCount; i++) {
            if (i % 2 == 0) {
                continue;
            }

            ++relayersUnregistered;
            RelayerAddress relayerAddress = relayerMainAddress[i];

            // De Register Relayer
            vm.expectEmit(true, true, true, true);
            emit RelayerUnRegistered(relayerAddress);

            _prankRA(relayerAddress);
            ta.unregister(latestRelayerState, _findRelayerIndex(relayerAddress));
            _removeRelayerFromLatestState(relayerAddress);

            // Relayer State
            assertEq(ta.relayerInfo(relayerAddress).stake, initialRelayerStake[relayerAddress]);
            assertEq(ta.relayerInfo(relayerAddress).endpoint, endpoint);
            assertEq(ta.relayerInfo(relayerAddress).status == RelayerStatus.Exiting, true);
            assertEq(ta.relayerInfo(relayerAddress).delegatorPoolPremiumShare == delegatorPoolPremiumShare, true);
            for (uint256 j = 0; j < relayerAccountAddresses[relayerAddress].length; j++) {
                assertEq(ta.relayerInfo_isAccount(relayerAddress, relayerAccountAddresses[relayerAddress][j]), true);
            }

            // Global Counters
            totalStake -= initialRelayerStake[relayerAddress];
            assertEq(ta.relayerCount(), relayerCount - relayersUnregistered);
            assertEq(ta.totalStake(), totalStake);

            // Check if the CDF Entries are correct
            _checkCdfInLatestState();
        }

        assertEq(ta.relayerCount(), relayerCount - relayersUnregistered);
        assertEq(latestRelayerState.cdf.length, relayerCount - relayersUnregistered);
        assertEq(latestRelayerState.relayers.length, relayerCount - relayersUnregistered);

        // Verify that at this point of time, CDF hash has not been updated
        assertEq(ta.debug_verifyRelayerStateAtWindow(currentState, ta.debug_currentWindowIndex()), true);
        assertEq(ta.debug_verifyRelayerStateAtWindow(latestRelayerState, ta.debug_currentWindowIndex()), false);

        _moveForwardToNextEpoch();
        _sendEmptyTransaction(currentState);
        _moveForwardByWindows(deployParams.relayerStateUpdateDelayInWindows);

        // CDF hash should be updated now
        assertEq(ta.debug_verifyRelayerStateAtWindow(currentState, ta.debug_currentWindowIndex()), false);
        assertEq(ta.debug_verifyRelayerStateAtWindow(latestRelayerState, ta.debug_currentWindowIndex()), true);
    }

    function testWithdrawal() external {
        // Register all relayers
        RelayerState memory currentState = latestRelayerState;
        _registerAllNonFoundationRelayers();
        _moveForwardToNextEpoch();
        _sendEmptyTransaction(currentState);
        _moveForwardByWindows(deployParams.relayerStateUpdateDelayInWindows);

        // De-register all Relayers
        currentState = latestRelayerState;
        for (uint256 i = 1; i < relayerCount; i++) {
            RelayerAddress relayerAddress = relayerMainAddress[i];
            _prankRA(relayerAddress);
            ta.unregister(latestRelayerState, _findRelayerIndex(relayerAddress));
            _removeRelayerFromLatestState(relayerAddress);
        }
        _moveForwardToNextEpoch();
        _sendEmptyTransaction(currentState);
        _moveForwardByWindows(deployParams.relayerStateUpdateDelayInWindows);

        vm.warp(ta.relayerInfo(relayerMainAddress[1]).minExitTimestamp);

        // Withdraw
        for (uint256 i = 1; i < relayerCount; i++) {
            RelayerAddress relayerAddress = relayerMainAddress[i];

            uint256 balanceBefore = bico.balanceOf(RelayerAddress.unwrap(relayerAddress));

            _startPrankRA(relayerAddress);
            vm.expectEmit(true, true, true, true);
            emit Withdraw(relayerAddress, initialRelayerStake[relayerAddress]);
            ta.withdraw();
            vm.stopPrank();

            assertEq(ta.relayerInfo(relayerAddress).stake, 0);
            assertEq(ta.relayerInfo(relayerAddress).minExitTimestamp, 0);
            assertEq(ta.relayerInfo(relayerAddress).status == RelayerStatus.Uninitialized, true);
            assertEq(
                bico.balanceOf(RelayerAddress.unwrap(relayerAddress)),
                balanceBefore + initialRelayerStake[relayerAddress]
            );
        }
    }

    function testSetRelayerAccountStatus() external {
        // Register
        _startPrankRA(relayerMainAddress[1]);
        bico.approve(address(ta), initialRelayerStake[relayerMainAddress[1]]);
        ta.register(
            latestRelayerState,
            initialRelayerStake[relayerMainAddress[1]],
            relayerAccountAddresses[relayerMainAddress[1]],
            endpoint,
            delegatorPoolPremiumShare
        );
        _appendRelayerToLatestState(relayerMainAddress[1]);
        vm.stopPrank();

        // Set Relayer Account Status
        _prankRA(relayerMainAddress[1]);
        ta.setRelayerAccountsStatus(
            relayerAccountAddresses[relayerMainAddress[1]],
            new bool[](relayerAccountAddresses[relayerMainAddress[1]].length)
        );
        for (uint256 i = 0; i < relayerAccountAddresses[relayerMainAddress[1]].length; i++) {
            assertEq(
                ta.relayerInfo_isAccount(relayerMainAddress[1], relayerAccountAddresses[relayerMainAddress[1]][i]),
                false
            );
        }
    }

    function testCannotRegisterWithNoRelayAccounts() external {
        RelayerAccountAddress[] memory accounts;

        _startPrankRA(relayerMainAddress[1]);
        bico.approve(address(ta), initialRelayerStake[relayerMainAddress[1]]);
        vm.expectRevert(NoAccountsProvided.selector);
        ta.register(
            latestRelayerState,
            initialRelayerStake[relayerMainAddress[1]],
            accounts,
            endpoint,
            delegatorPoolPremiumShare
        );
        vm.stopPrank();
    }

    function testCannotUnregisterAllRelayers() external {
        // Deregister the foundation relayer
        _prankRA(relayerMainAddress[0]);
        vm.expectRevert(CannotUnregisterLastRelayer.selector);
        ta.unregister(latestRelayerState, _findRelayerIndex(relayerMainAddress[0]));
    }

    function testCannotRegisterWithInsufficientStake() external {
        uint256 stake = deployParams.minimumStakeAmount - 1;

        _startPrankRA(relayerMainAddress[1]);
        bico.approve(address(ta), stake);
        vm.expectRevert(abi.encodeWithSelector(InsufficientStake.selector, stake, deployParams.minimumStakeAmount));
        ta.register(
            latestRelayerState,
            stake,
            relayerAccountAddresses[relayerMainAddress[1]],
            endpoint,
            delegatorPoolPremiumShare
        );
        vm.stopPrank();
    }

    function testCannotUnregisterAnotherRelayer() external {
        // Register
        _startPrankRA(relayerMainAddress[1]);
        RelayerState memory currentState = latestRelayerState;
        bico.approve(address(ta), initialRelayerStake[relayerMainAddress[1]]);
        ta.register(
            latestRelayerState,
            initialRelayerStake[relayerMainAddress[1]],
            relayerAccountAddresses[relayerMainAddress[1]],
            endpoint,
            delegatorPoolPremiumShare
        );
        _appendRelayerToLatestState(relayerMainAddress[1]);
        vm.stopPrank();

        _moveForwardToNextEpoch();
        _sendEmptyTransaction(currentState);
        _moveForwardByWindows(deployParams.relayerStateUpdateDelayInWindows);

        // Unregister
        uint256 relayerCount = ta.relayerCount();
        _prankRA(relayerMainAddress[1]);
        vm.expectRevert(abi.encodeWithSelector(InvalidRelayer.selector, relayerMainAddress[1]));
        ta.unregister(latestRelayerState, (_findRelayerIndex(relayerMainAddress[1]) + 1) % relayerCount);
    }

    function testCannotCallRegisterIfRelayerIsAlreadyRegistered() external {
        // Register
        _startPrankRA(relayerMainAddress[1]);
        RelayerState memory currentState = latestRelayerState;
        bico.approve(address(ta), initialRelayerStake[relayerMainAddress[1]]);
        ta.register(
            latestRelayerState,
            initialRelayerStake[relayerMainAddress[1]],
            relayerAccountAddresses[relayerMainAddress[1]],
            endpoint,
            delegatorPoolPremiumShare
        );
        _appendRelayerToLatestState(relayerMainAddress[1]);
        vm.stopPrank();

        _moveForwardToNextEpoch();
        _sendEmptyTransaction(currentState);
        _moveForwardByWindows(deployParams.relayerStateUpdateDelayInWindows);

        vm.expectRevert(abi.encodeWithSelector(RelayerAlreadyRegistered.selector));
        _prankRA(relayerMainAddress[1]);
        ta.register(
            latestRelayerState,
            initialRelayerStake[relayerMainAddress[1]],
            relayerAccountAddresses[relayerMainAddress[1]],
            endpoint,
            delegatorPoolPremiumShare
        );
    }

    function testCannotSetAccountsStateAfterUnRegistering() external {
        // Register
        _startPrankRA(relayerMainAddress[1]);
        RelayerState memory currentState = latestRelayerState;
        bico.approve(address(ta), initialRelayerStake[relayerMainAddress[1]]);
        ta.register(
            latestRelayerState,
            initialRelayerStake[relayerMainAddress[1]],
            relayerAccountAddresses[relayerMainAddress[1]],
            endpoint,
            delegatorPoolPremiumShare
        );
        _appendRelayerToLatestState(relayerMainAddress[1]);
        vm.stopPrank();

        _moveForwardToNextEpoch();
        _sendEmptyTransaction(currentState);
        _moveForwardByWindows(deployParams.relayerStateUpdateDelayInWindows);

        // Unregister
        _startPrankRA(relayerMainAddress[1]);
        currentState = latestRelayerState;
        ta.unregister(latestRelayerState, _findRelayerIndex(relayerMainAddress[1]));
        _removeRelayerFromLatestState(relayerMainAddress[1]);
        vm.stopPrank();

        _moveForwardToNextEpoch();
        _sendEmptyTransaction(currentState);
        _moveForwardByWindows(deployParams.relayerStateUpdateDelayInWindows);

        vm.expectRevert(abi.encodeWithSelector(InvalidRelayer.selector, relayerMainAddress[1]));
        _prankRA(relayerMainAddress[1]);
        ta.setRelayerAccountsStatus(new RelayerAccountAddress[](0), new bool[](0));
    }

    function testCannotWithdrawWithoutUnregistering() external {
        // Register
        _startPrankRA(relayerMainAddress[1]);
        RelayerState memory currentState = latestRelayerState;
        bico.approve(address(ta), initialRelayerStake[relayerMainAddress[1]]);
        ta.register(
            latestRelayerState,
            initialRelayerStake[relayerMainAddress[1]],
            relayerAccountAddresses[relayerMainAddress[1]],
            endpoint,
            delegatorPoolPremiumShare
        );
        _appendRelayerToLatestState(relayerMainAddress[1]);
        vm.stopPrank();

        _moveForwardToNextEpoch();
        _sendEmptyTransaction(currentState);
        _moveForwardByWindows(deployParams.relayerStateUpdateDelayInWindows);

        vm.expectRevert(abi.encodeWithSelector(RelayerNotExiting.selector));
        _prankRA(relayerMainAddress[1]);
        ta.withdraw();
    }

    function testCannotWithdrawBeforeWithdrawTime() external {
        // Register
        _startPrankRA(relayerMainAddress[1]);
        RelayerState memory currentState = latestRelayerState;
        bico.approve(address(ta), initialRelayerStake[relayerMainAddress[1]]);
        ta.register(
            latestRelayerState,
            initialRelayerStake[relayerMainAddress[1]],
            relayerAccountAddresses[relayerMainAddress[1]],
            endpoint,
            delegatorPoolPremiumShare
        );
        _appendRelayerToLatestState(relayerMainAddress[1]);
        vm.stopPrank();

        _moveForwardToNextEpoch();
        _sendEmptyTransaction(currentState);
        _moveForwardByWindows(deployParams.relayerStateUpdateDelayInWindows);

        // Unregister
        _startPrankRA(relayerMainAddress[1]);
        currentState = latestRelayerState;
        ta.unregister(latestRelayerState, _findRelayerIndex(relayerMainAddress[1]));
        _removeRelayerFromLatestState(relayerMainAddress[1]);
        vm.stopPrank();

        vm.warp(ta.relayerInfo(relayerMainAddress[1]).minExitTimestamp - 1);

        vm.expectRevert(
            abi.encodeWithSelector(
                InvalidWithdrawal.selector,
                initialRelayerStake[relayerMainAddress[1]],
                block.timestamp,
                block.timestamp + 1
            )
        );
        _prankRA(relayerMainAddress[1]);
        ta.withdraw();
    }
}
