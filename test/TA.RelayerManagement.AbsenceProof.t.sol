// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import "./base/TATestBase.t.sol";
import "src/transaction-allocator/common/TAConstants.sol";
import "src/transaction-allocator/modules/relayer-management/interfaces/ITARelayerManagementEventsErrors.sol";
import "src/transaction-allocator/common/interfaces/ITAHelpers.sol";

// TODO: Test withdrawal and stake updation
// TODO: Add tests related to delayed CDF Updation

contract TARelayerManagementAbsenceProofTest is TATestBase, ITARelayerManagementEventsErrors, ITAHelpers {
    uint256 private _postRegistrationSnapshotId;
    uint256 private constant _initialStakeAmount = MINIMUM_STAKE_AMOUNT;

    function setUp() public override {
        if (_postRegistrationSnapshotId != 0) {
            return;
        }

        super.setUp();

        // Register all Relayers
        for (uint256 i = 0; i < relayerCount; i++) {
            uint256 stake = _initialStakeAmount;
            string memory endpoint = "test";
            RelayerAddress relayerAddress = relayerMainAddress[i];

            _startPrankRA(relayerAddress);
            bico.approve(address(ta), stake);
            ta.register(
                ta.getStakeArray(), ta.getDelegationArray(), stake, relayerAccountAddresses[relayerAddress], endpoint
            );
            vm.stopPrank();
        }

        _postRegistrationSnapshotId = vm.snapshot();
    }

    function _preTestSnapshotId() internal view virtual override returns (uint256) {
        return _postRegistrationSnapshotId;
    }

    function testAbsenceProofSubmission() external atSnapshot {
        vm.roll(block.number + ta.penaltyDelayBlocks() * 2);

        // Select a relayer in the current window to miss tx submission in current window
        AbsenceProofAbsenteeData memory absenteeData;
        absenteeData.blockNumber = block.number;
        (RelayerAddress[] memory absence_selectedRelayers, uint256[] memory absence_cdfIndex) =
            ta.allocateRelayers(ta.getCdfArray(), 1);
        absenteeData.relayerAddress = absence_selectedRelayers[0];
        absenteeData.cdf = ta.getCdfArray();
        absenteeData.cdfIndex = absence_cdfIndex[0];
        absenteeData.relayerGenerationIterations = new uint256[](1);
        absenteeData.relayerGenerationIterations[0] = 0;
        absenteeData.latestStakeUpdationCdfLogIndex = 1;
        absenteeData.relayerIndexToRelayerLogIndex = 0;

        vm.roll(block.number + ta.blocksPerWindow());

        uint16[] memory cdf = ta.getCdfArray();

        // Submit the absence proof
        (RelayerAddress[] memory reporter_selectedRelayers, uint256[] memory reporter_cdfIndex) =
            ta.allocateRelayers(ta.getCdfArray(), 1);
        AbsenceProofReporterData memory reporterData;
        RelayerAddress reporter = reporter_selectedRelayers[0];
        if (reporter == absenteeData.relayerAddress) {
            fail("Reporter and Absentee cannot be the same relayer");
        }
        reporterData.cdfIndex = reporter_cdfIndex[0];
        reporterData.relayerGenerationIterations = new uint256[](1);
        reporterData.relayerGenerationIterations[0] = 0;
        reporterData.cdf = ta.getCdfArray();
        reporterData.currentCdfLogIndex = 1;
        reporterData.relayerIndexToRelayerLogIndex = 0;
        _startPrankRA(reporter);
        vm.expectEmit(true, true, true, true);

        uint256 expectedPenalty = _initialStakeAmount * ABSENCE_PENALTY / 10000;
        uint256 reporterBalance = bico.balanceOf(RelayerAddress.unwrap(reporter));

        emit AbsenceProofProcessed(
            block.number / ta.blocksPerWindow(),
            RelayerAddress.unwrap(reporter),
            absenteeData.relayerAddress,
            absenteeData.blockNumber / ta.blocksPerWindow(),
            expectedPenalty
        );
        ta.processAbsenceProof(reporterData, absenteeData, ta.getStakeArray(), ta.getDelegationArray());
        vm.stopPrank();

        assertEq(ta.relayerInfo_Stake(absenteeData.relayerAddress), _initialStakeAmount - expectedPenalty);
        assertEq(bico.balanceOf(RelayerAddress.unwrap(reporter)), reporterBalance + expectedPenalty);

        // Verify CDF Update
        uint16[] memory newCdf = ta.getCdfArray();
        assertEq(newCdf.length, relayerCount);

        assertEq(ta.debug_cdfHash(cdf) == ta.debug_cdfHash(newCdf), false);

        uint256 absentRelayerIndex = ta.relayerInfo_Index(absenteeData.relayerAddress);
        assertEq(newCdf[absentRelayerIndex] < cdf[absentRelayerIndex], true);

        // Verify Delayed CDF Updation

        // Verify that at this point of time, CDF hash has not been updated
        assertEq(ta.debug_verifyCdfHashAtWindow(cdf, ta.debug_currentWindowIndex(), 1), true);
        assertEq(ta.debug_verifyCdfHashAtWindow(newCdf, ta.debug_currentWindowIndex(), 1), false);

        vm.roll(block.number + RELAYER_CONFIGURATION_UPDATE_DELAY_IN_WINDOWS * ta.blocksPerWindow());

        // CDF hash should be updated now
        assertEq(ta.debug_verifyCdfHashAtWindow(cdf, ta.debug_currentWindowIndex(), 2), false);
        assertEq(ta.debug_verifyCdfHashAtWindow(newCdf, ta.debug_currentWindowIndex(), 2), true);
    }

    function testAbsenceProofSubmissionPostRelayerUnRegistrationDuringWithdrawDelay() external atSnapshot {
        vm.roll(block.number + ta.penaltyDelayBlocks() * 2);

        // Select a relayer in the current window to miss tx submission in current window
        AbsenceProofAbsenteeData memory absenteeData;
        absenteeData.blockNumber = block.number;
        (RelayerAddress[] memory absence_selectedRelayers, uint256[] memory absence_cdfIndex) =
            ta.allocateRelayers(ta.getCdfArray(), 1);
        absenteeData.relayerAddress = absence_selectedRelayers[0];
        absenteeData.cdf = ta.getCdfArray();
        absenteeData.cdfIndex = absence_cdfIndex[0];
        absenteeData.relayerGenerationIterations = new uint256[](1);
        absenteeData.relayerGenerationIterations[0] = 0;
        absenteeData.latestStakeUpdationCdfLogIndex = 1;
        absenteeData.relayerIndexToRelayerLogIndex = 0;

        vm.roll(block.number + ta.blocksPerWindow());

        uint16[] memory cdf = ta.getCdfArray();

        // Unregister the relayer
        _startPrankRA(absenteeData.relayerAddress);
        ta.unRegister(ta.getStakeArray(), ta.getDelegationArray());
        vm.stopPrank();

        uint16[] memory postDeregistrationCdf = ta.getCdfArray();

        // Submit the absence proof
        (RelayerAddress[] memory reporter_selectedRelayers, uint256[] memory reporter_cdfIndex) =
            ta.allocateRelayers(cdf, 1);
        AbsenceProofReporterData memory reporterData;
        RelayerAddress reporter = reporter_selectedRelayers[0];
        if (reporter == absenteeData.relayerAddress) {
            fail("Reporter and Absentee cannot be the same relayer");
        }
        reporterData.cdfIndex = reporter_cdfIndex[0];
        reporterData.relayerGenerationIterations = new uint256[](1);
        reporterData.relayerGenerationIterations[0] = 0;
        reporterData.cdf = cdf;
        reporterData.currentCdfLogIndex = 1;
        reporterData.relayerIndexToRelayerLogIndex = 0;
        _startPrankRA(reporter);
        vm.expectEmit(true, true, true, true);

        uint256 expectedPenalty = _initialStakeAmount * ABSENCE_PENALTY / 10000;
        uint256 reporterBalance = bico.balanceOf(RelayerAddress.unwrap(reporter));

        emit AbsenceProofProcessed(
            block.number / ta.blocksPerWindow(),
            RelayerAddress.unwrap(reporter),
            absenteeData.relayerAddress,
            absenteeData.blockNumber / ta.blocksPerWindow(),
            expectedPenalty
        );
        ta.processAbsenceProof(reporterData, absenteeData, ta.getStakeArray(), ta.getDelegationArray());
        vm.stopPrank();

        assertEq(ta.withdrawalInfo(absenteeData.relayerAddress).amount, _initialStakeAmount - expectedPenalty);
        assertEq(bico.balanceOf(RelayerAddress.unwrap(reporter)), reporterBalance + expectedPenalty);

        // There should be no change in CDF, since the absentee relayer had already de-registered
        uint16[] memory newCdf = ta.getCdfArray();
        assertEq(ta.debug_cdfHash(postDeregistrationCdf) == ta.debug_cdfHash(newCdf), true);
    }

    function testCannotSubmitAbsenceProofWithIncorrectReporterCdf() external atSnapshot {
        vm.roll(block.number + ta.penaltyDelayBlocks() * 2);

        // Select a relayer in the current window to miss tx submission in current window
        AbsenceProofAbsenteeData memory absenteeData;
        absenteeData.blockNumber = block.number;
        (RelayerAddress[] memory absence_selectedRelayers, uint256[] memory absence_cdfIndex) =
            ta.allocateRelayers(ta.getCdfArray(), 1);
        absenteeData.relayerAddress = absence_selectedRelayers[0];
        absenteeData.cdf = ta.getCdfArray();
        absenteeData.cdfIndex = absence_cdfIndex[0];
        absenteeData.relayerGenerationIterations = new uint256[](1);
        absenteeData.relayerGenerationIterations[0] = 0;
        absenteeData.latestStakeUpdationCdfLogIndex = 1;
        absenteeData.relayerIndexToRelayerLogIndex = 0;

        vm.roll(block.number + ta.blocksPerWindow());

        // Submit the absence proof
        (RelayerAddress[] memory reporter_selectedRelayers, uint256[] memory reporter_cdfIndex) =
            ta.allocateRelayers(ta.getCdfArray(), 1);
        AbsenceProofReporterData memory reporterData;
        RelayerAddress reporter = reporter_selectedRelayers[0];
        if (reporter == absenteeData.relayerAddress) {
            fail("Reporter and Absentee cannot be the same relayer");
        }
        reporterData.cdfIndex = reporter_cdfIndex[0];
        reporterData.relayerGenerationIterations = new uint256[](1);
        reporterData.relayerGenerationIterations[0] = 0;
        reporterData.cdf = ta.getCdfArray();
        reporterData.currentCdfLogIndex = 1;
        reporterData.relayerIndexToRelayerLogIndex = 0;
        uint32[] memory stakeArray = ta.getStakeArray();
        uint32[] memory delegationArray = ta.getDelegationArray();
        // Corrupt the reporter's CDF
        reporterData.cdf[0] += 1;
        _startPrankRA(reporter);
        vm.expectRevert(InvalidCdfArrayHash.selector);
        ta.processAbsenceProof(reporterData, absenteeData, stakeArray, delegationArray);
        vm.stopPrank();
    }

    function testCannotSubmitAbsenceProofWithIncorrectReporterStakeArray() external atSnapshot {
        vm.roll(block.number + ta.penaltyDelayBlocks() * 2);

        // Select a relayer in the current window to miss tx submission in current window
        AbsenceProofAbsenteeData memory absenteeData;
        absenteeData.blockNumber = block.number;
        (RelayerAddress[] memory absence_selectedRelayers, uint256[] memory absence_cdfIndex) =
            ta.allocateRelayers(ta.getCdfArray(), 1);
        absenteeData.relayerAddress = absence_selectedRelayers[0];
        absenteeData.cdf = ta.getCdfArray();
        absenteeData.cdfIndex = absence_cdfIndex[0];
        absenteeData.relayerGenerationIterations = new uint256[](1);
        absenteeData.relayerGenerationIterations[0] = 0;
        absenteeData.latestStakeUpdationCdfLogIndex = 1;
        absenteeData.relayerIndexToRelayerLogIndex = 0;

        vm.roll(block.number + ta.blocksPerWindow());

        // Submit the absence proof
        (RelayerAddress[] memory reporter_selectedRelayers, uint256[] memory reporter_cdfIndex) =
            ta.allocateRelayers(ta.getCdfArray(), 1);
        AbsenceProofReporterData memory reporterData;
        RelayerAddress reporter = reporter_selectedRelayers[0];
        if (reporter == absenteeData.relayerAddress) {
            fail("Reporter and Absentee cannot be the same relayer");
        }
        reporterData.cdfIndex = reporter_cdfIndex[0];
        reporterData.relayerGenerationIterations = new uint256[](1);
        reporterData.relayerGenerationIterations[0] = 0;
        reporterData.cdf = ta.getCdfArray();
        reporterData.currentCdfLogIndex = 1;
        reporterData.relayerIndexToRelayerLogIndex = 0;
        uint32[] memory stakeArray = ta.getStakeArray();
        uint32[] memory delegationArray = ta.getDelegationArray();
        // Corrupt the reporter's Stake Array
        stakeArray[0] += 1;
        _startPrankRA(reporter);
        vm.expectRevert(InvalidStakeArrayHash.selector);
        ta.processAbsenceProof(reporterData, absenteeData, stakeArray, delegationArray);
        vm.stopPrank();
    }

    function testCannotSubmitAbsenceProofIfReporterIsNotSelectedAsFirstRelayerInWindow() external atSnapshot {
        vm.roll(block.number + ta.penaltyDelayBlocks() * 2);

        // Select a relayer in the current window to miss tx submission in current window
        AbsenceProofAbsenteeData memory absenteeData;
        absenteeData.blockNumber = block.number;
        (RelayerAddress[] memory absence_selectedRelayers, uint256[] memory absence_cdfIndex) =
            ta.allocateRelayers(ta.getCdfArray(), 1);
        absenteeData.relayerAddress = absence_selectedRelayers[0];
        absenteeData.cdf = ta.getCdfArray();
        absenteeData.cdfIndex = absence_cdfIndex[0];
        absenteeData.relayerGenerationIterations = new uint256[](1);
        absenteeData.relayerGenerationIterations[0] = 0;
        absenteeData.latestStakeUpdationCdfLogIndex = 1;
        absenteeData.relayerIndexToRelayerLogIndex = 0;

        vm.roll(block.number + ta.blocksPerWindow());

        // Submit the absence proof
        (RelayerAddress[] memory reporter_selectedRelayers, uint256[] memory reporter_cdfIndex) =
            ta.allocateRelayers(ta.getCdfArray(), 1);
        AbsenceProofReporterData memory reporterData;
        RelayerAddress reporter = reporter_selectedRelayers[1];
        if (reporter == absenteeData.relayerAddress) {
            fail("Reporter and Absentee cannot be the same relayer");
        }
        if (reporter == reporter_selectedRelayers[0]) {
            fail("Reporter cannot be the first relayer in the window");
        }
        reporterData.cdfIndex = reporter_cdfIndex[1];
        reporterData.relayerGenerationIterations = new uint256[](1);
        reporterData.relayerGenerationIterations[0] = 0;
        reporterData.cdf = ta.getCdfArray();
        reporterData.currentCdfLogIndex = 1;
        reporterData.relayerIndexToRelayerLogIndex = 0;
        uint32[] memory stakeArray = ta.getStakeArray();
        uint32[] memory delegationArray = ta.getDelegationArray();
        _startPrankRA(reporter);
        vm.expectRevert(RelayerIndexDoesNotPointToSelectedCdfInterval.selector);
        ta.processAbsenceProof(reporterData, absenteeData, stakeArray, delegationArray);
        vm.stopPrank();
    }

    function testCannotSubmitAbsenceProofInTheSameWindow() external atSnapshot {
        vm.roll(block.number + ta.penaltyDelayBlocks() * 2);

        // Select a relayer in the current window to miss tx submission in current window
        AbsenceProofAbsenteeData memory absenteeData;
        absenteeData.blockNumber = block.number;
        (RelayerAddress[] memory absence_selectedRelayers, uint256[] memory absence_cdfIndex) =
            ta.allocateRelayers(ta.getCdfArray(), 1);
        absenteeData.relayerAddress = absence_selectedRelayers[1];
        absenteeData.cdf = ta.getCdfArray();
        absenteeData.cdfIndex = absence_cdfIndex[1];
        absenteeData.relayerGenerationIterations = new uint256[](1);
        absenteeData.relayerGenerationIterations[0] = 1;
        absenteeData.latestStakeUpdationCdfLogIndex = 1;
        absenteeData.relayerIndexToRelayerLogIndex = 0;

        // Submit the absence proof
        (RelayerAddress[] memory reporter_selectedRelayers, uint256[] memory reporter_cdfIndex) =
            ta.allocateRelayers(ta.getCdfArray(), 1);
        AbsenceProofReporterData memory reporterData;
        RelayerAddress reporter = reporter_selectedRelayers[0];
        if (reporter == absenteeData.relayerAddress) {
            fail("Reporter and Absentee cannot be the same relayer");
        }
        reporterData.cdfIndex = reporter_cdfIndex[0];
        reporterData.relayerGenerationIterations = new uint256[](1);
        reporterData.relayerGenerationIterations[0] = 0;
        reporterData.cdf = ta.getCdfArray();
        reporterData.currentCdfLogIndex = 1;
        reporterData.relayerIndexToRelayerLogIndex = 0;
        uint32[] memory stakeArray = ta.getStakeArray();
        uint32[] memory delegationArray = ta.getDelegationArray();
        _startPrankRA(reporter);
        vm.expectRevert(InvalidAbsenteeBlockNumber.selector);
        ta.processAbsenceProof(reporterData, absenteeData, stakeArray, delegationArray);
        vm.stopPrank();
    }

    function testCannotSubmitAbsenceProofWithIncorrectAbsenteeCdf() external atSnapshot {
        vm.roll(block.number + ta.penaltyDelayBlocks() * 2);

        // Select a relayer in the current window to miss tx submission in current window
        AbsenceProofAbsenteeData memory absenteeData;
        absenteeData.blockNumber = block.number;
        (RelayerAddress[] memory absence_selectedRelayers, uint256[] memory absence_cdfIndex) =
            ta.allocateRelayers(ta.getCdfArray(), 1);
        absenteeData.relayerAddress = absence_selectedRelayers[0];
        absenteeData.cdf = ta.getCdfArray();
        // Corrupt the absentee's CDF
        absenteeData.cdf[0] += 1;
        absenteeData.cdfIndex = absence_cdfIndex[0];
        absenteeData.relayerGenerationIterations = new uint256[](1);
        absenteeData.relayerGenerationIterations[0] = 0;
        absenteeData.latestStakeUpdationCdfLogIndex = 1;
        absenteeData.relayerIndexToRelayerLogIndex = 0;

        vm.roll(block.number + ta.blocksPerWindow());

        // Submit the absence proof
        (RelayerAddress[] memory reporter_selectedRelayers, uint256[] memory reporter_cdfIndex) =
            ta.allocateRelayers(ta.getCdfArray(), 1);
        AbsenceProofReporterData memory reporterData;
        RelayerAddress reporter = reporter_selectedRelayers[0];
        if (reporter == absenteeData.relayerAddress) {
            fail("Reporter and Absentee cannot be the same relayer");
        }
        reporterData.cdfIndex = reporter_cdfIndex[0];
        reporterData.relayerGenerationIterations = new uint256[](1);
        reporterData.relayerGenerationIterations[0] = 0;
        reporterData.cdf = ta.getCdfArray();
        reporterData.currentCdfLogIndex = 1;
        reporterData.relayerIndexToRelayerLogIndex = 0;
        uint32[] memory stakeArray = ta.getStakeArray();
        uint32[] memory delegationArray = ta.getDelegationArray();
        _startPrankRA(reporter);
        // TODO: vm.expectRevert(InvalidAbsenteeCdfArrayHash.selector);
        vm.expectRevert(InvalidCdfArrayHash.selector);
        ta.processAbsenceProof(reporterData, absenteeData, stakeArray, delegationArray);
        vm.stopPrank();
    }

    function testCannotSubmitAbsenceProofIfAbsenteeWasNotAbsent() external atSnapshot {
        vm.roll(block.number + ta.penaltyDelayBlocks() * 2);

        // Select a relayer in the current window to miss tx submission in current window
        AbsenceProofAbsenteeData memory absenteeData;
        absenteeData.blockNumber = block.number;
        (RelayerAddress[] memory absence_selectedRelayers, uint256[] memory absence_cdfIndex) =
            ta.allocateRelayers(ta.getCdfArray(), 1);
        absenteeData.relayerAddress = absence_selectedRelayers[0];
        absenteeData.cdf = ta.getCdfArray();
        absenteeData.cdfIndex = absence_cdfIndex[0];
        absenteeData.relayerGenerationIterations = new uint256[](1);
        absenteeData.relayerGenerationIterations[0] = 0;
        absenteeData.latestStakeUpdationCdfLogIndex = 1;
        absenteeData.relayerIndexToRelayerLogIndex = 0;

        // Mark the absentee as not absent
        _startPrankRA(absenteeData.relayerAddress);
        ta.execute(
            new ForwardRequest[](0),
            absenteeData.cdf,
            absenteeData.relayerGenerationIterations,
            absenteeData.cdfIndex,
            1,
            0
        );
        vm.stopPrank();

        vm.roll(block.number + ta.blocksPerWindow());

        // Submit the absence proof
        (RelayerAddress[] memory reporter_selectedRelayers, uint256[] memory reporter_cdfIndex) =
            ta.allocateRelayers(ta.getCdfArray(), 1);
        AbsenceProofReporterData memory reporterData;
        RelayerAddress reporter = reporter_selectedRelayers[0];
        if (reporter == absenteeData.relayerAddress) {
            fail("Reporter and Absentee cannot be the same relayer");
        }
        reporterData.cdfIndex = reporter_cdfIndex[0];
        reporterData.relayerGenerationIterations = new uint256[](1);
        reporterData.relayerGenerationIterations[0] = 0;
        reporterData.cdf = ta.getCdfArray();
        reporterData.currentCdfLogIndex = 1;
        reporterData.relayerIndexToRelayerLogIndex = 0;
        uint32[] memory stakeArray = ta.getStakeArray();
        uint32[] memory delegationArray = ta.getDelegationArray();
        _startPrankRA(reporter);
        vm.expectRevert(
            abi.encodeWithSelector(AbsenteeWasPresent.selector, absenteeData.blockNumber / ta.blocksPerWindow())
        );
        ta.processAbsenceProof(reporterData, absenteeData, stakeArray, delegationArray);
        vm.stopPrank();
    }

    function testCannotSubmitAbsenceProofIfAbsenteeWasNotSelected() external atSnapshot {
        vm.roll(block.number + ta.penaltyDelayBlocks() * 2);

        // Select a relayer not selected in the current window
        AbsenceProofAbsenteeData memory absenteeData;
        absenteeData.blockNumber = block.number;
        (RelayerAddress[] memory absence_selectedRelayers,) = ta.allocateRelayers(ta.getCdfArray(), 1);

        for (uint256 i = 0; i < relayerMainAddress.length; i++) {
            bool found = false;
            for (uint256 j = 0; j < absence_selectedRelayers.length; j++) {
                found = found || (relayerMainAddress[i] == absence_selectedRelayers[j]);
            }

            if (!found) {
                // Found unselected relayer
                absenteeData.relayerAddress = relayerMainAddress[i];
                absenteeData.cdf = ta.getCdfArray();
                absenteeData.relayerGenerationIterations = new uint256[](1);
                absenteeData.latestStakeUpdationCdfLogIndex = 1;
                absenteeData.relayerIndexToRelayerLogIndex = 0;

                break;
            }
        }

        if (absenteeData.relayerAddress == RelayerAddress.wrap(address(0))) {
            fail("No unselected relayer found");
        }

        vm.roll(block.number + ta.blocksPerWindow());

        // Try to submit the absence proof for all possible combn of (genItern,  cdfIndex)
        (RelayerAddress[] memory reporter_selectedRelayers, uint256[] memory reporter_cdfIndex) =
            ta.allocateRelayers(ta.getCdfArray(), 1);
        AbsenceProofReporterData memory reporterData;
        RelayerAddress reporter = reporter_selectedRelayers[0];
        if (reporter == absenteeData.relayerAddress) {
            fail("Reporter and Absentee cannot be the same relayer");
        }
        reporterData.cdfIndex = reporter_cdfIndex[0];
        reporterData.relayerGenerationIterations = new uint256[](1);
        reporterData.relayerGenerationIterations[0] = 0;
        reporterData.cdf = ta.getCdfArray();
        reporterData.currentCdfLogIndex = 1;
        reporterData.relayerIndexToRelayerLogIndex = 0;
        uint32[] memory stakeArray = ta.getStakeArray();
        uint32[] memory delegationArray = ta.getDelegationArray();
        uint256 relayerCount = ta.relayerCount();
        _startPrankRA(reporter);
        for (
            uint256 relayerGenerationIteration = 0;
            relayerGenerationIteration < relayerCount;
            ++relayerGenerationIteration
        ) {
            for (uint256 cdfIndex = 0; cdfIndex < relayerCount; ++cdfIndex) {
                absenteeData.relayerGenerationIterations[0] = relayerGenerationIteration;
                absenteeData.cdfIndex = cdfIndex;

                vm.expectRevert();
                ta.processAbsenceProof(reporterData, absenteeData, stakeArray, delegationArray);
            }
        }
        vm.stopPrank();
    }
}
