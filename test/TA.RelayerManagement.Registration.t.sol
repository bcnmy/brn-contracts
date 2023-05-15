// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import "./base/TATestBase.t.sol";
import "src/transaction-allocator/common/TAConstants.sol";
import "src/transaction-allocator/modules/relayer-management/interfaces/ITARelayerManagementEventsErrors.sol";
import "src/transaction-allocator/common/interfaces/ITAHelpers.sol";

// TODO: check delayed update for relayer index
contract TARelayerManagementRegistrationTest is TATestBase, ITARelayerManagementEventsErrors, ITAHelpers {
    string endpoint = "test";
    uint256 delegatorPoolPremiumShare = 1000;

    function testRelayerRegistration() external atSnapshot {
        uint16[] memory cdf = ta.getCdfArray(activeRelayers);
        assertEq(cdf.length, 0);

        for (uint256 i = 0; i < relayerCount; i++) {
            uint256 stake = MINIMUM_STAKE_AMOUNT;

            RelayerAddress relayerAddress = relayerMainAddress[i];

            _startPrankRA(relayerAddress);
            bico.approve(address(ta), stake);
            vm.stopPrank();

            vm.expectEmit(true, true, true, true);
            emit RelayerRegistered(
                relayerAddress, endpoint, relayerAccountAddresses[relayerAddress], stake, delegatorPoolPremiumShare
            );
            _register(
                relayerAddress,
                ta.getStakeArray(activeRelayers),
                ta.getDelegationArray(activeRelayers),
                stake,
                relayerAccountAddresses[relayerAddress],
                endpoint,
                delegatorPoolPremiumShare
            );
            assertEq(ta.relayerCount(), i + 1);
            assertEq(ta.relayerInfo_Stake(relayerAddress), stake);
            assertEq(ta.relayerInfo_Endpoint(relayerAddress), endpoint);

            for (uint256 j = 0; j < relayerAccountAddresses[relayerAddress].length; j++) {
                assertEq(ta.relayerInfo_isAccount(relayerAddress, relayerAccountAddresses[relayerAddress][j]), true);
            }
        }

        uint16[] memory newCdf = ta.getCdfArray(activeRelayers);
        assertEq(newCdf.length, relayerCount);

        // Verify that at this point of time, CDF hash has not been updated
        assertEq(ta.debug_verifyCdfHashAtWindow(cdf, ta.debug_currentWindowIndex(), 0), true);
        assertEq(ta.debug_verifyCdfHashAtWindow(newCdf, ta.debug_currentWindowIndex(), 0), false);

        vm.roll(block.number + WINDOWS_PER_EPOCH * ta.blocksPerWindow());

        // CDF hash should be updated now
        assertEq(ta.debug_verifyCdfHashAtWindow(cdf, ta.debug_currentWindowIndex(), 1), false);
        assertEq(ta.debug_verifyCdfHashAtWindow(newCdf, ta.debug_currentWindowIndex(), 1), true);
    }

    function testRelayerUnRegistration() external atSnapshot {
        // Register all Relayers
        for (uint256 i = 0; i < relayerCount; i++) {
            uint256 stake = MINIMUM_STAKE_AMOUNT;

            RelayerAddress relayerAddress = relayerMainAddress[i];

            _startPrankRA(relayerAddress);
            bico.approve(address(ta), stake);
            vm.stopPrank();

            _register(
                relayerAddress,
                ta.getStakeArray(activeRelayers),
                ta.getDelegationArray(activeRelayers),
                stake,
                relayerAccountAddresses[relayerAddress],
                endpoint,
                delegatorPoolPremiumShare
            );
        }

        vm.roll(block.number + WINDOWS_PER_EPOCH * ta.blocksPerWindow());
        uint16[] memory cdf = ta.getCdfArray(activeRelayers);

        // De-register all Relayers
        for (uint256 i = 0; i < relayerCount; i++) {
            RelayerAddress relayerAddress = relayerMainAddress[i];

            // De Register Relayer
            vm.expectEmit(true, true, true, true);
            emit RelayerUnRegistered(relayerAddress);

            _unregister(relayerAddress, ta.getStakeArray(activeRelayers), ta.getDelegationArray(activeRelayers));

            assertEq(ta.relayerCount(), relayerCount - i - 1);
            assertEq(ta.relayerInfo_Stake(relayerAddress), 0);
            assertEq(ta.relayerInfo_Endpoint(relayerAddress), "");

            for (uint256 j = 0; j < relayerAccountAddresses[relayerAddress].length; j++) {
                assertEq(ta.relayerInfo_isAccount(relayerAddress, relayerAccountAddresses[relayerAddress][j]), false);
            }
        }

        uint16[] memory newCdf = ta.getCdfArray(activeRelayers);
        assertEq(newCdf.length, 0);

        // Verify that at this point of time, CDF hash has not been updated
        assertEq(ta.debug_verifyCdfHashAtWindow(cdf, ta.debug_currentWindowIndex(), 1), true);
        assertEq(ta.debug_verifyCdfHashAtWindow(newCdf, ta.debug_currentWindowIndex(), 1), false);

        vm.roll(block.number + WINDOWS_PER_EPOCH * ta.blocksPerWindow());

        // CDF hash should be updated now
        assertEq(ta.debug_verifyCdfHashAtWindow(cdf, ta.debug_currentWindowIndex(), 2), false);
        assertEq(ta.debug_verifyCdfHashAtWindow(newCdf, ta.debug_currentWindowIndex(), 2), true);
    }

    function testWithdrawal() external atSnapshot {
        // Register all Relayers
        for (uint256 i = 0; i < relayerCount; i++) {
            uint256 stake = MINIMUM_STAKE_AMOUNT;

            RelayerAddress relayerAddress = relayerMainAddress[i];

            _startPrankRA(relayerAddress);
            bico.approve(address(ta), stake);
            vm.stopPrank();

            _register(
                relayerAddress,
                ta.getStakeArray(activeRelayers),
                ta.getDelegationArray(activeRelayers),
                stake,
                relayerAccountAddresses[relayerAddress],
                endpoint,
                delegatorPoolPremiumShare
            );
        }

        // De-register all Relayers
        uint256 maxWithdrawalBlock;
        for (uint256 i = 0; i < relayerCount; i++) {
            RelayerAddress relayerAddress = relayerMainAddress[i];

            _unregister(relayerAddress, ta.getStakeArray(activeRelayers), ta.getDelegationArray(activeRelayers));

            uint256 expectedWithdrawBlock = block.number + RELAYER_WITHDRAW_DELAY_IN_BLOCKS;

            assertEq(ta.withdrawalInfo(relayerAddress).amount, MINIMUM_STAKE_AMOUNT);
            assertEq(ta.withdrawalInfo(relayerAddress).minBlockNumber, expectedWithdrawBlock);

            maxWithdrawalBlock = expectedWithdrawBlock > maxWithdrawalBlock ? expectedWithdrawBlock : maxWithdrawalBlock;
        }

        // Withdraw
        vm.roll(maxWithdrawalBlock);

        for (uint256 i = 0; i < relayerCount; i++) {
            RelayerAddress relayerAddress = relayerMainAddress[i];

            uint256 stake = MINIMUM_STAKE_AMOUNT;
            uint256 balanceBefore = bico.balanceOf(RelayerAddress.unwrap(relayerAddress));

            _startPrankRA(relayerAddress);
            vm.expectEmit(true, true, true, true);
            emit Withdraw(relayerAddress, stake);
            ta.withdraw();
            vm.stopPrank();

            assertEq(ta.withdrawalInfo(relayerAddress).amount, 0);
            assertEq(ta.withdrawalInfo(relayerAddress).minBlockNumber, 0);
            assertEq(bico.balanceOf(RelayerAddress.unwrap(relayerAddress)), balanceBefore + stake);
        }
    }

    function testCannotRegisterWithNoRelayAccounts() external atSnapshot {
        uint256 stake = MINIMUM_STAKE_AMOUNT;

        RelayerAccountAddress[] memory accounts;

        _startPrankRA(relayerMainAddress[0]);
        bico.approve(address(ta), stake);
        vm.stopPrank();

        uint32[] memory stakeArray = ta.getStakeArray(activeRelayers);
        uint32[] memory delegationArray = ta.getDelegationArray(activeRelayers);
        vm.expectRevert(NoAccountsProvided.selector);
        _register(
            relayerMainAddress[0], stakeArray, delegationArray, stake, accounts, endpoint, delegatorPoolPremiumShare
        );
    }

    function testCannotRegisterWithInsufficientStake() external atSnapshot {
        uint256 stake = MINIMUM_STAKE_AMOUNT - 1;

        _startPrankRA(relayerMainAddress[0]);
        bico.approve(address(ta), stake);
        vm.stopPrank();

        uint32[] memory stakeArray = ta.getStakeArray(activeRelayers);
        uint32[] memory delegationArray = ta.getDelegationArray(activeRelayers);
        vm.expectRevert(abi.encodeWithSelector(InsufficientStake.selector, stake, MINIMUM_STAKE_AMOUNT));

        _register(
            relayerMainAddress[0],
            stakeArray,
            delegationArray,
            stake,
            relayerAccountAddresses[relayerMainAddress[0]],
            endpoint,
            delegatorPoolPremiumShare
        );
    }

    function testCannotRegisterWithInvalidStakeArray() external atSnapshot {
        uint256 stake = MINIMUM_STAKE_AMOUNT;

        _startPrankRA(relayerMainAddress[0]);
        bico.approve(address(ta), stake);
        vm.stopPrank();

        uint32[] memory stakeArray = new uint32[](1);
        uint32[] memory delegationArray = ta.getDelegationArray(activeRelayers);
        stakeArray[0] = 0xb1c0;
        vm.expectRevert(InvalidStakeArrayHash.selector);

        _register(
            relayerMainAddress[0],
            stakeArray,
            delegationArray,
            stake,
            relayerAccountAddresses[relayerMainAddress[0]],
            endpoint,
            delegatorPoolPremiumShare
        );
    }

    function testCannotRegisterWithInvalidDelegationArray() external atSnapshot {
        uint256 stake = MINIMUM_STAKE_AMOUNT;

        _startPrankRA(relayerMainAddress[0]);
        bico.approve(address(ta), stake);
        vm.stopPrank();

        uint32[] memory stakeArray = ta.getStakeArray(activeRelayers);
        uint32[] memory delegationArray = new uint32[](1);
        delegationArray[0] = 0xb1c0;
        vm.expectRevert(InvalidDelegationArrayHash.selector);

        _register(
            relayerMainAddress[0],
            stakeArray,
            delegationArray,
            stake,
            relayerAccountAddresses[relayerMainAddress[0]],
            endpoint,
            delegatorPoolPremiumShare
        );
    }

    function testCannotUnRegisterWithInvalidStakeArray() external atSnapshot {
        uint256 stake = MINIMUM_STAKE_AMOUNT;

        _startPrankRA(relayerMainAddress[0]);
        bico.approve(address(ta), stake);
        vm.stopPrank();

        _register(
            relayerMainAddress[0],
            ta.getStakeArray(activeRelayers),
            ta.getDelegationArray(activeRelayers),
            stake,
            relayerAccountAddresses[relayerMainAddress[0]],
            endpoint,
            delegatorPoolPremiumShare
        );
        uint32[] memory stakeArray = new uint32[](1);
        stakeArray[0] = 0xb1c0;
        uint32[] memory delegationArray = ta.getDelegationArray(activeRelayers);

        vm.expectRevert(InvalidStakeArrayHash.selector);
        _unregister(relayerMainAddress[0], stakeArray, delegationArray);
    }

    function testCannotUnRegisterWithInvalidDelegationArray() external atSnapshot {
        uint256 stake = MINIMUM_STAKE_AMOUNT;

        _startPrankRA(relayerMainAddress[0]);
        bico.approve(address(ta), stake);
        vm.stopPrank();

        _register(
            relayerMainAddress[0],
            ta.getStakeArray(activeRelayers),
            ta.getDelegationArray(activeRelayers),
            stake,
            relayerAccountAddresses[relayerMainAddress[0]],
            endpoint,
            delegatorPoolPremiumShare
        );
        uint32[] memory stakeArray = ta.getStakeArray(activeRelayers);
        uint32[] memory delegationArray = new uint32[](1);
        delegationArray[0] = 0xb1c0;

        vm.expectRevert(InvalidDelegationArrayHash.selector);
        _unregister(relayerMainAddress[0], stakeArray, delegationArray);
    }

    function testCannotSetAccountsStateAfterUnRegistering() external atSnapshot {
        uint256 stake = MINIMUM_STAKE_AMOUNT;

        _startPrankRA(relayerMainAddress[0]);
        bico.approve(address(ta), stake);
        vm.stopPrank();

        _register(
            relayerMainAddress[0],
            ta.getStakeArray(activeRelayers),
            ta.getDelegationArray(activeRelayers),
            stake,
            relayerAccountAddresses[relayerMainAddress[0]],
            endpoint,
            delegatorPoolPremiumShare
        );
        _unregister(relayerMainAddress[0], ta.getStakeArray(activeRelayers), ta.getDelegationArray(activeRelayers));
        vm.expectRevert(abi.encodeWithSelector(InvalidRelayer.selector, relayerMainAddress[0]));

        _startPrankRA(relayerMainAddress[0]);
        ta.setRelayerAccounts(new RelayerAccountAddress[](0));
        vm.stopPrank();
    }

    function testCannotWithdrawBeforeWithdrawTime() external atSnapshot {
        uint256 stake = MINIMUM_STAKE_AMOUNT;

        _startPrankRA(relayerMainAddress[0]);
        bico.approve(address(ta), stake);
        vm.stopPrank();

        _register(
            relayerMainAddress[0],
            ta.getStakeArray(activeRelayers),
            ta.getDelegationArray(activeRelayers),
            stake,
            relayerAccountAddresses[relayerMainAddress[0]],
            endpoint,
            delegatorPoolPremiumShare
        );
        _unregister(relayerMainAddress[0], ta.getStakeArray(activeRelayers), ta.getDelegationArray(activeRelayers));

        _startPrankRA(relayerMainAddress[0]);
        uint256 expectedWithdrawBlock = block.number + RELAYER_WITHDRAW_DELAY_IN_BLOCKS;
        vm.expectRevert(abi.encodeWithSelector(InvalidWithdrawal.selector, stake, block.number, expectedWithdrawBlock));
        ta.withdraw();
        vm.stopPrank();
    }
}
