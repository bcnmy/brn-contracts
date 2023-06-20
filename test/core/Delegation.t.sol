// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import "test/base/TATestBase.sol";
import "ta-common/interfaces/ITAHelpers.sol";
import "ta-delegation/interfaces/ITADelegationEventsErrors.sol";

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
        RelayerState memory currentState = latestRelayerState;
        _registerAllNonFoundationRelayers();
        _moveForwardToNextEpoch();
        _sendEmptyTransaction(currentState);
        _moveForwardByWindows(deployParams.relayerStateUpdateDelayInWindows);

        // Approval
        for (uint256 i = 0; i < delegatorAddresses.length; ++i) {
            _prankDa(delegatorAddresses[i]);
            bico.approve(address(ta), type(uint256).max);
        }

        // Accrue protocol rewards for all relayers
        vm.warp(block.timestamp + 100);

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

    function _increaseRewards(RelayerAddress _r, TokenAddress _t, uint256 _amount) internal {
        uint256 rewardsBefore = ta.unclaimedDelegationRewards(_r, _t);
        ta.debug_increaseRewards(_r, _t, _amount);
        assertEq(ta.unclaimedDelegationRewards(_r, _t), rewardsBefore + _amount);

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
        _prankDa(_d);
        ta.delegate(latestRelayerState, _ridx, delegation[_d]);
        assertEq(bico.balanceOf(DelegatorAddress.unwrap(_d)), balanceBefore - delegation[_d]);
        assertEq(ta.delegation(_r, _d), delegationBefore + delegation[_d]);

        _updateLatestStateCdf();
    }

    function _undelegate(
        RelayerAddress _r,
        DelegatorAddress _d,
        bool _expectNonZeroNativeDelegationReward,
        bool _expectNonZeroBicoDeleagationReward
    ) internal {
        uint256 nativeBalanceBefore = DelegatorAddress.unwrap(_d).balance;
        uint256 bicoBalanceBefore = bico.balanceOf(DelegatorAddress.unwrap(_d));
        uint256 totalDelegationBefore = ta.totalDelegation(r);
        FixedPointType sharesBicoBefore = ta.shares(_r, _d, bondTokenAddress);
        FixedPointType sharesNativeBefore = ta.shares(_r, _d, NATIVE_TOKEN);
        FixedPointType totalSharesBicoBefore = ta.totalShares(r, bondTokenAddress);
        FixedPointType totalSharesNativeBefore = ta.totalShares(r, NATIVE_TOKEN);
        uint256 claimableRewardsBicoBefore = ta.claimableDelegationRewards(_r, bondTokenAddress, _d);
        uint256 claimableRewardsNativeBefore = ta.claimableDelegationRewards(_r, NATIVE_TOKEN, _d);

        _prankDa(_d);
        ta.undelegate(latestRelayerState, _r);

        // Shares should be destroyed
        assertEq(ta.shares(_r, _d, bondTokenAddress), FP_ZERO);
        assertEq(ta.shares(_r, _d, NATIVE_TOKEN), FP_ZERO);

        // Global counters
        assertEq(ta.totalShares(r, bondTokenAddress), totalSharesBicoBefore - sharesBicoBefore);
        assertEq(ta.totalShares(r, NATIVE_TOKEN), totalSharesNativeBefore - sharesNativeBefore);
        assertEq(ta.totalDelegation(r), totalDelegationBefore - delegation[_d]);

        // Check that rewards are credited
        assertTrue(DelegatorAddress.unwrap(_d).balance >= nativeBalanceBefore);
        assertTrue(bico.balanceOf(DelegatorAddress.unwrap(_d)) >= bicoBalanceBefore + delegation[_d]);
        reward[_d][NATIVE_TOKEN] = DelegatorAddress.unwrap(_d).balance - nativeBalanceBefore;
        reward[_d][bondTokenAddress] = bico.balanceOf(DelegatorAddress.unwrap(_d)) - bicoBalanceBefore - delegation[_d];
        assertEq(reward[_d][bondTokenAddress], claimableRewardsBicoBefore);
        assertEq(reward[_d][NATIVE_TOKEN], claimableRewardsNativeBefore);

        if (_expectNonZeroNativeDelegationReward) {
            assertTrue(reward[_d][NATIVE_TOKEN] > 0);
        }
        if (_expectNonZeroBicoDeleagationReward) {
            assertTrue(reward[_d][bondTokenAddress] > 0);
        }

        _updateLatestStateCdf();
    }

    // TODO: Test protoocl reward accrual

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

    function testWithdrawPostRelayerUnregistration() external {
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

        _prankDa(d0);
        vm.expectRevert(abi.encodeWithSelector(InvalidRelayerIndex.selector));
        ta.delegate(latestRelayerState, _findRelayerIndex(r), delegation[d0]);
    }

    function testDelegationShouldUpdateCDFWithDelay() external {
        RelayerState memory currentState = latestRelayerState;

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
        RelayerState memory currentState = latestRelayerState;

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
}
