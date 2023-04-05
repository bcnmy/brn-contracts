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
        uint16[] memory cdf = ta.getCdfArray();
        assertEq(cdf.length, 0);

        for (uint256 i = 0; i < relayerCount; i++) {
            uint256 stake = MINIMUM_STAKE_AMOUNT;

            RelayerAddress relayerAddress = relayerMainAddress[i];

            _startPrankRA(relayerAddress);
            bico.approve(address(ta), stake);
            vm.expectEmit(true, true, true, true);
            emit RelayerRegistered(
                relayerAddress, endpoint, relayerAccountAddresses[relayerAddress], stake, delegatorPoolPremiumShare
            );
            ta.register(
                ta.getStakeArray(),
                ta.getDelegationArray(),
                stake,
                relayerAccountAddresses[relayerAddress],
                endpoint,
                delegatorPoolPremiumShare
            );
            vm.stopPrank();

            assertEq(ta.relayerCount(), i + 1);
            assertEq(ta.relayerInfo_Stake(relayerAddress), stake);
            assertEq(ta.relayerInfo_Endpoint(relayerAddress), endpoint);
            assertEq(ta.relayerInfo_Index(relayerAddress), i);

            for (uint256 j = 0; j < relayerAccountAddresses[relayerAddress].length; j++) {
                assertEq(ta.relayerInfo_isAccount(relayerAddress, relayerAccountAddresses[relayerAddress][j]), true);
            }
        }

        uint16[] memory newCdf = ta.getCdfArray();
        assertEq(newCdf.length, relayerCount);

        // Verify that at this point of time, CDF hash has not been updated
        assertEq(ta.debug_verifyCdfHashAtWindow(cdf, ta.debug_currentWindowIndex(), 0), true);
        assertEq(ta.debug_verifyCdfHashAtWindow(newCdf, ta.debug_currentWindowIndex(), 0), false);

        vm.roll(block.number + RELAYER_CONFIGURATION_UPDATE_DELAY_IN_WINDOWS * ta.blocksPerWindow());

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
            ta.register(
                ta.getStakeArray(),
                ta.getDelegationArray(),
                stake,
                relayerAccountAddresses[relayerAddress],
                endpoint,
                delegatorPoolPremiumShare
            );
            vm.stopPrank();
        }

        vm.roll(block.number + RELAYER_CONFIGURATION_UPDATE_DELAY_IN_WINDOWS * ta.blocksPerWindow());
        uint16[] memory cdf = ta.getCdfArray();

        // De-register all Relayers
        for (uint256 i = 0; i < relayerCount; i++) {
            RelayerAddress relayerAddress = relayerMainAddress[i];
            _startPrankRA(relayerAddress);

            // De Register Relayer
            vm.expectEmit(true, true, true, true);
            emit RelayerUnRegistered(relayerAddress);
            ta.unRegister(ta.getStakeArray(), ta.getDelegationArray());

            vm.stopPrank();

            assertEq(ta.relayerCount(), relayerCount - i - 1);
            assertEq(ta.relayerInfo_Stake(relayerAddress), 0);
            assertEq(ta.relayerInfo_Endpoint(relayerAddress), "");
            assertEq(ta.relayerInfo_Index(relayerAddress), 0);

            for (uint256 j = 0; j < relayerAccountAddresses[relayerAddress].length; j++) {
                assertEq(ta.relayerInfo_isAccount(relayerAddress, relayerAccountAddresses[relayerAddress][j]), false);
            }
        }

        uint16[] memory newCdf = ta.getCdfArray();
        assertEq(newCdf.length, 0);

        // Verify that at this point of time, CDF hash has not been updated
        assertEq(ta.debug_verifyCdfHashAtWindow(cdf, ta.debug_currentWindowIndex(), 1), true);
        assertEq(ta.debug_verifyCdfHashAtWindow(newCdf, ta.debug_currentWindowIndex(), 1), false);

        vm.roll(block.number + RELAYER_CONFIGURATION_UPDATE_DELAY_IN_WINDOWS * ta.blocksPerWindow());

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
            ta.register(
                ta.getStakeArray(),
                ta.getDelegationArray(),
                stake,
                relayerAccountAddresses[relayerAddress],
                endpoint,
                delegatorPoolPremiumShare
            );
            vm.stopPrank();
        }

        // De-register all Relayers
        uint256 maxWithdrawalBlock;
        for (uint256 i = 0; i < relayerCount; i++) {
            RelayerAddress relayerAddress = relayerMainAddress[i];

            _startPrankRA(relayerAddress);
            ta.unRegister(ta.getStakeArray(), ta.getDelegationArray());
            vm.stopPrank();

            uint256 expectedWithdrawBlock = (
                (block.number + RELAYER_CONFIGURATION_UPDATE_DELAY_IN_WINDOWS * deployParams.blocksPerWindow)
                    / deployParams.blocksPerWindow
            ) * deployParams.blocksPerWindow;

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
        uint32[] memory stakeArray = ta.getStakeArray();
        uint32[] memory delegationArray = ta.getDelegationArray();
        bico.approve(address(ta), stake);
        vm.expectRevert(NoAccountsProvided.selector);
        ta.register(stakeArray, delegationArray, stake, accounts, endpoint, delegatorPoolPremiumShare);
        vm.stopPrank();
    }

    function testCannotRegisterWithInsufficientStake() external atSnapshot {
        uint256 stake = MINIMUM_STAKE_AMOUNT - 1;

        _startPrankRA(relayerMainAddress[0]);
        uint32[] memory stakeArray = ta.getStakeArray();
        uint32[] memory delegationArray = ta.getDelegationArray();
        bico.approve(address(ta), stake);
        vm.expectRevert(abi.encodeWithSelector(InsufficientStake.selector, stake, MINIMUM_STAKE_AMOUNT));
        ta.register(
            stakeArray,
            delegationArray,
            stake,
            relayerAccountAddresses[relayerMainAddress[0]],
            endpoint,
            delegatorPoolPremiumShare
        );
        vm.stopPrank();
    }

    function testCannotRegisterWithInvalidStakeArray() external atSnapshot {
        uint256 stake = MINIMUM_STAKE_AMOUNT;

        _startPrankRA(relayerMainAddress[0]);
        uint32[] memory stakeArray = new uint32[](1);
        uint32[] memory delegationArray = ta.getDelegationArray();
        stakeArray[0] = 0xb1c0;
        bico.approve(address(ta), stake);
        vm.expectRevert(InvalidStakeArrayHash.selector);
        ta.register(
            stakeArray,
            delegationArray,
            stake,
            relayerAccountAddresses[relayerMainAddress[0]],
            endpoint,
            delegatorPoolPremiumShare
        );
        vm.stopPrank();
    }

    function testCannotRegisterWithInvalidDelegationArray() external atSnapshot {
        uint256 stake = MINIMUM_STAKE_AMOUNT;

        _startPrankRA(relayerMainAddress[0]);
        uint32[] memory stakeArray = ta.getStakeArray();
        uint32[] memory delegationArray = new uint32[](1);
        delegationArray[0] = 0xb1c0;
        bico.approve(address(ta), stake);
        vm.expectRevert(InvalidDelegationArrayHash.selector);
        ta.register(
            stakeArray,
            delegationArray,
            stake,
            relayerAccountAddresses[relayerMainAddress[0]],
            endpoint,
            delegatorPoolPremiumShare
        );
        vm.stopPrank();
    }

    function testCannotUnRegisterWithInvalidStakeArray() external atSnapshot {
        uint256 stake = MINIMUM_STAKE_AMOUNT;

        _startPrankRA(relayerMainAddress[0]);
        bico.approve(address(ta), stake);
        ta.register(
            ta.getStakeArray(),
            ta.getDelegationArray(),
            stake,
            relayerAccountAddresses[relayerMainAddress[0]],
            endpoint,
            delegatorPoolPremiumShare
        );
        uint32[] memory stakeArray = new uint32[](1);
        stakeArray[0] = 0xb1c0;
        uint32[] memory delegationArray = ta.getDelegationArray();
        vm.expectRevert(InvalidStakeArrayHash.selector);
        ta.unRegister(stakeArray, delegationArray);
        vm.stopPrank();
    }

    function testCannotUnRegisterWithInvalidDelegationArray() external atSnapshot {
        uint256 stake = MINIMUM_STAKE_AMOUNT;

        _startPrankRA(relayerMainAddress[0]);
        bico.approve(address(ta), stake);
        ta.register(
            ta.getStakeArray(),
            ta.getDelegationArray(),
            stake,
            relayerAccountAddresses[relayerMainAddress[0]],
            endpoint,
            delegatorPoolPremiumShare
        );
        uint32[] memory stakeArray = ta.getStakeArray();
        uint32[] memory delegationArray = new uint32[](1);
        delegationArray[0] = 0xb1c0;
        vm.expectRevert(InvalidDelegationArrayHash.selector);
        ta.unRegister(stakeArray, delegationArray);
        vm.stopPrank();
    }

    function testCannotSetAccountsStateAfterUnRegistering() external atSnapshot {
        uint256 stake = MINIMUM_STAKE_AMOUNT;

        _startPrankRA(relayerMainAddress[0]);
        bico.approve(address(ta), stake);
        ta.register(
            ta.getStakeArray(),
            ta.getDelegationArray(),
            stake,
            relayerAccountAddresses[relayerMainAddress[0]],
            endpoint,
            delegatorPoolPremiumShare
        );
        ta.unRegister(ta.getStakeArray(), ta.getDelegationArray());
        vm.expectRevert(abi.encodeWithSelector(InvalidRelayer.selector, relayerMainAddress[0]));
        ta.setRelayerAccountsStatus(new RelayerAccountAddress[](0));
        vm.stopPrank();
    }

    function testCannotWithdrawBeforeWithdrawTime() external atSnapshot {
        uint256 stake = MINIMUM_STAKE_AMOUNT;

        _startPrankRA(relayerMainAddress[0]);
        bico.approve(address(ta), stake);
        ta.register(
            ta.getStakeArray(),
            ta.getDelegationArray(),
            stake,
            relayerAccountAddresses[relayerMainAddress[0]],
            endpoint,
            delegatorPoolPremiumShare
        );
        ta.setRelayerAccountsStatus(new RelayerAccountAddress[](0));
        ta.unRegister(ta.getStakeArray(), ta.getDelegationArray());

        uint256 expectedWithdrawBlock = (
            (block.number + RELAYER_CONFIGURATION_UPDATE_DELAY_IN_WINDOWS * deployParams.blocksPerWindow)
                / deployParams.blocksPerWindow
        ) * deployParams.blocksPerWindow;
        vm.expectRevert(abi.encodeWithSelector(InvalidWithdrawal.selector, stake, block.number, expectedWithdrawBlock));
        ta.withdraw();
        vm.stopPrank();
    }
}
