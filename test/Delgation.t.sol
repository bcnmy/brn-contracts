// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import "./base/TATestBase.sol";
import "ta-common/TAConstants.sol";
import "ta-common/interfaces/ITAHelpers.sol";
import "ta-delegation/interfaces/ITADelegationEventsErrors.sol";

// TODO: Testing mechanism needs to change
// TODO: Add tests for delegation affecting CDF
contract DelegationTest is TATestBase, ITAHelpers, ITADelegationEventsErrors {
    using Uint256WrapperHelper for uint256;
    using FixedPointTypeHelper for FixedPointType;

    uint256 ERROR_TOLERANCE = 0.0001e18; // 0.001%

    function setUp() public override {
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

        // Test State
        r0 = relayerMainAddress[0];
        d0 = delegatorAddresses[0];
        d1 = delegatorAddresses[1];
        t0 = supportedTokens[0];
        t1 = supportedTokens[1];
    }

    // Test State
    RelayerAddress r0;
    DelegatorAddress d0;
    DelegatorAddress d1;
    TokenAddress t0;
    TokenAddress t1;

    mapping(RelayerAddress => mapping(DelegatorAddress => uint256)) expDelegation;
    mapping(RelayerAddress => uint256) expTotalDelegation;
    mapping(RelayerAddress => mapping(DelegatorAddress => mapping(TokenAddress => uint256))) expRewards;

    uint256 totalDelegation = 0;

    function check() internal {
        assertEq(ta.delegation(r0, d0), expDelegation[r0][d0], "Delegation R0 D0");
        assertEq(ta.delegation(r0, d1), expDelegation[r0][d1], "Delegation R0 D1");

        assertEq(ta.totalDelegation(r0), expTotalDelegation[r0], "Total Delegation R0");

        assertApproxEqRel(
            ta.delegationRewardsEarned(r0, t0, d0), expRewards[r0][d0][t0], ERROR_TOLERANCE, "Rewards R0 T0 D0"
        );
        assertApproxEqRel(
            ta.delegationRewardsEarned(r0, t0, d1), expRewards[r0][d1][t0], ERROR_TOLERANCE, "Rewards R0 T0 D1"
        );
        assertApproxEqRel(
            ta.delegationRewardsEarned(r0, t1, d0), expRewards[r0][d0][t1], ERROR_TOLERANCE, "Rewards R0 T1 D0"
        );
        assertApproxEqRel(
            ta.delegationRewardsEarned(r0, t1, d1), expRewards[r0][d1][t1], ERROR_TOLERANCE, "Rewards R0 T1 D1"
        );
    }

    function delegate(RelayerAddress r, DelegatorAddress d, uint256 amount) internal {
        _prankDa(d);
        ta.delegate(latestRelayerState, _findRelayerIndex(r), amount);

        expDelegation[r][d] += amount;
        expTotalDelegation[r] += amount;
    }

    function undelegate(RelayerAddress r, DelegatorAddress d) internal {
        _prankDa(d);
        ta.undelegate(latestRelayerState, r, _findRelayerIndex(r));

        expTotalDelegation[r] -= expDelegation[r][d];
        expDelegation[r][d] = 0;
        expRewards[r][d][t0] = 0;
        expRewards[r][d][t1] = 0;
    }

    function increaseRewards(RelayerAddress r, TokenAddress t, uint256 amount) internal {
        ta.debug_increaseRewards(r, t, amount);

        if (t == NATIVE_TOKEN) {
            deal(address(ta), address(ta).balance + amount);
        } else {
            address token = TokenAddress.unwrap(t);
            IERC20 tokenContract = IERC20(token);
            deal(token, address(ta), amount + tokenContract.balanceOf(address(ta)));
        }
    }

    function testDelegation() external {
        delegate(r0, d0, 0.01 ether);
        check();

        delegate(r0, d1, 0.02 ether);
        check();
    }

    function testAccrueDelegationRewards() external {
        delegate(r0, d0, 0.01 ether);
        delegate(r0, d1, 0.02 ether);

        increaseRewards(r0, t0, 0.001 ether);
        expRewards[r0][d0][t0] += uint256(0.001 ether) * 1 / 3;
        expRewards[r0][d1][t0] += uint256(0.001 ether) * 2 / 3;
        check();

        increaseRewards(r0, t1, 0.002 ether);
        expRewards[r0][d0][t1] += uint256(0.002 ether) * 1 / 3;
        expRewards[r0][d1][t1] += uint256(0.002 ether) * 2 / 3;
        check();

        delegate(r0, d0, 0.01 ether);
        check();

        increaseRewards(r0, t0, 0.005 ether);
        expRewards[r0][d0][t0] += uint256(0.005 ether) * 1 / 2;
        expRewards[r0][d1][t0] += uint256(0.005 ether) * 1 / 2;
    }

    // TODO: Reach a level where abs equality is possible
    function testClaimDelegationRewards() external {
        delegate(r0, d0, 0.01 ether);
        delegate(r0, d1, 0.02 ether);

        increaseRewards(r0, t0, 0.001 ether);
        expRewards[r0][d0][t0] += uint256(0.001 ether) * 1 / 3;
        expRewards[r0][d1][t0] += uint256(0.001 ether) * 2 / 3;

        increaseRewards(r0, t1, 0.002 ether);
        expRewards[r0][d0][t1] += uint256(0.002 ether) * 1 / 3;
        expRewards[r0][d1][t1] += uint256(0.002 ether) * 2 / 3;

        delegate(r0, d0, 0.01 ether);

        increaseRewards(r0, t0, 0.005 ether);
        expRewards[r0][d0][t0] += uint256(0.005 ether) * 1 / 2;
        expRewards[r0][d1][t0] += uint256(0.005 ether) * 1 / 2;

        uint256 expD0t0bal = bico.balanceOf(DelegatorAddress.unwrap(d0)) + expRewards[r0][d0][t0];
        uint256 expD0t1bal = DelegatorAddress.unwrap(d0).balance + expRewards[r0][d0][t1];
        undelegate(r0, d0);
        assertApproxEqRel(bico.balanceOf(DelegatorAddress.unwrap(d0)), expD0t0bal, ERROR_TOLERANCE);
        assertApproxEqRel(DelegatorAddress.unwrap(d0).balance, expD0t1bal, ERROR_TOLERANCE);

        uint256 expD1t0bal = bico.balanceOf(DelegatorAddress.unwrap(d1)) + expRewards[r0][d1][t0];
        uint256 expD1t1bal = DelegatorAddress.unwrap(d1).balance + expRewards[r0][d1][t1];
        undelegate(r0, d1);
        assertApproxEqRel(bico.balanceOf(DelegatorAddress.unwrap(d1)), expD1t0bal, ERROR_TOLERANCE);
        assertApproxEqRel(DelegatorAddress.unwrap(d1).balance, expD1t1bal, ERROR_TOLERANCE);
    }

    function testClaimDelegationRewardsAfterRelayerDeRegistration() external {
        delegate(r0, d0, 0.01 ether);
        delegate(r0, d1, 0.02 ether);

        increaseRewards(r0, t0, 0.001 ether);
        expRewards[r0][d0][t0] += uint256(0.001 ether) * 1 / 3;
        expRewards[r0][d1][t0] += uint256(0.001 ether) * 2 / 3;

        increaseRewards(r0, t1, 0.002 ether);
        expRewards[r0][d0][t1] += uint256(0.002 ether) * 1 / 3;
        expRewards[r0][d1][t1] += uint256(0.002 ether) * 2 / 3;

        delegate(r0, d0, 0.01 ether);

        increaseRewards(r0, t0, 0.005 ether);
        expRewards[r0][d0][t0] += uint256(0.005 ether) * 1 / 2;
        expRewards[r0][d1][t0] += uint256(0.005 ether) * 1 / 2;

        _prankRA(r0);
        ta.unregister(latestRelayerState, _findRelayerIndex(r0));
        _removeRelayerFromLatestState(r0);

        uint256 expD0t0bal = bico.balanceOf(DelegatorAddress.unwrap(d0)) + expRewards[r0][d0][t0];
        uint256 expD0t1bal = DelegatorAddress.unwrap(d0).balance + expRewards[r0][d0][t1];
        undelegate(r0, d0);
        assertApproxEqRel(bico.balanceOf(DelegatorAddress.unwrap(d0)), expD0t0bal, ERROR_TOLERANCE);
        assertApproxEqRel(DelegatorAddress.unwrap(d0).balance, expD0t1bal, ERROR_TOLERANCE);

        uint256 expD1t0bal = bico.balanceOf(DelegatorAddress.unwrap(d1)) + expRewards[r0][d1][t0];
        uint256 expD1t1bal = DelegatorAddress.unwrap(d1).balance + expRewards[r0][d1][t1];
        undelegate(r0, d1);
        assertApproxEqRel(bico.balanceOf(DelegatorAddress.unwrap(d1)), expD1t0bal, ERROR_TOLERANCE);
        assertApproxEqRel(DelegatorAddress.unwrap(d1).balance, expD1t1bal, ERROR_TOLERANCE);
    }

    function testCannotDelegateToUnRegisteredRelayer() external {
        _prankRA(r0);
        ta.unregister(latestRelayerState, _findRelayerIndex(r0));
        _removeRelayerFromLatestState(r0);

        _prankDa(d0);
        vm.expectRevert(abi.encodeWithSelector(InvalidRelayerIndex.selector));
        ta.delegate(latestRelayerState, _findRelayerIndex(r0), 0.01 ether);
    }
}