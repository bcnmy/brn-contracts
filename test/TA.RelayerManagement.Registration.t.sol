// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import "./base/TATestBase.t.sol";
import "src/transaction-allocator/common/TAConstants.sol";
import "src/transaction-allocator/modules/relayer-management/interfaces/ITARelayerManagementEventsErrors.sol";
import "src/transaction-allocator/common/interfaces/ITAHelpers.sol";

// TODO: Relayer Ownership Checks
contract TARelayerManagementRegistrationTest is TATestBase, ITARelayerManagementEventsErrors, ITAHelpers {
    mapping(RelayerAddress => RelayerId) internal relayerIdMap;

    function testRelayerRegistration() external atSnapshot {
        for (uint256 i = 0; i < relayerCount; i++) {
            uint256 stake = MINIMUM_STAKE_AMOUNT;
            string memory endpoint = "test";
            RelayerAddress relayerAddress = relayerMainAddress[i];

            _startPrankRA(relayerAddress);
            bico.approve(address(ta), stake);
            RelayerId expectedRelayerId = ta.getExpectedRelayerId(relayerAddress);
            vm.expectEmit(true, true, true, true);
            emit RelayerRegistered(
                expectedRelayerId, relayerAddress, endpoint, relayerAccountAddresses[relayerAddress], stake
            );
            relayerIdMap[relayerAddress] = ta.register(
                ta.getStakeArray(), ta.getDelegationArray(), stake, relayerAccountAddresses[relayerAddress], endpoint
            );
            vm.stopPrank();

            _assertEqRid(expectedRelayerId, relayerIdMap[relayerAddress]);
            assertEq(ta.relayerCount(), i + 1);
            _assertEqRa(ta.relayerInfo_RelayerAddress(expectedRelayerId), relayerAddress);
            assertEq(ta.relayerInfo_Stake(expectedRelayerId), stake);
            assertEq(ta.relayerInfo_Endpoint(expectedRelayerId), endpoint);
            assertEq(ta.relayerInfo_Index(expectedRelayerId), i);

            for (uint256 j = 0; j < relayerAccountAddresses[relayerAddress].length; j++) {
                assertEq(ta.relayerInfo_isAccount(expectedRelayerId, relayerAccountAddresses[relayerAddress][j]), true);
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
            bico.approve(address(ta), stake);
            relayerIdMap[relayerAddress] = ta.register(
                ta.getStakeArray(), ta.getDelegationArray(), stake, relayerAccountAddresses[relayerAddress], endpoint
            );
            vm.stopPrank();
        }

        // De-register all Relayers
        for (uint256 i = 0; i < relayerCount; i++) {
            RelayerAddress relayerAddress = relayerMainAddress[i];
            RelayerId relayerId = relayerIdMap[relayerAddress];
            RelayerAccountAddress[] storage accounts = relayerAccountAddresses[relayerAddress];

            _startPrankRA(relayerAddress);

            // De Register Accounts
            bool[] memory accountUpdatedStatus = new bool[](relayerAccountAddresses[relayerAddress].length);
            vm.expectEmit(true, true, true, true);
            emit RelayerAccountsUpdated(relayerId, accounts, accountUpdatedStatus);
            ta.setRelayerAccountsStatus(relayerId, accounts, accountUpdatedStatus);

            // De Register Relayer
            vm.expectEmit(true, true, true, true);
            emit RelayerUnRegistered(relayerId);
            ta.unRegister(ta.getStakeArray(), ta.getDelegationArray(), relayerId);

            vm.stopPrank();

            assertEq(ta.relayerCount(), relayerCount - i - 1);
            assertEq(ta.relayerInfo_Stake(relayerId), 0);
            assertEq(ta.relayerInfo_Endpoint(relayerId), "");
            assertEq(ta.relayerInfo_Index(relayerId), 0);

            for (uint256 j = 0; j < relayerAccountAddresses[relayerAddress].length; j++) {
                assertEq(ta.relayerInfo_isAccount(relayerId, relayerAccountAddresses[relayerAddress][j]), false);
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
            bico.approve(address(ta), stake);
            relayerIdMap[relayerAddress] = ta.register(
                ta.getStakeArray(), ta.getDelegationArray(), stake, relayerAccountAddresses[relayerAddress], endpoint
            );
            vm.stopPrank();
        }

        // De-register all Relayers
        for (uint256 i = 0; i < relayerCount; i++) {
            RelayerAddress relayerAddress = relayerMainAddress[i];
            RelayerId relayerId = relayerIdMap[relayerAddress];
            RelayerAccountAddress[] storage accounts = relayerAccountAddresses[relayerAddress];

            _startPrankRA(relayerAddress);
            bool[] memory accountUpdatedStatus = new bool[](relayerAccountAddresses[relayerAddress].length);
            ta.setRelayerAccountsStatus(relayerId, accounts, accountUpdatedStatus);
            ta.unRegister(ta.getStakeArray(), ta.getDelegationArray(), relayerId);
            vm.stopPrank();

            assertEq(ta.withdrawalInfo(relayerId).amount, MINIMUM_STAKE_AMOUNT);
            assertEq(ta.withdrawalInfo(relayerId).time, block.timestamp + ta.withdrawDelay());
        }

        // Withdraw
        skip(ta.withdrawDelay() + 1);

        for (uint256 i = 0; i < relayerCount; i++) {
            RelayerAddress relayerAddress = relayerMainAddress[i];
            RelayerId relayerId = relayerIdMap[relayerAddress];
            uint256 stake = MINIMUM_STAKE_AMOUNT;
            uint256 balanceBefore = bico.balanceOf(RelayerAddress.unwrap(relayerAddress));

            _startPrankRA(relayerAddress);
            vm.expectEmit(true, true, true, true);
            emit Withdraw(relayerId, stake);
            ta.withdraw(relayerId);
            vm.stopPrank();

            assertEq(ta.withdrawalInfo(relayerId).amount, 0);
            assertEq(ta.withdrawalInfo(relayerId).time, 0);
            assertEq(bico.balanceOf(RelayerAddress.unwrap(relayerAddress)), balanceBefore + stake);
        }
    }

    function testCannotRegisterWithNoRelayAccounts() external atSnapshot {
        uint256 stake = MINIMUM_STAKE_AMOUNT;
        string memory endpoint = "test";
        RelayerAccountAddress[] memory accounts;

        _startPrankRA(relayerMainAddress[0]);
        uint32[] memory stakeArray = ta.getStakeArray();
        uint32[] memory delegationArray = ta.getDelegationArray();
        bico.approve(address(ta), stake);
        vm.expectRevert(NoAccountsProvided.selector);
        ta.register(stakeArray, delegationArray, stake, accounts, endpoint);
        vm.stopPrank();
    }

    function testCannotRegisterWithInsufficientStake() external atSnapshot {
        uint256 stake = MINIMUM_STAKE_AMOUNT - 1;
        string memory endpoint = "test";

        _startPrankRA(relayerMainAddress[0]);
        uint32[] memory stakeArray = ta.getStakeArray();
        uint32[] memory delegationArray = ta.getDelegationArray();
        bico.approve(address(ta), stake);
        vm.expectRevert(abi.encodeWithSelector(InsufficientStake.selector, stake, MINIMUM_STAKE_AMOUNT));
        ta.register(stakeArray, delegationArray, stake, relayerAccountAddresses[relayerMainAddress[0]], endpoint);
        vm.stopPrank();
    }

    function testCannotRegisterWithInvalidStakeArray() external atSnapshot {
        uint256 stake = MINIMUM_STAKE_AMOUNT;
        string memory endpoint = "test";

        _startPrankRA(relayerMainAddress[0]);
        uint32[] memory stakeArray = new uint32[](1);
        uint32[] memory delegationArray = ta.getDelegationArray();
        stakeArray[0] = 0xb1c0;
        bico.approve(address(ta), stake);
        vm.expectRevert(InvalidStakeArrayHash.selector);
        ta.register(stakeArray, delegationArray, stake, relayerAccountAddresses[relayerMainAddress[0]], endpoint);
        vm.stopPrank();
    }

    function testCannotRegisterWithInvalidDelegationArray() external atSnapshot {
        uint256 stake = MINIMUM_STAKE_AMOUNT;
        string memory endpoint = "test";

        _startPrankRA(relayerMainAddress[0]);
        uint32[] memory stakeArray = ta.getStakeArray();
        uint32[] memory delegationArray = new uint32[](1);
        delegationArray[0] = 0xb1c0;
        bico.approve(address(ta), stake);
        vm.expectRevert(InvalidDelegationArrayHash.selector);
        ta.register(stakeArray, delegationArray, stake, relayerAccountAddresses[relayerMainAddress[0]], endpoint);
        vm.stopPrank();
    }

    function testCannotUnRegisterWithInvalidStakeArray() external atSnapshot {
        uint256 stake = MINIMUM_STAKE_AMOUNT;
        string memory endpoint = "test";

        _startPrankRA(relayerMainAddress[0]);
        bico.approve(address(ta), stake);
        RelayerId relayerId = ta.register(
            ta.getStakeArray(), ta.getDelegationArray(), stake, relayerAccountAddresses[relayerMainAddress[0]], endpoint
        );
        uint32[] memory stakeArray = new uint32[](1);
        stakeArray[0] = 0xb1c0;
        uint32[] memory delegationArray = ta.getDelegationArray();
        vm.expectRevert(InvalidStakeArrayHash.selector);
        ta.unRegister(stakeArray, delegationArray, relayerId);
        vm.stopPrank();
    }

    function testCannotUnRegisterWithInvalidDelegationArray() external atSnapshot {
        uint256 stake = MINIMUM_STAKE_AMOUNT;
        string memory endpoint = "test";

        _startPrankRA(relayerMainAddress[0]);
        bico.approve(address(ta), stake);
        RelayerId relayerId = ta.register(
            ta.getStakeArray(), ta.getDelegationArray(), stake, relayerAccountAddresses[relayerMainAddress[0]], endpoint
        );
        uint32[] memory stakeArray = ta.getStakeArray();
        uint32[] memory delegationArray = new uint32[](1);
        delegationArray[0] = 0xb1c0;
        vm.expectRevert(InvalidDelegationArrayHash.selector);
        ta.unRegister(stakeArray, delegationArray, relayerId);
        vm.stopPrank();
    }

    function testCannotSetAccountsStateAfterUnRegistering() external atSnapshot {
        uint256 stake = MINIMUM_STAKE_AMOUNT;
        string memory endpoint = "test";

        _startPrankRA(relayerMainAddress[0]);
        bico.approve(address(ta), stake);
        RelayerId relayerId = ta.register(
            ta.getStakeArray(), ta.getDelegationArray(), stake, relayerAccountAddresses[relayerMainAddress[0]], endpoint
        );
        ta.unRegister(ta.getStakeArray(), ta.getDelegationArray(), relayerId);
        vm.expectRevert(abi.encodeWithSelector(InvalidRelayer.selector, relayerId));
        ta.setRelayerAccountsStatus(
            relayerId,
            relayerAccountAddresses[relayerMainAddress[0]],
            new bool[](relayerAccountAddresses[relayerMainAddress[0]].length)
        );
        vm.stopPrank();
    }

    function testCannotWithdrawBeforeWithdrawTime() external atSnapshot {
        uint256 stake = MINIMUM_STAKE_AMOUNT;
        string memory endpoint = "test";

        _startPrankRA(relayerMainAddress[0]);
        bico.approve(address(ta), stake);
        RelayerId relayerId = ta.register(
            ta.getStakeArray(), ta.getDelegationArray(), stake, relayerAccountAddresses[relayerMainAddress[0]], endpoint
        );
        ta.setRelayerAccountsStatus(
            relayerId,
            relayerAccountAddresses[relayerMainAddress[0]],
            new bool[](relayerAccountAddresses[relayerMainAddress[0]].length)
        );
        ta.unRegister(ta.getStakeArray(), ta.getDelegationArray(), relayerId);
        uint256 withdrawTime = block.timestamp + ta.withdrawDelay();
        skip(1);
        vm.expectRevert(abi.encodeWithSelector(InvalidWithdrawal.selector, stake, block.timestamp, withdrawTime));
        ta.withdraw(relayerId);
        vm.stopPrank();
    }

    function testGasTokenAddition() external atSnapshot {
        uint256 stake = MINIMUM_STAKE_AMOUNT;
        string memory endpoint = "test";

        _startPrankRA(relayerMainAddress[0]);
        bico.approve(address(ta), stake);
        RelayerId relayerId = ta.register(
            ta.getStakeArray(), ta.getDelegationArray(), stake, relayerAccountAddresses[relayerMainAddress[0]], endpoint
        );
        TokenAddress[] memory tokens = new TokenAddress[](2);
        tokens[0] = NATIVE_TOKEN;
        tokens[1] = TokenAddress.wrap(address(bico));
        ta.addSupportedGasTokens(relayerId, tokens);
        assertEq(ta.supportedPools(relayerId)[0] == tokens[0], true);
        assertEq(ta.supportedPools(relayerId)[1] == tokens[1], true);
        assertEq(ta.supportedPools(relayerId).length, 2);
        assertEq(ta.relayerInfo_isGasTokenSupported(relayerId, tokens[0]), true);
        assertEq(ta.relayerInfo_isGasTokenSupported(relayerId, tokens[1]), true);
        vm.stopPrank();
    }

    function testGasTokenRemoval() external atSnapshot {
        uint256 stake = MINIMUM_STAKE_AMOUNT;
        string memory endpoint = "test";

        _startPrankRA(relayerMainAddress[0]);
        bico.approve(address(ta), stake);
        RelayerId relayerId = ta.register(
            ta.getStakeArray(), ta.getDelegationArray(), stake, relayerAccountAddresses[relayerMainAddress[0]], endpoint
        );
        TokenAddress[] memory tokens = new TokenAddress[](2);
        tokens[0] = NATIVE_TOKEN;
        tokens[1] = TokenAddress.wrap(address(bico));
        ta.addSupportedGasTokens(relayerId, tokens);

        TokenAddress[] memory removalTokens = new TokenAddress[](1);
        removalTokens[0] = tokens[0];
        ta.removeSupportedGasTokens(relayerId, removalTokens);
        assertEq(ta.supportedPools(relayerId)[0] == tokens[0], true);
        assertEq(ta.supportedPools(relayerId)[1] == tokens[1], true);
        assertEq(ta.supportedPools(relayerId).length, 2);
        assertEq(ta.relayerInfo_isGasTokenSupported(relayerId, tokens[0]), false);
        assertEq(ta.relayerInfo_isGasTokenSupported(relayerId, tokens[1]), true);

        removalTokens[0] = tokens[1];
        ta.removeSupportedGasTokens(relayerId, removalTokens);
        assertEq(ta.supportedPools(relayerId)[0] == tokens[0], true);
        assertEq(ta.supportedPools(relayerId)[1] == tokens[1], true);
        assertEq(ta.supportedPools(relayerId).length, 2);
        assertEq(ta.relayerInfo_isGasTokenSupported(relayerId, tokens[0]), false);
        assertEq(ta.relayerInfo_isGasTokenSupported(relayerId, tokens[1]), false);
        vm.stopPrank();
    }

    function testCannotAddTokenTwice() external atSnapshot {
        uint256 stake = MINIMUM_STAKE_AMOUNT;
        string memory endpoint = "test";

        _startPrankRA(relayerMainAddress[0]);
        bico.approve(address(ta), stake);
        RelayerId relayerId = ta.register(
            ta.getStakeArray(), ta.getDelegationArray(), stake, relayerAccountAddresses[relayerMainAddress[0]], endpoint
        );
        TokenAddress[] memory tokens = new TokenAddress[](2);
        tokens[0] = NATIVE_TOKEN;
        tokens[1] = TokenAddress.wrap(address(bico));
        ta.addSupportedGasTokens(relayerId, tokens);

        TokenAddress[] memory additionToken = new TokenAddress[](1);
        additionToken[0] = tokens[0];
        vm.expectRevert(abi.encodeWithSelector(GasTokenAlreadySupported.selector, tokens[0]));
        ta.addSupportedGasTokens(relayerId, additionToken);

        additionToken[0] = tokens[1];
        vm.expectRevert(abi.encodeWithSelector(GasTokenAlreadySupported.selector, tokens[1]));
        ta.addSupportedGasTokens(relayerId, additionToken);

        vm.stopPrank();
    }

    function testCannotRemoveAlreadyRemovedToken() external atSnapshot {
        uint256 stake = MINIMUM_STAKE_AMOUNT;
        string memory endpoint = "test";

        _startPrankRA(relayerMainAddress[0]);
        bico.approve(address(ta), stake);
        RelayerId relayerId = ta.register(
            ta.getStakeArray(), ta.getDelegationArray(), stake, relayerAccountAddresses[relayerMainAddress[0]], endpoint
        );
        TokenAddress[] memory tokens = new TokenAddress[](2);
        tokens[0] = NATIVE_TOKEN;
        tokens[1] = TokenAddress.wrap(address(bico));
        ta.addSupportedGasTokens(relayerId, tokens);

        TokenAddress[] memory removalTokens = new TokenAddress[](1);
        removalTokens[0] = tokens[0];
        ta.removeSupportedGasTokens(relayerId, removalTokens);
        assertEq(ta.supportedPools(relayerId)[0] == tokens[0], true);
        assertEq(ta.supportedPools(relayerId)[1] == tokens[1], true);
        assertEq(ta.supportedPools(relayerId).length, 2);
        assertEq(ta.relayerInfo_isGasTokenSupported(relayerId, tokens[0]), false);
        assertEq(ta.relayerInfo_isGasTokenSupported(relayerId, tokens[1]), true);

        removalTokens[0] = tokens[0];
        vm.expectRevert(abi.encodeWithSelector(GasTokenNotSupported.selector, tokens[0]));
        ta.removeSupportedGasTokens(relayerId, removalTokens);
        vm.stopPrank();
    }
}
