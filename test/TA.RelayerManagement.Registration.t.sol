// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import "./base/TATestBase.t.sol";
import "src/transaction-allocator/common/TAConstants.sol";
import "src/transaction-allocator/modules/relayer-management/interfaces/ITARelayerManagementEventsErrors.sol";
import "src/transaction-allocator/common/interfaces/ITAHelpers.sol";

contract TARelayerManagementRegistrationTest is TATestBase, ITARelayerManagementEventsErrors, ITAHelpers {
    function testRelayerRegistration() external atSnapshot {
        for (uint256 i = 0; i < relayerCount; i++) {
            uint256 stake = MINIMUM_STAKE_AMOUNT;
            string memory endpoint = "test";
            RelayerAddress relayerAddress = relayerMainAddress[i];

            _startPrankRA(relayerAddress);
            vm.expectEmit(true, true, true, true);
            emit RelayerRegistered(relayerAddress, endpoint, relayerAccountAddresses[relayerAddress], stake);
            // TODO: Pass tokens while registering
            ta.register(ta.getStakeArray(), stake, relayerAccountAddresses[relayerAddress], endpoint);
            vm.stopPrank();

            assertEq(ta.relayerCount(), i + 1);
            assertEq(ta.relayerInfo_Stake(relayerAddress), stake);
            assertEq(ta.relayerInfo_Endpoint(relayerAddress), endpoint);
            assertEq(ta.relayerInfo_Index(relayerAddress), i);

            for (uint256 j = 0; j < relayerAccountAddresses[relayerAddress].length; j++) {
                assertEq(ta.relayerInfo_isAccount(relayerAddress, relayerAccountAddresses[relayerAddress][j]), true);
            }
        }
    }

    function testRelayerUnRegistration() external atSnapshot {
        // Register all Relayers
        for (uint256 i = 0; i < relayerCount; i++) {
            uint256 stake = MINIMUM_STAKE_AMOUNT;
            string memory endpoint = "test";
            RelayerAddress relayerAddress = relayerMainAddress[i];

            _startPrankRA(relayerAddress);
            ta.register(ta.getStakeArray(), stake, relayerAccountAddresses[relayerAddress], endpoint);
            vm.stopPrank();
        }

        // De-register all Relayers
        for (uint256 i = 0; i < relayerCount; i++) {
            RelayerAddress relayerAddress = relayerMainAddress[i];
            RelayerAccountAddress[] storage accounts = relayerAccountAddresses[relayerAddress];

            _startPrankRA(relayerAddress);

            // De Register Accounts
            bool[] memory accountUpdatedStatus = new bool[](relayerAccountAddresses[relayerAddress].length);
            vm.expectEmit(true, true, true, true);
            emit RelayerAccountsUpdated(relayerAddress, accounts, accountUpdatedStatus);
            ta.setRelayerAccountsStatus(accounts, accountUpdatedStatus);

            // De Register Relayer
            vm.expectEmit(true, true, true, true);
            emit RelayerUnRegistered(relayerAddress);
            ta.unRegister(ta.getStakeArray());

            vm.stopPrank();

            assertEq(ta.relayerCount(), relayerCount - i - 1);
            assertEq(ta.relayerInfo_Stake(relayerAddress), 0);
            assertEq(ta.relayerInfo_Endpoint(relayerAddress), "");
            assertEq(ta.relayerInfo_Index(relayerAddress), 0);

            for (uint256 j = 0; j < relayerAccountAddresses[relayerAddress].length; j++) {
                assertEq(ta.relayerInfo_isAccount(relayerAddress, relayerAccountAddresses[relayerAddress][j]), false);
            }
        }
    }

    function testWithdrawal() external atSnapshot {
        // Register all Relayers
        for (uint256 i = 0; i < relayerCount; i++) {
            uint256 stake = MINIMUM_STAKE_AMOUNT;
            string memory endpoint = "test";
            RelayerAddress relayerAddress = relayerMainAddress[i];

            _startPrankRA(relayerAddress);
            ta.register(ta.getStakeArray(), stake, relayerAccountAddresses[relayerAddress], endpoint);
            vm.stopPrank();
        }

        // De-register all Relayers
        for (uint256 i = 0; i < relayerCount; i++) {
            RelayerAddress relayerAddress = relayerMainAddress[i];
            RelayerAccountAddress[] storage accounts = relayerAccountAddresses[relayerAddress];

            _startPrankRA(relayerAddress);
            bool[] memory accountUpdatedStatus = new bool[](relayerAccountAddresses[relayerAddress].length);
            ta.setRelayerAccountsStatus(accounts, accountUpdatedStatus);
            ta.unRegister(ta.getStakeArray());
            vm.stopPrank();

            assertEq(ta.withdrawalInfo(relayerAddress).amount, MINIMUM_STAKE_AMOUNT);
            assertEq(ta.withdrawalInfo(relayerAddress).time, block.timestamp + ta.withdrawDelay());
        }

        // Withdraw
        skip(ta.withdrawDelay() + 1);

        for (uint256 i = 0; i < relayerCount; i++) {
            RelayerAddress relayerAddress = relayerMainAddress[i];
            uint256 stake = MINIMUM_STAKE_AMOUNT;

            _startPrankRA(relayerAddress);
            vm.expectEmit(true, true, true, true);
            emit Withdraw(relayerAddress, stake);
            ta.withdraw();
            vm.stopPrank();

            // TODO: Check if the stake is transferred to the relayer address
            assertEq(ta.withdrawalInfo(relayerAddress).amount, 0);
            assertEq(ta.withdrawalInfo(relayerAddress).time, 0);
        }
    }

    function testCannotRegisterWithNoRelayAccounts() external atSnapshot {
        uint256 stake = MINIMUM_STAKE_AMOUNT;
        string memory endpoint = "test";
        RelayerAccountAddress[] memory accounts;

        _startPrankRA(relayerMainAddress[0]);
        uint32[] memory stakeArray = ta.getStakeArray();
        vm.expectRevert(NoAccountsProvided.selector);
        ta.register(stakeArray, stake, accounts, endpoint);
        vm.stopPrank();
    }

    function testCannotRegisterWithInsufficientStake() external atSnapshot {
        uint256 stake = MINIMUM_STAKE_AMOUNT - 1;
        string memory endpoint = "test";

        _startPrankRA(relayerMainAddress[0]);
        uint32[] memory stakeArray = ta.getStakeArray();
        vm.expectRevert(abi.encodeWithSelector(InsufficientStake.selector, stake, MINIMUM_STAKE_AMOUNT));
        ta.register(stakeArray, stake, relayerAccountAddresses[relayerMainAddress[0]], endpoint);
        vm.stopPrank();
    }

    function testCannotRegisterWithInvalidStakeArray() external atSnapshot {
        uint256 stake = MINIMUM_STAKE_AMOUNT;
        string memory endpoint = "test";

        _startPrankRA(relayerMainAddress[0]);
        uint32[] memory stakeArray = new uint32[](1);
        stakeArray[0] = 0xb1c0;
        vm.expectRevert(InvalidStakeArrayHash.selector);
        ta.register(stakeArray, stake, relayerAccountAddresses[relayerMainAddress[0]], endpoint);
        vm.stopPrank();
    }

    function testCannotUnRegisterWithInvalidStakeArray() external atSnapshot {
        uint256 stake = MINIMUM_STAKE_AMOUNT;
        string memory endpoint = "test";

        _startPrankRA(relayerMainAddress[0]);
        ta.register(ta.getStakeArray(), stake, relayerAccountAddresses[relayerMainAddress[0]], endpoint);
        uint32[] memory stakeArray = new uint32[](1);
        stakeArray[0] = 0xb1c0;
        vm.expectRevert(InvalidStakeArrayHash.selector);
        ta.unRegister(stakeArray);
        vm.stopPrank();
    }

    function testCannotSetAccountsStateAfterUnRegistering() external atSnapshot {
        uint256 stake = MINIMUM_STAKE_AMOUNT;
        string memory endpoint = "test";

        _startPrankRA(relayerMainAddress[0]);
        ta.register(ta.getStakeArray(), stake, relayerAccountAddresses[relayerMainAddress[0]], endpoint);
        ta.unRegister(ta.getStakeArray());
        vm.expectRevert(abi.encodeWithSelector(InvalidRelayer.selector, relayerMainAddress[0]));
        ta.setRelayerAccountsStatus(
            relayerAccountAddresses[relayerMainAddress[0]],
            new bool[](relayerAccountAddresses[relayerMainAddress[0]].length)
        );
        vm.stopPrank();
    }

    function testCannotWithdrawBeforeWithdrawTime() external atSnapshot {
        uint256 stake = MINIMUM_STAKE_AMOUNT;
        string memory endpoint = "test";

        _startPrankRA(relayerMainAddress[0]);
        ta.register(ta.getStakeArray(), stake, relayerAccountAddresses[relayerMainAddress[0]], endpoint);
        ta.setRelayerAccountsStatus(
            relayerAccountAddresses[relayerMainAddress[0]],
            new bool[](relayerAccountAddresses[relayerMainAddress[0]].length)
        );
        ta.unRegister(ta.getStakeArray());
        uint256 withdrawTime = block.timestamp + ta.withdrawDelay();
        skip(1);
        vm.expectRevert(abi.encodeWithSelector(InvalidWithdrawal.selector, stake, block.timestamp, withdrawTime));
        ta.withdraw();
        vm.stopPrank();
    }

    function testGasTokenAddition() external atSnapshot {
        uint256 stake = MINIMUM_STAKE_AMOUNT;
        string memory endpoint = "test";

        _startPrankRA(relayerMainAddress[0]);
        ta.register(ta.getStakeArray(), stake, relayerAccountAddresses[relayerMainAddress[0]], endpoint);
        TokenAddress[] memory tokens = new TokenAddress[](2);
        tokens[0] = NATIVE_TOKEN;
        tokens[1] = TokenAddress.wrap(address(bico));
        ta.addSupportedGasTokens(tokens);
        assertEq(ta.relayerInfo_SupportedGasTokens(relayerMainAddress[0])[0] == tokens[0], true);
        assertEq(ta.relayerInfo_SupportedGasTokens(relayerMainAddress[0])[1] == tokens[1], true);
        assertEq(ta.relayerInfo_SupportedGasTokens(relayerMainAddress[0]).length, 2);
        assertEq(ta.relayerInfo_isGasTokenSupported(relayerMainAddress[0], tokens[0]), true);
        assertEq(ta.relayerInfo_isGasTokenSupported(relayerMainAddress[0], tokens[1]), true);
        vm.stopPrank();
    }

    function testGasTokenRemoval() external atSnapshot {
        uint256 stake = MINIMUM_STAKE_AMOUNT;
        string memory endpoint = "test";

        _startPrankRA(relayerMainAddress[0]);
        ta.register(ta.getStakeArray(), stake, relayerAccountAddresses[relayerMainAddress[0]], endpoint);
        TokenAddress[] memory tokens = new TokenAddress[](2);
        tokens[0] = NATIVE_TOKEN;
        tokens[1] = TokenAddress.wrap(address(bico));
        ta.addSupportedGasTokens(tokens);

        TokenAddress[] memory removalTokens = new TokenAddress[](1);
        removalTokens[0] = tokens[0];
        ta.removeSupportedGasTokens(removalTokens);
        assertEq(ta.relayerInfo_SupportedGasTokens(relayerMainAddress[0])[0] == tokens[1], true);
        assertEq(ta.relayerInfo_SupportedGasTokens(relayerMainAddress[0]).length, 1);
        assertEq(ta.relayerInfo_isGasTokenSupported(relayerMainAddress[0], tokens[0]), false);
        assertEq(ta.relayerInfo_isGasTokenSupported(relayerMainAddress[0], tokens[1]), true);

        removalTokens[0] = tokens[1];
        ta.removeSupportedGasTokens(removalTokens);
        assertEq(ta.relayerInfo_SupportedGasTokens(relayerMainAddress[0]).length, 0);
        assertEq(ta.relayerInfo_isGasTokenSupported(relayerMainAddress[0], tokens[0]), false);
        assertEq(ta.relayerInfo_isGasTokenSupported(relayerMainAddress[0], tokens[1]), false);
        vm.stopPrank();
    }

    function testCannotAddTokenTwice() external atSnapshot {
        uint256 stake = MINIMUM_STAKE_AMOUNT;
        string memory endpoint = "test";

        _startPrankRA(relayerMainAddress[0]);
        ta.register(ta.getStakeArray(), stake, relayerAccountAddresses[relayerMainAddress[0]], endpoint);
        TokenAddress[] memory tokens = new TokenAddress[](2);
        tokens[0] = NATIVE_TOKEN;
        tokens[1] = TokenAddress.wrap(address(bico));
        ta.addSupportedGasTokens(tokens);

        TokenAddress[] memory additionToken = new TokenAddress[](1);
        additionToken[0] = tokens[0];
        vm.expectRevert(abi.encodeWithSelector(GasTokenAlreadySupported.selector, tokens[0]));
        ta.addSupportedGasTokens(additionToken);

        additionToken[0] = tokens[1];
        vm.expectRevert(abi.encodeWithSelector(GasTokenAlreadySupported.selector, tokens[1]));
        ta.addSupportedGasTokens(additionToken);

        vm.stopPrank();
    }

    function testCannotRemoveAlreadyRemovedToken() external atSnapshot {
        uint256 stake = MINIMUM_STAKE_AMOUNT;
        string memory endpoint = "test";

        _startPrankRA(relayerMainAddress[0]);
        ta.register(ta.getStakeArray(), stake, relayerAccountAddresses[relayerMainAddress[0]], endpoint);
        TokenAddress[] memory tokens = new TokenAddress[](2);
        tokens[0] = NATIVE_TOKEN;
        tokens[1] = TokenAddress.wrap(address(bico));
        ta.addSupportedGasTokens(tokens);

        TokenAddress[] memory removalTokens = new TokenAddress[](1);
        removalTokens[0] = tokens[0];
        ta.removeSupportedGasTokens(removalTokens);
        assertEq(ta.relayerInfo_SupportedGasTokens(relayerMainAddress[0])[0] == tokens[1], true);
        assertEq(ta.relayerInfo_SupportedGasTokens(relayerMainAddress[0]).length, 1);
        assertEq(ta.relayerInfo_isGasTokenSupported(relayerMainAddress[0], tokens[0]), false);
        assertEq(ta.relayerInfo_isGasTokenSupported(relayerMainAddress[0], tokens[1]), true);

        removalTokens[0] = tokens[0];
        vm.expectRevert(abi.encodeWithSelector(GasTokenNotSupported.selector, tokens[0]));
        ta.removeSupportedGasTokens(removalTokens);
        vm.stopPrank();
    }
}
