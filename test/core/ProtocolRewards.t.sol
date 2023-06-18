// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import "test/base/TATestBase.sol";
import "ta-transaction-allocation/interfaces/ITATransactionAllocationEventsErrors.sol";
import "ta-relayer-management/interfaces/ITARelayerManagementEventsErrors.sol";
import "ta-common/interfaces/ITAHelpers.sol";

contract ProtocolRewardsTest is
    TATestBase,
    ITATransactionAllocationEventsErrors,
    ITARelayerManagementEventsErrors,
    ITAHelpers,
    IMinimalApplicationEventsErrors
{
    using FixedPointTypeHelper for FixedPointType;
    using Uint256WrapperHelper for uint256;

    uint256 constant TEST_SETUP_PROTOCOL_REWARD_RATE = 743844708255694;
    uint256 constant FOUNDATION_RELAYER_POST_REGISTRATION_REWARD_RATE = 100300000000000;
    uint256 constant REWARDS_MAX_ABSOLUTE_ERROR = 1; // 1 wei

    mapping(RelayerAddress => uint256) claimableRewards;

    function setUp() public override {
        if (tx.gasprice == 0) {
            fail("Gas Price is 0. Please set it to 1 gwei or more.");
        }

        super.setUp();

        RelayerState memory currentState = latestRelayerState;
        vm.warp(block.timestamp + deployParams.epochLengthInSec / 2);
        _registerAllNonFoundationRelayers();
        _moveForwardToNextEpoch();
        _sendEmptyTransaction(currentState);
        _moveForwardByWindows(deployParams.relayerStateUpdateDelayInWindows);
    }

    function _checkTotalShares() internal {
        FixedPointType totalShares = FixedPointType.wrap(0);
        for (uint256 i = 0; i < relayerCount; ++i) {
            totalShares = totalShares + ta.relayerInfo(relayerMainAddress[i]).rewardShares;
        }
        _assertEqFp(totalShares, ta.totalProtocolRewardShares());
    }

    function testProtocolRewardRates() external {
        // Check Reward Rate at current stake
        assertEq(ta.protocolRewardRate(), TEST_SETUP_PROTOCOL_REWARD_RATE);

        // Check Reward Rate at 10 relayers each with minimum stake
        ta.debug_setTotalStake(ta.minimumStakeAmount() * 10);
        ta.debug_setRelayerCount(10);
        assertEq(ta.protocolRewardRate(), 317176449314888);

        // Check Reward Rate at 1 relayer with minimum stake
        ta.debug_setTotalStake(ta.minimumStakeAmount());
        ta.debug_setRelayerCount(1);
        assertEq(ta.protocolRewardRate(), FOUNDATION_RELAYER_POST_REGISTRATION_REWARD_RATE);
    }

    FixedPointType[10] initialExpectedRelayerShares = [
        FixedPointType.wrap(10000000000000000000000000000000000000000000000),
        FixedPointType.wrap(19999989970005030042477433697567000670149163920),
        FixedPointType.wrap(29999984955007545063716150546350501005223745880),
        FixedPointType.wrap(39999979940010060084954867395134001340298327840),
        FixedPointType.wrap(49999974925012575106193584243917501675372909800),
        FixedPointType.wrap(59999969910015090127432301092701002010447491760),
        FixedPointType.wrap(69999964895017605148671017941484502345522073720),
        FixedPointType.wrap(79999959880020120169909734790268002680596655680),
        FixedPointType.wrap(89999954865022635191148451639051503015671237640),
        FixedPointType.wrap(99999949850025150212387168487835003350745819600)
    ];

    function testRelayersShouldHaveCorrectInitialProtocolRewardShares() external {
        // At time t=0, share price = 1. Therefore shares=stake
        _assertEqFp(
            ta.relayerInfo(relayerMainAddress[0]).stake.fp(), ta.relayerInfo(relayerMainAddress[0]).rewardShares
        );
        _assertEqFp(initialExpectedRelayerShares[0], ta.relayerInfo(relayerMainAddress[0]).rewardShares);

        // we waited for half an epoch before registering other relayers so that the foundation relayer has accrued some rewards
        // check setUp()
        uint256 initialRewardsGenerated =
            (FOUNDATION_RELAYER_POST_REGISTRATION_REWARD_RATE * (deployParams.epochLengthInSec / 2));
        FixedPointType newSharePrice = (initialRelayerStake[relayerMainAddress[0]].fp() + initialRewardsGenerated.fp())
            / ta.relayerInfo(relayerMainAddress[0]).rewardShares;

        for (uint256 i = 1; i < relayerCount; ++i) {
            RelayerAddress relayerAddress = relayerMainAddress[i];
            _assertEqFp(
                ta.relayerInfo(relayerAddress).stake.fp() / newSharePrice, ta.relayerInfo(relayerAddress).rewardShares
            );
            _assertEqFp(initialExpectedRelayerShares[i], ta.relayerInfo(relayerAddress).rewardShares);
        }

        _checkTotalShares();
    }

    uint256[10] expectedRelayerRewardsAfter100Sec = [
        6367445590020546,
        2434400841184962,
        3651601261777443,
        4868801682369923,
        6086002102962405,
        7303202523554886,
        8520402944147366,
        9737603364739847,
        10954803785332328,
        12172004205924809
    ];

    function testRelayersShouldAccrueRewardsProportionally() external {
        // Foundation relayer has been registered for 1.5 epoch + 1 window. It should have accrued rewards
        uint256 initialFoundationRelayerRewards =
            FOUNDATION_RELAYER_POST_REGISTRATION_REWARD_RATE * (block.timestamp - deploymentTimestamp);
        assertEq(ta.relayerClaimableProtocolRewards(relayerMainAddress[0]), initialFoundationRelayerRewards);

        // Other relayers were just registered, therefore they should have no rewards
        for (uint256 i = 1; i < relayerCount; ++i) {
            assertEq(ta.relayerClaimableProtocolRewards(relayerMainAddress[i]), 0);
        }

        uint256 t = 100;
        vm.warp(block.timestamp + t);

        // All relayers should have accrued rewards proportionally in the last t s as per TEST_SETUP_PROTOCOL_REWARD_RATE
        uint256 expectedTotalRewardsAccrued = t * TEST_SETUP_PROTOCOL_REWARD_RATE + initialFoundationRelayerRewards;
        FixedPointType newPrice =
            (ta.totalStake().fp() + expectedTotalRewardsAccrued.fp()) / ta.totalProtocolRewardShares();

        for (uint256 i = 0; i < relayerCount; ++i) {
            RelayerAddress relayerAddress = relayerMainAddress[i];
            uint256 totalReward =
                (initialExpectedRelayerShares[i] * newPrice - initialRelayerStake[relayerAddress].fp()).u256();
            uint256 delegatorPoolPremiumShare =
                i == 0 ? deployParams.foundationDelegatorPoolPremiumShare : delegatorPoolPremiumShare;
            uint256 delegatorShare = totalReward * delegatorPoolPremiumShare / (PERCENTAGE_MULTIPLIER * 100);
            uint256 relayerShare = totalReward - delegatorShare;
            assertEq(ta.relayerClaimableProtocolRewards(relayerAddress), relayerShare);
            assertEq(ta.relayerClaimableProtocolRewards(relayerAddress), expectedRelayerRewardsAfter100Sec[i]);
        }
    }

    function testRelayerUnregistrationShouldAutomaticallyClaimRewards() external {
        uint256 t = 100;
        vm.warp(block.timestamp + t);

        for (uint256 i = 0; i < relayerCount - 1; ++i) {
            RelayerAddress relayerAddress = relayerMainAddress[i];
            uint256 balance = bico.balanceOf(RelayerAddress.unwrap(relayerAddress));

            _prankRA(relayerAddress);
            ta.unregister(latestRelayerState, _findRelayerIndex(relayerAddress));
            _removeRelayerFromLatestState(relayerAddress);

            assertApproxEqAbs(
                bico.balanceOf(RelayerAddress.unwrap(relayerAddress)),
                balance + expectedRelayerRewardsAfter100Sec[i],
                REWARDS_MAX_ABSOLUTE_ERROR
            );
            assertEq(ta.relayerClaimableProtocolRewards(relayerAddress), 0);
            _assertEqFp(ta.relayerInfo(relayerAddress).rewardShares, FP_ZERO);
            _checkTotalShares();
        }
    }

    function testRelayersShouldBeAbleToClaimRewards() external {
        uint256 t = 100;
        vm.warp(block.timestamp + t);

        for (uint256 i = 0; i < relayerCount; ++i) {
            RelayerAddress relayerAddress = relayerMainAddress[i];
            uint256 balance = bico.balanceOf(RelayerAddress.unwrap(relayerAddress));

            _prankRA(relayerAddress);
            ta.claimProtocolReward();

            assertEq(
                bico.balanceOf(RelayerAddress.unwrap(relayerAddress)), balance + expectedRelayerRewardsAfter100Sec[i]
            );
            assertEq(ta.relayerClaimableProtocolRewards(relayerAddress), 0);
            _checkTotalShares();
        }
    }

    function testExitingRelayersShouldNotAffectClaimableRewards() external {
        uint256 t = 100;
        vm.warp(block.timestamp + t);

        for (uint256 i = 0; i < relayerCount; ++i) {
            RelayerAddress relayerAddress = relayerMainAddress[i];
            uint256 balance = bico.balanceOf(RelayerAddress.unwrap(relayerAddress));

            _prankRA(relayerAddress);
            ta.claimProtocolReward();

            assertApproxEqAbs(
                bico.balanceOf(RelayerAddress.unwrap(relayerAddress)),
                balance + expectedRelayerRewardsAfter100Sec[i],
                REWARDS_MAX_ABSOLUTE_ERROR
            );
            assertEq(ta.relayerClaimableProtocolRewards(relayerAddress), 0);

            // Unregister all relayers except the last one
            if (i != relayerCount - 1) {
                _prankRA(relayerAddress);
                ta.unregister(latestRelayerState, _findRelayerIndex(relayerAddress));
                _removeRelayerFromLatestState(relayerAddress);
                _assertEqFp(ta.relayerInfo(relayerAddress).rewardShares, FP_ZERO);
            }
        }
    }

    uint256[10] expectedDelegatorRewardsAfter100Sec = [
        0, // Foundation relayer specified the delegator pool premium share as 0
        270488982353884,
        405733473530826,
        540977964707769,
        676222455884711,
        811466947061653,
        946711438238596,
        1081955929415538,
        1217200420592480,
        1352444911769423
    ];

    function testRelayerClaimShouldCreditRewardsToDelegators() external {
        uint256 t = 100;
        vm.warp(block.timestamp + t);

        for (uint256 i = 0; i < relayerCount; ++i) {
            RelayerAddress relayerAddress = relayerMainAddress[i];
            uint256 delegatorUnclaimedBalance =
                ta.unclaimedDelegationRewards(relayerAddress, TokenAddress.wrap(address(bico)));

            _prankRA(relayerAddress);
            ta.claimProtocolReward();

            assertApproxEqAbs(
                ta.unclaimedDelegationRewards(relayerAddress, TokenAddress.wrap(address(bico))),
                delegatorUnclaimedBalance + expectedDelegatorRewardsAfter100Sec[i],
                REWARDS_MAX_ABSOLUTE_ERROR
            );
            assertEq(ta.relayerClaimableProtocolRewards(relayerAddress), 0);
        }
    }

    uint256[9] expectedRewardRatesAsRelayersExit = [
        737051463603458,
        723273585858076,
        702100000000000,
        672832854429686,
        634352898629776,
        584844475052983,
        521174087997475,
        437197564037129,
        317176449314888
    ];

    function testExitingRelayersShouldLowerRewardRate() external {
        for (uint256 i = 0; i < relayerCount - 1; ++i) {
            RelayerAddress relayerAddress = relayerMainAddress[i];
            _prankRA(relayerAddress);
            ta.unregister(latestRelayerState, _findRelayerIndex(relayerAddress));
            _removeRelayerFromLatestState(relayerAddress);

            assertEq(ta.protocolRewardRate(), expectedRewardRatesAsRelayersExit[i]);
        }
    }

    function testActiveRelayerPenalization() external {
        uint256 t = 100;
        vm.warp(block.timestamp + t);

        // Setup to penalize relayer 9
        uint256 inactiveRelayerIndex = 9;
        RelayerAddress inactiveRelayer = relayerMainAddress[inactiveRelayerIndex];
        ta.debug_setTotalTransactionsProcessed(1000);
        for (uint256 i = 0; i < relayerCount; ++i) {
            if (i == inactiveRelayerIndex) continue;
            ta.debug_setTransactionsProcessedByRelayer(relayerMainAddress[i], 1000);
        }

        assertEq(
            ta.relayerClaimableProtocolRewards(inactiveRelayer), expectedRelayerRewardsAfter100Sec[inactiveRelayerIndex]
        );
        _assertEqFp(ta.relayerInfo(inactiveRelayer).rewardShares, initialExpectedRelayerShares[inactiveRelayerIndex]);

        RelayerState memory currentState = latestRelayerState;
        _moveForwardToNextEpoch();

        FixedPointType initialShares = ta.totalProtocolRewardShares();
        for (uint256 i = 0; i < relayerCount; ++i) {
            RelayerAddress relayer = relayerMainAddress[i];
            claimableRewards[relayer] = ta.relayerClaimableProtocolRewards(relayer);
            assertTrue(claimableRewards[relayer] > expectedDelegatorRewardsAfter100Sec[i]);
        }

        // Penalize the relayer
        _sendEmptyTransaction(currentState);

        // Relayer Was penalized
        assertTrue(ta.relayerInfo(inactiveRelayer).status == RelayerStatus.Active);
        assertEq(
            initialRelayerStake[inactiveRelayer] - ta.relayerInfo(inactiveRelayer).stake,
            _calculatePenalty(initialRelayerStake[inactiveRelayer])
        );

        // The claimable rewards should not have changed for any relayer
        for (uint256 i = 0; i < relayerCount; ++i) {
            RelayerAddress relayer = relayerMainAddress[i];
            assertEq(ta.relayerClaimableProtocolRewards(relayer), claimableRewards[relayer]);
        }

        // Shares should have decreased
        assertTrue(ta.relayerInfo(inactiveRelayer).rewardShares < initialExpectedRelayerShares[inactiveRelayerIndex]);
        // Total Shares should have decreased
        _checkTotalShares();
        assertTrue(ta.totalProtocolRewardShares() < initialShares);

        // Claim the rewards
        for (uint256 i = 0; i < relayerCount; ++i) {
            RelayerAddress relayerAddress = relayerMainAddress[i];
            uint256 balance = bico.balanceOf(RelayerAddress.unwrap(relayerAddress));
            _prankRA(relayerAddress);
            ta.claimProtocolReward();
            assertEq(bico.balanceOf(RelayerAddress.unwrap(relayerAddress)), balance + claimableRewards[relayerAddress]);
        }
    }

    function testShouldHandleRewardsForExitingRelayersCorrectly() external {
        uint256 t = 100;
        vm.warp(block.timestamp + t);

        uint256 relayerIndex = 1;
        RelayerAddress relayer = relayerMainAddress[relayerIndex];

        uint256 preUnregisterRelayerBalance = bico.balanceOf(RelayerAddress.unwrap(relayer));
        uint256 preUnregisterDelegatorBalance = ta.unclaimedDelegationRewards(relayer, TokenAddress.wrap(address(bico)));

        _prankRA(relayer);
        ta.unregister(latestRelayerState, _findRelayerIndex(relayer));
        _removeRelayerFromLatestState(relayer);

        // Relayer rewards should have been transferred
        assertEq(
            bico.balanceOf(RelayerAddress.unwrap(relayer)),
            preUnregisterRelayerBalance + expectedRelayerRewardsAfter100Sec[relayerIndex]
        );
        // Delegator rewards should have been transferred
        assertEq(
            ta.unclaimedDelegationRewards(relayer, TokenAddress.wrap(address(bico))),
            preUnregisterDelegatorBalance + expectedDelegatorRewardsAfter100Sec[relayerIndex]
        );
        // Relayer shares should have been removed
        _assertEqFp(ta.relayerInfo(relayer).rewardShares, FP_ZERO);
        _checkTotalShares();
        // Relayer should have no claimable rewards
        assertEq(ta.relayerClaimableProtocolRewards(relayer), 0);
        // Claimable rewards for other relayers should not have changed
        for (uint256 i = 0; i < relayerCount; ++i) {
            if (i == relayerIndex) continue;
            assertEq(ta.relayerClaimableProtocolRewards(relayerMainAddress[i]), expectedRelayerRewardsAfter100Sec[i]);
        }
    }

    function testExitingRelayerPenalization() external {
        uint256 t = 100;
        vm.warp(block.timestamp + t);

        // Setup to penalize relayer 9
        uint256 inactiveRelayerIndex = 9;
        RelayerAddress inactiveRelayer = relayerMainAddress[inactiveRelayerIndex];
        ta.debug_setTotalTransactionsProcessed(1000);
        for (uint256 i = 0; i < relayerCount; ++i) {
            if (i == inactiveRelayerIndex) continue;
            ta.debug_setTransactionsProcessedByRelayer(relayerMainAddress[i], 1000);
        }
        // Unregister the relayer
        RelayerState memory currentState = latestRelayerState;
        _prankRA(inactiveRelayer);
        ta.unregister(latestRelayerState, _findRelayerIndex(inactiveRelayer));
        _removeRelayerFromLatestState(inactiveRelayer);

        _moveForwardToNextEpoch();

        FixedPointType initialShares = ta.totalProtocolRewardShares();
        for (uint256 i = 0; i < relayerCount; ++i) {
            RelayerAddress relayer = relayerMainAddress[i];
            claimableRewards[relayer] = ta.relayerClaimableProtocolRewards(relayer);

            if (i == inactiveRelayerIndex) {
                assertTrue(claimableRewards[relayer] == 0);
            } else {
                assertTrue(claimableRewards[relayer] > expectedDelegatorRewardsAfter100Sec[i]);
            }
        }

        // Penalize the relayer
        _sendEmptyTransaction(currentState);

        // Relayer Was penalized
        assertTrue(ta.relayerInfo(inactiveRelayer).status == RelayerStatus.Exiting);
        assertEq(
            initialRelayerStake[inactiveRelayer] - ta.relayerInfo(inactiveRelayer).stake,
            _calculatePenalty(initialRelayerStake[inactiveRelayer])
        );

        // The claimable rewards should not have changed for any relayer
        for (uint256 i = 0; i < relayerCount; ++i) {
            RelayerAddress relayer = relayerMainAddress[i];
            assertEq(ta.relayerClaimableProtocolRewards(relayer), claimableRewards[relayer]);
        }

        // Total Shares should be the same
        _checkTotalShares();
        _assertEqFp(ta.totalProtocolRewardShares(), initialShares);
    }

    function testShouldPreventExitingRelayerFromClaimingProtocolRewards() external {
        uint256 t = 100;
        vm.warp(block.timestamp + t);

        // Unregister the relayer
        RelayerAddress relayer = relayerMainAddress[9];
        _prankRA(relayer);
        ta.unregister(latestRelayerState, _findRelayerIndex(relayer));
        _removeRelayerFromLatestState(relayer);

        vm.expectRevert(abi.encodeWithSelector(InvalidRelayer.selector, [relayer]));
        _prankRA(relayer);
        ta.claimProtocolReward();
    }

    function testActiveRelayerJailing() external {
        uint256 t = 100;
        vm.warp(block.timestamp + t);

        // Setup to jail relayer 0. If relayer 0 is penalized, it will get jailed
        uint256 inactiveRelayerIndex = 0;
        RelayerAddress inactiveRelayer = relayerMainAddress[inactiveRelayerIndex];
        ta.debug_setTotalTransactionsProcessed(1000);
        for (uint256 i = 0; i < relayerCount; ++i) {
            if (i == inactiveRelayerIndex) continue;
            ta.debug_setTransactionsProcessedByRelayer(relayerMainAddress[i], 1000);
        }

        assertEq(
            ta.relayerClaimableProtocolRewards(inactiveRelayer), expectedRelayerRewardsAfter100Sec[inactiveRelayerIndex]
        );
        _assertEqFp(ta.relayerInfo(inactiveRelayer).rewardShares, initialExpectedRelayerShares[inactiveRelayerIndex]);

        RelayerState memory currentState = latestRelayerState;
        _moveForwardToNextEpoch();

        FixedPointType initialShares = ta.totalProtocolRewardShares();
        for (uint256 i = 0; i < relayerCount; ++i) {
            RelayerAddress relayer = relayerMainAddress[i];
            claimableRewards[relayer] = ta.relayerClaimableProtocolRewards(relayer);
            assertTrue(claimableRewards[relayer] > expectedDelegatorRewardsAfter100Sec[i]);
        }

        uint256 initialJailedRelayerDelegatorUnclaimedRewards =
            ta.unclaimedDelegationRewards(inactiveRelayer, TokenAddress.wrap(address(bico)));
        uint256 initialJailedRelayerUnclaimedRewards = ta.relayerInfo(inactiveRelayer).unpaidProtocolRewards;

        // Penalize and jail the relayer
        _sendEmptyTransaction(currentState);

        // Relayer was jailed
        assertTrue(ta.relayerInfo(inactiveRelayer).status == RelayerStatus.Jailed);
        assertEq(
            initialRelayerStake[inactiveRelayer] - ta.relayerInfo(inactiveRelayer).stake,
            _calculatePenalty(initialRelayerStake[inactiveRelayer])
        );

        // The claimable rewards should not have changed for any relayer other than the jailed one
        for (uint256 i = 0; i < relayerCount; ++i) {
            if (i == inactiveRelayerIndex) continue;

            RelayerAddress relayer = relayerMainAddress[i];
            assertEq(ta.relayerClaimableProtocolRewards(relayer), claimableRewards[relayer]);
        }
        // Jailed Relayer should have 0 claimable rewards
        assertEq(ta.relayerClaimableProtocolRewards(inactiveRelayer), 0);
        // The delegator rewards should have been credited for the jailed relayer
        assertEq(
            ta.unclaimedDelegationRewards(inactiveRelayer, TokenAddress.wrap(address(bico))),
            initialJailedRelayerDelegatorUnclaimedRewards + expectedDelegatorRewardsAfter100Sec[inactiveRelayerIndex]
        );
        // The relayer rewards should be saved to relayer info, even if they are not claimable
        assertEq(
            ta.relayerInfo(inactiveRelayer).unpaidProtocolRewards,
            initialJailedRelayerUnclaimedRewards + expectedRelayerRewardsAfter100Sec[inactiveRelayerIndex]
        );

        // Shares should have destroyed
        _assertEqFp(ta.relayerInfo(inactiveRelayer).rewardShares, FP_ZERO);
        // Total Shares should have decreased
        _checkTotalShares();
        assertTrue(ta.totalProtocolRewardShares() < initialShares);

        // Claim the rewards for other relayers
        for (uint256 i = 0; i < relayerCount; ++i) {
            if (i == inactiveRelayerIndex) continue;

            RelayerAddress relayerAddress = relayerMainAddress[i];
            uint256 balance = bico.balanceOf(RelayerAddress.unwrap(relayerAddress));
            _prankRA(relayerAddress);
            ta.claimProtocolReward();
            assertEq(bico.balanceOf(RelayerAddress.unwrap(relayerAddress)), balance + claimableRewards[relayerAddress]);
        }
    }

    function testExitingRelayerJailing() external {
        uint256 t = 100;
        vm.warp(block.timestamp + t);

        // Setup to jail relayer 0. If relayer 0 is penalized, it will get jailed
        uint256 inactiveRelayerIndex = 0;
        RelayerAddress inactiveRelayer = relayerMainAddress[inactiveRelayerIndex];
        ta.debug_setTotalTransactionsProcessed(1000);
        for (uint256 i = 0; i < relayerCount; ++i) {
            if (i == inactiveRelayerIndex) continue;
            ta.debug_setTransactionsProcessedByRelayer(relayerMainAddress[i], 1000);
        }
        assertEq(
            ta.relayerClaimableProtocolRewards(inactiveRelayer), expectedRelayerRewardsAfter100Sec[inactiveRelayerIndex]
        );
        _assertEqFp(ta.relayerInfo(inactiveRelayer).rewardShares, initialExpectedRelayerShares[inactiveRelayerIndex]);

        // Unregister the relayer
        RelayerState memory currentState = latestRelayerState;
        _prankRA(inactiveRelayer);
        ta.unregister(latestRelayerState, _findRelayerIndex(inactiveRelayer));
        _removeRelayerFromLatestState(inactiveRelayer);

        _moveForwardToNextEpoch();

        FixedPointType initialShares = ta.totalProtocolRewardShares();
        for (uint256 i = 0; i < relayerCount; ++i) {
            RelayerAddress relayer = relayerMainAddress[i];
            claimableRewards[relayer] = ta.relayerClaimableProtocolRewards(relayer);

            if (i == inactiveRelayerIndex) {
                assertTrue(claimableRewards[relayer] == 0);
            } else {
                assertTrue(claimableRewards[relayer] > expectedDelegatorRewardsAfter100Sec[i]);
            }
        }

        // Jail the relayer
        _sendEmptyTransaction(currentState);

        // Relayer was jailed
        assertTrue(ta.relayerInfo(inactiveRelayer).status == RelayerStatus.Jailed);

        // The claimable rewards should not have changed for any relayer
        for (uint256 i = 0; i < relayerCount; ++i) {
            RelayerAddress relayer = relayerMainAddress[i];
            assertEq(ta.relayerClaimableProtocolRewards(relayer), claimableRewards[relayer]);
        }

        // Total Shares should be the same
        _checkTotalShares();
        _assertEqFp(ta.totalProtocolRewardShares(), initialShares);

        // Claim the rewards for other relayers
        for (uint256 i = 0; i < relayerCount; ++i) {
            if (i == inactiveRelayerIndex) continue;

            RelayerAddress relayerAddress = relayerMainAddress[i];
            uint256 balance = bico.balanceOf(RelayerAddress.unwrap(relayerAddress));
            _prankRA(relayerAddress);
            ta.claimProtocolReward();
            assertEq(bico.balanceOf(RelayerAddress.unwrap(relayerAddress)), balance + claimableRewards[relayerAddress]);
        }
    }

    function testShouldPreventJailedRelayerFromClaimingProtocolRewards() external {
        uint256 t = 100;
        vm.warp(block.timestamp + t);

        // Setup to jail relayer 0. If relayer 0 is penalized, it will get jailed
        uint256 inactiveRelayerIndex = 0;
        RelayerAddress inactiveRelayer = relayerMainAddress[inactiveRelayerIndex];
        ta.debug_setTotalTransactionsProcessed(1000);
        for (uint256 i = 0; i < relayerCount; ++i) {
            if (i == inactiveRelayerIndex) continue;
            ta.debug_setTransactionsProcessedByRelayer(relayerMainAddress[i], 1000);
        }

        _moveForwardToNextEpoch();
        _sendEmptyTransaction(latestRelayerState);

        // Relayer was jailed
        assertTrue(ta.relayerInfo(inactiveRelayer).status == RelayerStatus.Jailed);

        vm.expectRevert(abi.encodeWithSelector(InvalidRelayer.selector, [inactiveRelayer]));
        _prankRA(inactiveRelayer);
        ta.claimProtocolReward();
    }

    function testJailedRelayerReentry() external {
        uint256 t = 100;
        vm.warp(block.timestamp + t);

        // Setup to jail relayer 0. If relayer 0 is penalized, it will get jailed
        uint256 inactiveRelayerIndex = 0;
        RelayerAddress inactiveRelayer = relayerMainAddress[inactiveRelayerIndex];
        ta.debug_setTotalTransactionsProcessed(1000);
        for (uint256 i = 0; i < relayerCount; ++i) {
            if (i == inactiveRelayerIndex) continue;
            ta.debug_setTransactionsProcessedByRelayer(relayerMainAddress[i], 1000);
        }

        uint256 initialJailedRelayerClaimableRewards = ta.relayerClaimableProtocolRewards(inactiveRelayer);

        _moveForwardToNextEpoch();
        _sendEmptyTransaction(latestRelayerState);
        _moveForwardByWindows(deployParams.relayerStateUpdateDelayInWindows);
        _removeRelayerFromLatestState(inactiveRelayer);

        // Relayer was jailed
        assertTrue(ta.relayerInfo(inactiveRelayer).status == RelayerStatus.Jailed);

        // Wait for unjail
        vm.warp(ta.relayerInfo(inactiveRelayer).minExitTimestamp);

        // Record the state before unjail
        FixedPointType preUnjailTotalShares = ta.totalProtocolRewardShares();
        for (uint256 i = 0; i < relayerCount; ++i) {
            RelayerAddress relayer = relayerMainAddress[i];
            claimableRewards[relayer] = ta.relayerClaimableProtocolRewards(relayer);

            if (i == inactiveRelayerIndex) {
                assertTrue(claimableRewards[relayer] == 0);
            } else {
                assertTrue(claimableRewards[relayer] > expectedDelegatorRewardsAfter100Sec[i]);
            }
        }

        // Unjail
        _startPrankRA(inactiveRelayer);
        uint256 stake = 10000 ether;
        bico.approve(address(ta), stake);
        ta.unjailAndReenter(latestRelayerState, stake);
        vm.stopPrank();

        // Relayer was unjailed
        assertTrue(ta.relayerInfo(inactiveRelayer).status == RelayerStatus.Active);

        // Relayer should have some shares
        assertTrue(ta.relayerInfo(inactiveRelayer).rewardShares > FP_ZERO);

        // Total shares should increase
        _checkTotalShares();
        assertTrue(ta.totalProtocolRewardShares() > preUnjailTotalShares);

        // Rewards earned before jailing should be restored
        assertEq(ta.relayerClaimableProtocolRewards(inactiveRelayer), initialJailedRelayerClaimableRewards);
        claimableRewards[inactiveRelayer] = initialJailedRelayerClaimableRewards;

        // The claimable rewards should not have changed for any relayer except the jailed one
        for (uint256 i = 0; i < relayerCount; ++i) {
            if (i == inactiveRelayerIndex) continue;

            RelayerAddress relayer = relayerMainAddress[i];
            assertEq(ta.relayerClaimableProtocolRewards(relayer), claimableRewards[relayer]);
        }

        // Claim the rewards for relayers
        for (uint256 i = 0; i < relayerCount; ++i) {
            RelayerAddress relayerAddress = relayerMainAddress[i];
            uint256 balance = bico.balanceOf(RelayerAddress.unwrap(relayerAddress));
            _prankRA(relayerAddress);
            ta.claimProtocolReward();
            assertEq(bico.balanceOf(RelayerAddress.unwrap(relayerAddress)), balance + claimableRewards[relayerAddress]);
        }
    }
}
