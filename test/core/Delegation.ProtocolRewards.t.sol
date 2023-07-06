// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import "test/base/TATestBase.sol";
import "ta-common/interfaces/ITAHelpers.sol";
import "ta-delegation/interfaces/ITADelegationEventsErrors.sol";
import "ta-delegation/interfaces/ITADelegationGetters.sol";

contract DelegationWithProtocolRewardsTest is TATestBase, ITAHelpers, ITADelegationEventsErrors {
    using Uint256WrapperHelper for uint256;
    using FixedPointTypeHelper for FixedPointType;

    uint256 constant REWARDS_MAX_ABSOLUTE_ERROR = 1; // 1 wei
    uint256 constant expectedDelegatorRewardAfter100Secfor9thRelayer = 1352444911769423;
    uint256 constant expectedDelegatorRewardAfter200Secfor9thRelayer = 2704889673884633;

    TokenAddress bondTokenAddress;
    uint256 constant ridx = 9;
    RelayerAddress r;
    DelegatorAddress d0;
    DelegatorAddress d1;
    DelegatorAddress d2;

    mapping(DelegatorAddress => uint256) delegation;
    mapping(DelegatorAddress => mapping(TokenAddress => uint256)) reward;

    function setUp() public override {
        super.setUp();

        supportedTokens.push(TokenAddress.wrap(address(bico)));
        supportedTokens.push(NATIVE_TOKEN);

        // Register all Relayers
        RelayerStateManager.RelayerState memory currentState = latestRelayerState;
        vm.warp(block.timestamp + deployParams.epochLengthInSec / 2);
        _registerAllNonFoundationRelayers();
        _moveForwardToNextEpoch();
        _sendEmptyTransaction(currentState);
        _moveForwardByWindows(deployParams.relayerStateUpdateDelayInWindows);

        // Approval
        for (uint256 i = 0; i < delegatorAddresses.length; ++i) {
            _prankDA(delegatorAddresses[i]);
            bico.approve(address(ta), type(uint256).max);
        }

        // Accrue protocol rewards for all relayers
        vm.warp(block.timestamp + 100);

        // Constants
        bondTokenAddress = TokenAddress.wrap(address(bico));
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

    // uint256 nativeBalanceBefore;
    // uint256 bicoBalanceBefore;
    // uint256 totalDelegationBefore;
    // FixedPointType sharesBicoBefore;
    // FixedPointType sharesNativeBefore;
    // FixedPointType totalSharesBicoBefore;
    // FixedPointType totalSharesNativeBefore;
    // uint256 claimableRewardsBicoBefore;
    // uint256 claimableRewardsNativeBefore;

    // function _undelegate(
    //     RelayerAddress _r,
    //     DelegatorAddress _d,
    //     bool _expectNonZeroNativeDelegationReward,
    //     bool _expectNonZeroBicoDeleagationReward
    // ) internal {
    //     nativeBalanceBefore = DelegatorAddress.unwrap(_d).balance;
    //     bicoBalanceBefore = bico.balanceOf(DelegatorAddress.unwrap(_d));
    //     totalDelegationBefore = ta.totalDelegation(r);
    //     sharesBicoBefore = ta.shares(_r, _d, bondTokenAddress);
    //     sharesNativeBefore = ta.shares(_r, _d, NATIVE_TOKEN);
    //     totalSharesBicoBefore = ta.totalShares(r, bondTokenAddress);
    //     totalSharesNativeBefore = ta.totalShares(r, NATIVE_TOKEN);
    //     claimableRewardsBicoBefore = ta.claimableDelegationRewards(_r, bondTokenAddress, _d);
    //     claimableRewardsNativeBefore = ta.claimableDelegationRewards(_r, NATIVE_TOKEN, _d);

    //     _prankDA(_d);
    //     ta.undelegate(latestRelayerState, _r, _findRelayerIndex(_r));

    //     // Shares should be destroyed
    //     assertEq(ta.shares(_r, _d, bondTokenAddress), FP_ZERO);
    //     assertEq(ta.shares(_r, _d, NATIVE_TOKEN), FP_ZERO);

    //     // Global counters
    //     assertEq(ta.totalShares(r, bondTokenAddress), totalSharesBicoBefore - sharesBicoBefore);
    //     assertEq(ta.totalShares(r, NATIVE_TOKEN), totalSharesNativeBefore - sharesNativeBefore);
    //     assertEq(ta.totalDelegation(r), totalDelegationBefore - delegation[_d]);

    //     // Check that rewards are credited
    //     assertTrue(DelegatorAddress.unwrap(_d).balance >= nativeBalanceBefore);
    //     assertTrue(bico.balanceOf(DelegatorAddress.unwrap(_d)) >= bicoBalanceBefore + delegation[_d]);
    //     reward[_d][NATIVE_TOKEN] = DelegatorAddress.unwrap(_d).balance - nativeBalanceBefore;
    //     reward[_d][bondTokenAddress] = bico.balanceOf(DelegatorAddress.unwrap(_d)) - bicoBalanceBefore - delegation[_d];
    //     assertEq(reward[_d][bondTokenAddress], claimableRewardsBicoBefore, "Claimable BICO Rewards Mismatch");
    //     assertEq(reward[_d][NATIVE_TOKEN], claimableRewardsNativeBefore, "Claimable Native Rewards Mismatch");

    //     if (_expectNonZeroNativeDelegationReward) {
    //         assertTrue(reward[_d][NATIVE_TOKEN] > 0);
    //     }
    //     if (_expectNonZeroBicoDeleagationReward) {
    //         assertTrue(reward[_d][bondTokenAddress] > 0);
    //     }

    //     _updateLatestStateCdf();
    // }

    function testTokenDelegation() external {
        // D0 delegates
        _delegate(r, ridx, d0);

        assertEq(ta.unclaimedDelegationRewards(r, bondTokenAddress), expectedDelegatorRewardAfter100Secfor9thRelayer);

        // Check Relayer State. The initla share price is 1.0
        assertEq(ta.shares(r, d0, bondTokenAddress), uint256(delegation[d0]).fp() / FP_ONE);

        // Check Global Counters
        assertEq(ta.totalShares(r, bondTokenAddress), uint256(delegation[d0]).fp() / FP_ONE);
        assertEq(ta.totalDelegation(r), uint256(delegation[d0]));

        // D1 delegates
        _delegate(r, ridx, d1);

        // Check Relayer State
        FixedPointType expectedBondTokenSharePrice =
            uint256(delegation[d0] + expectedDelegatorRewardAfter100Secfor9thRelayer).fp().div(delegation[d0]);
        FixedPointType expectedD1BondTokenShares = uint256(delegation[d1]).fp() / expectedBondTokenSharePrice;
        assertEq(ta.shares(r, d1, bondTokenAddress), expectedD1BondTokenShares);

        // Check Global Counters
        assertEq(ta.totalShares(r, bondTokenAddress), uint256(delegation[d0]).fp() + expectedD1BondTokenShares);
        assertEq(ta.totalDelegation(r), uint256(delegation[d2]));
    }

    function testUndelegate() external {
        // Delegation
        _delegate(r, ridx, d0);
        _delegate(r, ridx, d1);

        vm.warp(block.timestamp + 100);

        // Undelegation by D0
        _undelegate(r, d0, false, true);

        // Undelegation by D1
        _undelegate(r, d1, false, true);

        // Check reward values are positive
        assertTrue(reward[d0][bondTokenAddress] > 0);
        assertTrue(reward[d1][bondTokenAddress] > 0);

        // Sum of rewards should be equal to the total rewards generated
        assertApproxEqAbs(
            reward[d0][bondTokenAddress] + reward[d1][bondTokenAddress] + reward[d2][bondTokenAddress],
            expectedDelegatorRewardAfter200Secfor9thRelayer,
            REWARDS_MAX_ABSOLUTE_ERROR
        );
    }
}
