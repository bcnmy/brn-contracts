// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import "test/base/TATestBase.sol";
import "ta-common/interfaces/ITAHelpers.sol";
import "ta-delegation/interfaces/ITADelegationEventsErrors.sol";
import "ta-delegation/interfaces/ITADelegationGetters.sol";

contract DelegationTest is TATestBase, ITAHelpers, ITADelegationEventsErrors {
    using Uint256WrapperHelper for uint256;
    using FixedPointTypeHelper for FixedPointType;

    uint256 constant REWARDS_MAX_ABSOLUTE_ERROR = 1; // 1 wei

    TokenAddress bondTokenAddress;
    uint256 ridx;
    RelayerAddress r;
    DelegatorAddress d0;
    DelegatorAddress d1;
    DelegatorAddress d2;

    mapping(DelegatorAddress => uint256) delegation;
    mapping(DelegatorAddress => mapping(TokenAddress => uint256)) reward;

    function setUp() public override {
        // Disable protocol rewards accrual
        deployParams.baseRewardRatePerMinimumStakePerSec = 0;

        super.setUp();

        supportedTokens.push(TokenAddress.wrap(address(bico)));
        supportedTokens.push(NATIVE_TOKEN);

        // Register all Relayers
        RelayerStateManager.RelayerState memory currentState = latestRelayerState;
        _registerAllNonFoundationRelayers();
        _moveForwardToNextEpoch();
        _sendEmptyTransaction(currentState);
        _moveForwardByWindows(deployParams.relayerStateUpdateDelayInWindows);

        // Approval
        for (uint256 i = 0; i < delegatorAddresses.length; ++i) {
            _prankDA(delegatorAddresses[i]);
            bico.approve(address(ta), type(uint256).max);
        }

        // Constants
        bondTokenAddress = TokenAddress.wrap(address(bico));
        ridx = 9;
        r = relayerMainAddress[ridx];
        d0 = delegatorAddresses[0];
        d1 = delegatorAddresses[1];
        d2 = delegatorAddresses[2];

        // Validate test assumptions
        if (ta.supportedPools().length != 2) {
            fail("Expected 2 supported pools");
        }
        if (ta.supportedPools()[0] != bondTokenAddress) {
            fail("Expected first supported pool to be BICO");
        }
        if (ta.supportedPools()[1] != NATIVE_TOKEN) {
            fail("Expected second supported pool to be NATIVE_TOKEN");
        }

        delegation[d0] = 1000 ether;
        delegation[d1] = 2000 ether;
        delegation[d2] = 3000 ether;
    }

    function _findTokenIndex(TokenAddress _t) internal returns (uint256) {
        for (uint256 i = 0; i < ta.supportedPools().length; ++i) {
            if (ta.supportedPools()[i] == _t) {
                return i;
            }
        }
        fail("could not find token index");
        return ta.supportedPools().length;
    }

    function _increaseRewards(RelayerAddress _r, TokenAddress _t, uint256 _amount) internal {
        uint256 rewardsBefore = ta.unclaimedDelegationRewards(_r, _t);
        _startPrankRA(relayerMainAddress[0]);
        if (_t != NATIVE_TOKEN) {
            IERC20(TokenAddress.unwrap(_t)).approve(address(ta), _amount);
        }
        ta.addDelegationRewards{value: _t == NATIVE_TOKEN ? _amount : 0}(_r, _findTokenIndex(_t), _amount);
        assertEq(ta.unclaimedDelegationRewards(_r, _t), rewardsBefore + _amount);
        vm.stopPrank();

        if (_t == NATIVE_TOKEN) {
            deal(address(ta), address(ta).balance + _amount);
        } else {
            address token = TokenAddress.unwrap(_t);
            IERC20 tokenContract = IERC20(token);
            deal(token, address(ta), _amount + tokenContract.balanceOf(address(ta)));
        }
    }

    function _delegate(RelayerAddress _r, uint256 _ridx, DelegatorAddress _d) internal {
        uint256 balanceBefore = bico.balanceOf(DelegatorAddress.unwrap(_d));
        uint256 delegationBefore = ta.delegation(_r, _d);
        if (delegation[_d] == 0) {
            fail("Delegation amount is 0");
        }
        _prankDA(_d);
        ta.delegate(latestRelayerState, _ridx, delegation[_d]);
        assertEq(bico.balanceOf(DelegatorAddress.unwrap(_d)), balanceBefore - delegation[_d]);
        assertEq(ta.delegation(_r, _d), delegationBefore + delegation[_d]);

        _updateLatestStateCdf();
    }

    struct UndelegateTestState {
        uint256 nativeBalanceBefore;
        uint256 bicoBalanceBefore;
        uint256 totalDelegationBefore;
        FixedPointType sharesBicoBefore;
        FixedPointType sharesNativeBefore;
        FixedPointType totalSharesBicoBefore;
        FixedPointType totalSharesNativeBefore;
        uint256 claimableRewardsBicoBefore;
        uint256 claimableRewardsNativeBefore;
    }

    function _undelegate(
        RelayerAddress _r,
        DelegatorAddress _d,
        bool _expectNonZeroNativeDelegationReward,
        bool _expectNonZeroBicoDeleagationReward
    ) internal {
        UndelegateTestState memory s = UndelegateTestState({
            nativeBalanceBefore: DelegatorAddress.unwrap(_d).balance,
            bicoBalanceBefore: bico.balanceOf(DelegatorAddress.unwrap(_d)),
            totalDelegationBefore: ta.totalDelegation(r),
            sharesBicoBefore: ta.shares(_r, _d, bondTokenAddress),
            sharesNativeBefore: ta.shares(_r, _d, NATIVE_TOKEN),
            totalSharesBicoBefore: ta.totalShares(r, bondTokenAddress),
            totalSharesNativeBefore: ta.totalShares(r, NATIVE_TOKEN),
            claimableRewardsBicoBefore: ta.claimableDelegationRewards(_r, bondTokenAddress, _d),
            claimableRewardsNativeBefore: ta.claimableDelegationRewards(_r, NATIVE_TOKEN, _d)
        });

        _prankDA(_d);
        ta.undelegate(latestRelayerState, _r, _findRelayerIndex(_r));

        // Shares should be destroyed
        assertEq(ta.shares(_r, _d, bondTokenAddress), FP_ZERO);
        assertEq(ta.shares(_r, _d, NATIVE_TOKEN), FP_ZERO);

        // Global counters
        assertEq(ta.totalShares(r, bondTokenAddress), s.totalSharesBicoBefore - s.sharesBicoBefore);
        assertEq(ta.totalShares(r, NATIVE_TOKEN), s.totalSharesNativeBefore - s.sharesNativeBefore);
        assertEq(ta.totalDelegation(r), s.totalDelegationBefore - delegation[_d]);

        // Check that rewards are NOT credited
        assertTrue(DelegatorAddress.unwrap(_d).balance == s.nativeBalanceBefore);
        assertTrue(bico.balanceOf(DelegatorAddress.unwrap(_d)) == s.bicoBalanceBefore);

        // Check that claimable rewards are now 0
        assertEq(ta.claimableDelegationRewards(_r, bondTokenAddress, _d), 0);
        assertEq(ta.claimableDelegationRewards(_r, NATIVE_TOKEN, _d), 0);

        // Check that withdrawal with correct amount is created
        ITADelegationGetters.DelegationWithdrawalResult memory withdrawal = ta.delegationWithdrawal(_r, _d);
        assertEq(withdrawal.minWithdrawalTimestamp, block.timestamp + deployParams.delegationWithdrawDelayInSec);
        assertEq(withdrawal.withdrawals.length, 2);
        // BICO
        assertTrue(withdrawal.withdrawals[0].tokenAddress == bondTokenAddress);
        assertTrue(withdrawal.withdrawals[0].amount >= delegation[_d]);
        reward[_d][bondTokenAddress] = withdrawal.withdrawals[0].amount - delegation[_d];
        assertEq(reward[_d][bondTokenAddress], s.claimableRewardsBicoBefore);
        // NATIVE
        assertTrue(withdrawal.withdrawals[1].tokenAddress == NATIVE_TOKEN);
        assertTrue(withdrawal.withdrawals[1].amount >= 0);
        reward[_d][NATIVE_TOKEN] = withdrawal.withdrawals[1].amount;
        assertEq(reward[_d][NATIVE_TOKEN], s.claimableRewardsNativeBefore);

        if (_expectNonZeroNativeDelegationReward) {
            assertTrue(reward[_d][NATIVE_TOKEN] > 0);
        }
        if (_expectNonZeroBicoDeleagationReward) {
            assertTrue(reward[_d][bondTokenAddress] > 0);
        }

        _updateLatestStateCdf();
    }

    function _withdraw(RelayerAddress _r, DelegatorAddress _d) internal {
        uint256 nativeBalanceBefore = DelegatorAddress.unwrap(_d).balance;
        uint256 bicoBalanceBefore = bico.balanceOf(DelegatorAddress.unwrap(_d));

        _prankDA(_d);
        ta.withdrawDelegation(_r);

        // Check that withdrawal is cleared
        ITADelegationGetters.DelegationWithdrawalResult memory withdrawalAfter = ta.delegationWithdrawal(_r, _d);
        assertEq(withdrawalAfter.minWithdrawalTimestamp, 0);
        assertEq(withdrawalAfter.withdrawals.length, 2);
        assertEq(withdrawalAfter.withdrawals[0].amount, 0);
        assertEq(withdrawalAfter.withdrawals[1].amount, 0);

        // Check that rewards are credited
        assertEq(DelegatorAddress.unwrap(_d).balance, nativeBalanceBefore + reward[_d][NATIVE_TOKEN]);
        assertEq(
            bico.balanceOf(DelegatorAddress.unwrap(_d)),
            bicoBalanceBefore + reward[_d][bondTokenAddress] + delegation[_d]
        );
    }

    function testTokenDelegation() external {
        // D0 delegates
        _delegate(r, ridx, d0);

        // Check Relayer State
        assertEq(ta.shares(r, d0, bondTokenAddress), uint256(delegation[d0]).fp());
        assertEq(ta.shares(r, d0, NATIVE_TOKEN), uint256(delegation[d0]).fp());

        // Check Global Counters
        assertEq(ta.totalShares(r, bondTokenAddress), uint256(delegation[d0]).fp());
        assertEq(ta.totalShares(r, NATIVE_TOKEN), uint256(delegation[d0]).fp());
        assertEq(ta.totalDelegation(r), uint256(delegation[d0]));

        // Add reward for BICO
        _increaseRewards(r, bondTokenAddress, 0.005 ether);

        // D1 delegates
        _delegate(r, ridx, d1);

        // Check Relayer State
        FixedPointType expectedBondTokenSharePrice = uint256(delegation[d0] + 0.005 ether).fp().div(delegation[d0]);
        FixedPointType expectedD1BondTokenShares = uint256(delegation[d1]).fp() / expectedBondTokenSharePrice;
        assertEq(ta.shares(r, d1, bondTokenAddress), expectedD1BondTokenShares);
        assertEq(ta.shares(r, d1, NATIVE_TOKEN), uint256(delegation[d1]).fp());

        // Check Global Counters
        assertEq(ta.totalShares(r, bondTokenAddress), uint256(delegation[d0]).fp() + expectedD1BondTokenShares);
        assertEq(ta.totalShares(r, NATIVE_TOKEN), uint256(delegation[d0] + delegation[d1]).fp());
        assertEq(ta.totalDelegation(r), uint256(delegation[d2]));

        // Add reward for BICO
        _increaseRewards(r, bondTokenAddress, 0.1 ether);
        // Add reward for Native
        _increaseRewards(r, NATIVE_TOKEN, 0.1 ether);

        // D2 delegates
        _delegate(r, ridx, d2);

        // Check Relayer State
        expectedBondTokenSharePrice =
            uint256(delegation[d2] + 0.105 ether).fp() / (uint256(delegation[d0]).fp() + expectedD1BondTokenShares);
        FixedPointType expectedD2BondTokenShares = uint256(delegation[d2]).fp() / expectedBondTokenSharePrice;
        assertEq(ta.shares(r, d2, bondTokenAddress), expectedD2BondTokenShares);

        FixedPointType expectedNativeTokenSharePrice =
            uint256(delegation[d2] + 0.1 ether).fp() / (uint256(delegation[d0] + delegation[d1]).fp());
        FixedPointType expectedD2NativeTokenShares = uint256(delegation[d2]).fp() / expectedNativeTokenSharePrice;
        assertEq(ta.shares(r, d2, NATIVE_TOKEN), expectedD2NativeTokenShares);

        // Check Global Counters
        assertEq(
            ta.totalShares(r, bondTokenAddress),
            uint256(delegation[d0]).fp() + expectedD1BondTokenShares + expectedD2BondTokenShares
        );
        assertEq(
            ta.totalShares(r, NATIVE_TOKEN), uint256(delegation[d0] + delegation[d1]).fp() + expectedD2NativeTokenShares
        );
        assertEq(ta.totalDelegation(r), uint256(6000 ether));
    }

    function testUndelegate() external {
        // Delegation
        _delegate(r, ridx, d0);
        _increaseRewards(r, bondTokenAddress, 1 ether);
        _delegate(r, ridx, d1);
        _increaseRewards(r, bondTokenAddress, 0.1 ether);
        _increaseRewards(r, NATIVE_TOKEN, 0.1 ether);
        _delegate(r, ridx, d2);
        _increaseRewards(r, bondTokenAddress, 0.1 ether);
        _increaseRewards(r, NATIVE_TOKEN, 0.1 ether);

        // Undelegation by D0
        _undelegate(r, d0, true, true);

        // Undelegation by D1
        _undelegate(r, d1, true, true);

        // Undelegation by D2
        _undelegate(r, d2, true, true);

        // Check reward values are positive
        assertTrue(reward[d0][NATIVE_TOKEN] > 0);
        assertTrue(reward[d0][bondTokenAddress] > 0);
        assertTrue(reward[d1][NATIVE_TOKEN] > 0);
        assertTrue(reward[d1][bondTokenAddress] > 0);
        assertTrue(reward[d2][NATIVE_TOKEN] > 0);
        assertTrue(reward[d2][bondTokenAddress] > 0);

        // Sum of rewards should be equal to the total rewards added
        assertApproxEqAbs(
            reward[d0][NATIVE_TOKEN] + reward[d1][NATIVE_TOKEN] + reward[d2][NATIVE_TOKEN],
            0.2 ether,
            REWARDS_MAX_ABSOLUTE_ERROR
        );
        assertApproxEqAbs(
            reward[d0][bondTokenAddress] + reward[d1][bondTokenAddress] + reward[d2][bondTokenAddress],
            1.2 ether,
            REWARDS_MAX_ABSOLUTE_ERROR
        );
    }

    function testWithdraw() external {
        // Delegation
        _delegate(r, ridx, d0);
        _increaseRewards(r, bondTokenAddress, 1 ether);
        _delegate(r, ridx, d1);
        _increaseRewards(r, bondTokenAddress, 0.1 ether);
        _increaseRewards(r, NATIVE_TOKEN, 0.1 ether);
        _delegate(r, ridx, d2);
        _increaseRewards(r, bondTokenAddress, 0.1 ether);
        _increaseRewards(r, NATIVE_TOKEN, 0.1 ether);

        // Undelegation
        _undelegate(r, d0, true, true);
        _undelegate(r, d1, true, true);
        _undelegate(r, d2, true, true);

        vm.warp(block.timestamp + deployParams.delegationWithdrawDelayInSec);
        _withdraw(r, d0);
        _withdraw(r, d1);
        _withdraw(r, d2);
    }

    function testUndelegatePostRelayerUnregistration() external {
        // Delegation
        _delegate(r, ridx, d0);
        _increaseRewards(r, bondTokenAddress, 1 ether);
        _delegate(r, ridx, d1);
        _increaseRewards(r, bondTokenAddress, 0.1 ether);
        _increaseRewards(r, NATIVE_TOKEN, 0.1 ether);
        _delegate(r, ridx, d2);
        _increaseRewards(r, bondTokenAddress, 0.1 ether);
        _increaseRewards(r, NATIVE_TOKEN, 0.1 ether);

        // Relayer Unregistration
        _prankRA(r);
        ta.unregister(latestRelayerState, ridx);
        _removeRelayerFromLatestState(r);

        // Undelegation by D0
        _undelegate(r, d0, true, true);

        // Undelegation by D1
        _undelegate(r, d1, true, true);

        // Undelegation by D2
        _undelegate(r, d2, true, true);

        // Check reward values are positive
        assertTrue(reward[d0][NATIVE_TOKEN] > 0);
        assertTrue(reward[d0][bondTokenAddress] > 0);
        assertTrue(reward[d1][NATIVE_TOKEN] > 0);
        assertTrue(reward[d1][bondTokenAddress] > 0);
        assertTrue(reward[d2][NATIVE_TOKEN] > 0);
        assertTrue(reward[d2][bondTokenAddress] > 0);

        // Sum of rewards should be equal to the total rewards added
        assertApproxEqAbs(
            reward[d0][NATIVE_TOKEN] + reward[d1][NATIVE_TOKEN] + reward[d2][NATIVE_TOKEN],
            0.2 ether,
            REWARDS_MAX_ABSOLUTE_ERROR
        );
        assertApproxEqAbs(
            reward[d0][bondTokenAddress] + reward[d1][bondTokenAddress] + reward[d2][bondTokenAddress],
            1.2 ether,
            REWARDS_MAX_ABSOLUTE_ERROR
        );
    }

    function testCannotDelegateToUnRegisteredRelayer() external {
        _prankRA(r);
        ta.unregister(latestRelayerState, _findRelayerIndex(r));
        _removeRelayerFromLatestState(r);

        _prankDA(d0);
        vm.expectRevert(abi.encodeWithSelector(InvalidRelayerIndex.selector));
        ta.delegate(latestRelayerState, _findRelayerIndex(r), delegation[d0]);
    }

    function testDelegationShouldUpdateCDFWithDelay() external {
        RelayerStateManager.RelayerState memory currentState = latestRelayerState;

        _delegate(r, ridx, d0);

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

    function testUnDelegationShouldUpdateCDFWithDelay() external {
        RelayerStateManager.RelayerState memory currentState = latestRelayerState;

        _delegate(r, ridx, d0);

        _moveForwardToNextEpoch();
        _sendEmptyTransaction(currentState);
        _moveForwardByWindows(deployParams.relayerStateUpdateDelayInWindows);

        currentState = latestRelayerState;

        _undelegate(r, d0, false, false);

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

    function testShouldNotAllowAdditionOfDelegationRewardsToInvalidToken() external {
        uint256 tokenIndex = ta.supportedPools().length;
        vm.expectRevert(abi.encodeWithSelector(InvalidTokenIndex.selector));
        ta.addDelegationRewards(r, tokenIndex, 1 ether);
    }

    function testShouldNotAllowAdditionOfIncorrectNativeTokenAmount() external {
        uint256 tokenIndex = _findTokenIndex(NATIVE_TOKEN);
        vm.expectRevert(abi.encodeWithSelector(NativeAmountMismatch.selector));
        _prankRA(relayerMainAddress[0]);
        ta.addDelegationRewards{value: 0.5 ether}(r, tokenIndex, 1 ether);
    }

    function testShouldNotAllowWithdrawBeforeDelay() external {
        _delegate(r, ridx, d0);
        _undelegate(r, d0, false, false);
        vm.expectRevert(
            abi.encodeWithSelector(WithdrawalNotReady.selector, block.timestamp + ta.delegationWithdrawDelayInSec())
        );
        _prankDA(d0);
        ta.withdrawDelegation(r);
    }

    function testShouldNotAllowUndelegationIfRelayerIndexIsInvalid() external {
        _delegate(r, ridx, d0);
        vm.expectRevert(abi.encodeWithSelector(InvalidRelayerIndex.selector));
        _prankDA(d0);
        ta.undelegate(latestRelayerState, r, (_findRelayerIndex(r) + 1) % relayerCount);
    }
}
