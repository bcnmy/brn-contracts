// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import "./base/TATestBase.sol";
import "ta-common/TAConstants.sol";
import "ta-transaction-allocation/interfaces/ITATransactionAllocationEventsErrors.sol";
import "ta-relayer-management/interfaces/ITARelayerManagementEventsErrors.sol";
import "ta-common/interfaces/ITAHelpers.sol";

// TODO: verify global counters in each test

contract ProtocolRewardsTest is
    TATestBase,
    ITATransactionAllocationEventsErrors,
    ITARelayerManagementEventsErrors,
    ITAHelpers,
    IMinimalApplicationEventsErrors
{
    using FixedPointTypeHelper for FixedPointType;
    using Uint256WrapperHelper for uint256;

    uint256 constant TEST_SETUP_PROTOCOL_REWARD_RATE = 174447047123188;

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

    function testProtocolRewardRates() external {
        // Check Reward Rate at current stake
        assertEq(ta.debug_getProtocolRewardRate(), TEST_SETUP_PROTOCOL_REWARD_RATE);

        // Check Reward Rate at 10 relayers each with minimum stake
        ta.debug_setTotalStake(ta.minimumStakeAmount() * 10);
        ta.debug_setRelayerCount(10);
        assertEq(ta.debug_getProtocolRewardRate(), 31717644931488);

        // Check Reward Rate at 1 relayer with minimum stake
        ta.debug_setTotalStake(ta.minimumStakeAmount());
        ta.debug_setRelayerCount(1);
        assertEq(ta.debug_getProtocolRewardRate(), deployParams.baseRewardRatePerMinimumStakePerSec);
    }

    FixedPointType[10] initialExpectedRelayerShares = [
        FixedPointType.wrap(10000000000000000000000000000000000000000000000),
        FixedPointType.wrap(19999999899700000503004497477432445150676287569),
        FixedPointType.wrap(29999999849550000754506746216148667726014431354),
        FixedPointType.wrap(39999999799400001006008994954864890301352575138),
        FixedPointType.wrap(49999999749250001257511243693581112876690718923),
        FixedPointType.wrap(59999999699100001509013492432297335452028862708),
        FixedPointType.wrap(69999999648950001760515741171013558027367006492),
        FixedPointType.wrap(79999999598800002012017989909729780602705150277),
        FixedPointType.wrap(89999999548650002263520238648446003178043294062),
        FixedPointType.wrap(99999999498500002515022487387162225753381437846)
    ];

    function testRelayersShouldHaveCorrectInitialProtocolRewardShares() external {
        // At time t=0, share price = 1. Therefore shares=stake
        assertTrue(
            ta.relayerInfo(relayerMainAddress[0]).stake.fp() == ta.relayerInfo(relayerMainAddress[0]).rewardShares
        );
        assertTrue(initialExpectedRelayerShares[0] == ta.relayerInfo(relayerMainAddress[0]).rewardShares);

        // we waited for half an epoch before registering other relayers so that the foundation relayer has accrued some rewards
        // check setUp()
        uint256 initialRewardsGenerated =
            (deployParams.baseRewardRatePerMinimumStakePerSec * (deployParams.epochLengthInSec / 2));
        FixedPointType newSharePrice = (initialRelayerStake[relayerMainAddress[0]].fp() + initialRewardsGenerated.fp())
            / ta.relayerInfo(relayerMainAddress[0]).rewardShares;

        for (uint256 i = 1; i < relayerCount; ++i) {
            RelayerAddress relayerAddress = relayerMainAddress[i];
            assertTrue(
                ta.relayerInfo(relayerAddress).stake.fp() / newSharePrice == ta.relayerInfo(relayerAddress).rewardShares
            );
            assertTrue(initialExpectedRelayerShares[i] == ta.relayerInfo(relayerAddress).rewardShares);
        }
    }

    uint256[10] expectedRewardsAfter100Sec = [
        367326450876606,
        570917608714740,
        856376413072110,
        1141835217429480,
        1427294021786849,
        1712752826144220,
        1998211630501589,
        2283670434858959,
        2569129239216329,
        2854588043573699
    ];

    function testRelayersShouldAccrueRewardsProportionally() external {
        // Foundation relayer has been registered for 1.5 epoch + 1 window. It should have accrued rewards
        uint256 initialFoundationRelayerRewards =
            deployParams.baseRewardRatePerMinimumStakePerSec * (block.timestamp - deploymentTimestamp);
        assertEq(ta.relayerClaimableProtocolRewards(relayerMainAddress[0]), initialFoundationRelayerRewards);

        // Other relayers were just registered, therefore they should have no rewards
        for (uint256 i = 1; i < relayerCount; ++i) {
            assertEq(ta.relayerClaimableProtocolRewards(relayerMainAddress[i]), 0);
        }

        uint256 t = 100;
        vm.warp(block.timestamp + t);

        // All relayers should have accrued rewards proportionally in the last t s as per TEST_SETUP_PROTOCOL_REWARD_RATE
        uint256 expectedTotalRewardsAccrued = t * TEST_SETUP_PROTOCOL_REWARD_RATE
            + (deployParams.baseRewardRatePerMinimumStakePerSec * (deployParams.epochLengthInSec / 2));
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
            assertEq(ta.relayerClaimableProtocolRewards(relayerAddress), expectedRewardsAfter100Sec[i]);
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
            assertEq(bico.balanceOf(RelayerAddress.unwrap(relayerAddress)), balance + expectedRewardsAfter100Sec[i]);
            assertEq(ta.relayerClaimableProtocolRewards(relayerAddress), 0);
        }
    }
}
