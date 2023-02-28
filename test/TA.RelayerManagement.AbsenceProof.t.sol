// SPDX-License-Identifier: MIT

pragma solidity 0.8.17;

import "./base/TATestBase.t.sol";
import "src/structs/TAStructs.sol";
import "src/transaction-allocator/common/TAConstants.sol";
import "src/transaction-allocator/modules/relayer-management/interfaces/ITARelayerManagementEventsErrors.sol";
import "src/transaction-allocator/common/interfaces/ITAHelpers.sol";

contract TARelayerManagementAbsenceProofTest is
    TATestBase,
    TAConstants,
    ITARelayerManagementEventsErrors,
    ITAHelpers
{
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
            address relayerAddress = relayerMainAddress[i];

            vm.startPrank(relayerAddress);
            ta.register(ta.getStakeArray(), stake, relayerAccountAddresses[relayerAddress], endpoint);
            vm.stopPrank();
        }

        _postRegistrationSnapshotId = vm.snapshot();
    }

    function _preTestSnapshotId() internal view virtual override returns (uint256) {
        return _postRegistrationSnapshotId;
    }

    function testAbsenceProofSubmission() external withTADeployed {
        vm.roll(block.number + ta.penaltyDelayBlocks() * 2);

        // Select a relayer in the current window to miss tx submission in current window
        AbsenceProofAbsenteeData memory absenteeData;
        absenteeData.blockNumber = block.number;
        (address[] memory absence_selectedRelayers, uint256[] memory absence_cdfIndex) =
            ta.allocateRelayers(ta.getCdf());
        absenteeData.relayerAddress = absence_selectedRelayers[0];
        absenteeData.cdf = ta.getCdf();
        absenteeData.cdfIndex = absence_cdfIndex[0];
        absenteeData.relayerGenerationIterations = new uint256[](1);
        absenteeData.relayerGenerationIterations[0] = 0;
        absenteeData.latestStakeUpdationCdfLogIndex = 0;

        vm.roll(block.number + ta.blocksPerWindow());

        // Submit the absence proof
        (address[] memory reporter_selectedRelayers, uint256[] memory reporter_cdfIndex) =
            ta.allocateRelayers(ta.getCdf());
        AbsenceProofReporterData memory reporterData;
        address reporter = reporter_selectedRelayers[0];
        if (reporter == absenteeData.relayerAddress) {
            fail("Reporter and Absentee cannot be the same relayer");
        }
        reporterData.cdfIndex = reporter_cdfIndex[0];
        reporterData.relayerGenerationIterations = new uint256[](1);
        reporterData.relayerGenerationIterations[0] = 0;
        reporterData.cdf = ta.getCdf();
        vm.startPrank(reporter);
        vm.expectEmit(true, true, true, true);
        emit AbsenceProofProcessed(
            block.number / ta.blocksPerWindow(),
            reporter,
            absenteeData.relayerAddress,
            absenteeData.blockNumber / ta.blocksPerWindow(),
            _initialStakeAmount * ABSENCE_PENALTY / 10000
            );
        ta.processAbsenceProof(reporterData, absenteeData, ta.getStakeArray());
        vm.stopPrank();
    }

    function testCannotSubmitAbsenceProofWithIncorrectReporterCdf() external withTADeployed {
        vm.roll(block.number + ta.penaltyDelayBlocks() * 2);

        // Select a relayer in the current window to miss tx submission in current window
        AbsenceProofAbsenteeData memory absenteeData;
        absenteeData.blockNumber = block.number;
        (address[] memory absence_selectedRelayers, uint256[] memory absence_cdfIndex) =
            ta.allocateRelayers(ta.getCdf());
        absenteeData.relayerAddress = absence_selectedRelayers[0];
        absenteeData.cdf = ta.getCdf();
        absenteeData.cdfIndex = absence_cdfIndex[0];
        absenteeData.relayerGenerationIterations = new uint256[](1);
        absenteeData.relayerGenerationIterations[0] = 0;
        absenteeData.latestStakeUpdationCdfLogIndex = 0;

        vm.roll(block.number + ta.blocksPerWindow());

        // Submit the absence proof
        (address[] memory reporter_selectedRelayers, uint256[] memory reporter_cdfIndex) =
            ta.allocateRelayers(ta.getCdf());
        AbsenceProofReporterData memory reporterData;
        address reporter = reporter_selectedRelayers[0];
        if (reporter == absenteeData.relayerAddress) {
            fail("Reporter and Absentee cannot be the same relayer");
        }
        reporterData.cdfIndex = reporter_cdfIndex[0];
        reporterData.relayerGenerationIterations = new uint256[](1);
        reporterData.relayerGenerationIterations[0] = 0;
        reporterData.cdf = ta.getCdf();
        uint32[] memory stakeArray = ta.getStakeArray();
        // Corrupt the reporter's CDF
        reporterData.cdf[0] += 1;
        vm.startPrank(reporter);
        vm.expectRevert(InvalidCdfArrayHash.selector);
        ta.processAbsenceProof(reporterData, absenteeData, stakeArray);
        vm.stopPrank();
    }

    function testCannotSubmitAbsenceProofWithIncorrectReporterStakeArray() external withTADeployed {
        vm.roll(block.number + ta.penaltyDelayBlocks() * 2);

        // Select a relayer in the current window to miss tx submission in current window
        AbsenceProofAbsenteeData memory absenteeData;
        absenteeData.blockNumber = block.number;
        (address[] memory absence_selectedRelayers, uint256[] memory absence_cdfIndex) =
            ta.allocateRelayers(ta.getCdf());
        absenteeData.relayerAddress = absence_selectedRelayers[0];
        absenteeData.cdf = ta.getCdf();
        absenteeData.cdfIndex = absence_cdfIndex[0];
        absenteeData.relayerGenerationIterations = new uint256[](1);
        absenteeData.relayerGenerationIterations[0] = 0;
        absenteeData.latestStakeUpdationCdfLogIndex = 0;

        vm.roll(block.number + ta.blocksPerWindow());

        // Submit the absence proof
        (address[] memory reporter_selectedRelayers, uint256[] memory reporter_cdfIndex) =
            ta.allocateRelayers(ta.getCdf());
        AbsenceProofReporterData memory reporterData;
        address reporter = reporter_selectedRelayers[0];
        if (reporter == absenteeData.relayerAddress) {
            fail("Reporter and Absentee cannot be the same relayer");
        }
        reporterData.cdfIndex = reporter_cdfIndex[0];
        reporterData.relayerGenerationIterations = new uint256[](1);
        reporterData.relayerGenerationIterations[0] = 0;
        reporterData.cdf = ta.getCdf();
        uint32[] memory stakeArray = ta.getStakeArray();
        // Corrupt the reporter's Stake Array
        stakeArray[0] += 1;
        vm.startPrank(reporter);
        vm.expectRevert(InvalidStakeArrayHash.selector);
        ta.processAbsenceProof(reporterData, absenteeData, stakeArray);
        vm.stopPrank();
    }

    function testCannotSubmitAbsenceProofIfReporterIsNotSelectedAsFirstRelayerInWindow() external withTADeployed {
        vm.roll(block.number + ta.penaltyDelayBlocks() * 2);

        // Select a relayer in the current window to miss tx submission in current window
        AbsenceProofAbsenteeData memory absenteeData;
        absenteeData.blockNumber = block.number;
        (address[] memory absence_selectedRelayers, uint256[] memory absence_cdfIndex) =
            ta.allocateRelayers(ta.getCdf());
        absenteeData.relayerAddress = absence_selectedRelayers[0];
        absenteeData.cdf = ta.getCdf();
        absenteeData.cdfIndex = absence_cdfIndex[0];
        absenteeData.relayerGenerationIterations = new uint256[](1);
        absenteeData.relayerGenerationIterations[0] = 0;
        absenteeData.latestStakeUpdationCdfLogIndex = 0;

        vm.roll(block.number + ta.blocksPerWindow());

        // Submit the absence proof
        (address[] memory reporter_selectedRelayers, uint256[] memory reporter_cdfIndex) =
            ta.allocateRelayers(ta.getCdf());
        AbsenceProofReporterData memory reporterData;
        address reporter = reporter_selectedRelayers[1];
        if (reporter == absenteeData.relayerAddress) {
            fail("Reporter and Absentee cannot be the same relayer");
        }
        if (reporter == reporter_selectedRelayers[0]) {
            fail("Reporter cannot be the first relayer in the window");
        }
        reporterData.cdfIndex = reporter_cdfIndex[1];
        reporterData.relayerGenerationIterations = new uint256[](1);
        reporterData.relayerGenerationIterations[0] = 0;
        reporterData.cdf = ta.getCdf();
        uint32[] memory stakeArray = ta.getStakeArray();
        vm.startPrank(reporter);
        vm.expectRevert(InvalidRelayerWindowForReporter.selector);
        ta.processAbsenceProof(reporterData, absenteeData, stakeArray);
        vm.stopPrank();
    }

    function testCannotSubmitAbsenceProofInTheSameWindow() external withTADeployed {
        vm.roll(block.number + ta.penaltyDelayBlocks() * 2);

        // Select a relayer in the current window to miss tx submission in current window
        AbsenceProofAbsenteeData memory absenteeData;
        absenteeData.blockNumber = block.number;
        (address[] memory absence_selectedRelayers, uint256[] memory absence_cdfIndex) =
            ta.allocateRelayers(ta.getCdf());
        absenteeData.relayerAddress = absence_selectedRelayers[1];
        absenteeData.cdf = ta.getCdf();
        absenteeData.cdfIndex = absence_cdfIndex[1];
        absenteeData.relayerGenerationIterations = new uint256[](1);
        absenteeData.relayerGenerationIterations[0] = 1;
        absenteeData.latestStakeUpdationCdfLogIndex = 0;

        // Submit the absence proof
        (address[] memory reporter_selectedRelayers, uint256[] memory reporter_cdfIndex) =
            ta.allocateRelayers(ta.getCdf());
        AbsenceProofReporterData memory reporterData;
        address reporter = reporter_selectedRelayers[0];
        if (reporter == absenteeData.relayerAddress) {
            fail("Reporter and Absentee cannot be the same relayer");
        }
        reporterData.cdfIndex = reporter_cdfIndex[0];
        reporterData.relayerGenerationIterations = new uint256[](1);
        reporterData.relayerGenerationIterations[0] = 0;
        reporterData.cdf = ta.getCdf();
        uint32[] memory stakeArray = ta.getStakeArray();
        vm.startPrank(reporter);
        vm.expectRevert(InvalidAbsenteeBlockNumber.selector);
        ta.processAbsenceProof(reporterData, absenteeData, stakeArray);
        vm.stopPrank();
    }

    function testCannotSubmitAbsenceProofWithIncorrectAbsenteeCdf() external withTADeployed {
        vm.roll(block.number + ta.penaltyDelayBlocks() * 2);

        // Select a relayer in the current window to miss tx submission in current window
        AbsenceProofAbsenteeData memory absenteeData;
        absenteeData.blockNumber = block.number;
        (address[] memory absence_selectedRelayers, uint256[] memory absence_cdfIndex) =
            ta.allocateRelayers(ta.getCdf());
        absenteeData.relayerAddress = absence_selectedRelayers[0];
        absenteeData.cdf = ta.getCdf();
        // Corrupt the absentee's CDF
        absenteeData.cdf[0] += 1;
        absenteeData.cdfIndex = absence_cdfIndex[0];
        absenteeData.relayerGenerationIterations = new uint256[](1);
        absenteeData.relayerGenerationIterations[0] = 0;
        absenteeData.latestStakeUpdationCdfLogIndex = 0;

        vm.roll(block.number + ta.blocksPerWindow());

        // Submit the absence proof
        (address[] memory reporter_selectedRelayers, uint256[] memory reporter_cdfIndex) =
            ta.allocateRelayers(ta.getCdf());
        AbsenceProofReporterData memory reporterData;
        address reporter = reporter_selectedRelayers[0];
        if (reporter == absenteeData.relayerAddress) {
            fail("Reporter and Absentee cannot be the same relayer");
        }
        reporterData.cdfIndex = reporter_cdfIndex[0];
        reporterData.relayerGenerationIterations = new uint256[](1);
        reporterData.relayerGenerationIterations[0] = 0;
        reporterData.cdf = ta.getCdf();
        uint32[] memory stakeArray = ta.getStakeArray();
        vm.startPrank(reporter);
        vm.expectRevert(InvalidAbsenteeCdfArrayHash.selector);
        ta.processAbsenceProof(reporterData, absenteeData, stakeArray);
        vm.stopPrank();
    }

    function testCannotSubmitAbsenceProofIfAbsenteeWasNotAbsent() external withTADeployed {
        vm.roll(block.number + ta.penaltyDelayBlocks() * 2);

        // Select a relayer in the current window to miss tx submission in current window
        AbsenceProofAbsenteeData memory absenteeData;
        absenteeData.blockNumber = block.number;
        (address[] memory absence_selectedRelayers, uint256[] memory absence_cdfIndex) =
            ta.allocateRelayers(ta.getCdf());
        absenteeData.relayerAddress = absence_selectedRelayers[0];
        absenteeData.cdf = ta.getCdf();
        absenteeData.cdfIndex = absence_cdfIndex[0];
        absenteeData.relayerGenerationIterations = new uint256[](1);
        absenteeData.relayerGenerationIterations[0] = 0;
        absenteeData.latestStakeUpdationCdfLogIndex = 0;

        // Mark the absentee as not absent
        vm.startPrank(absenteeData.relayerAddress);
        ta.execute(
            new ForwardRequest[](0), absenteeData.cdf, absenteeData.relayerGenerationIterations, absenteeData.cdfIndex
        );
        vm.stopPrank();

        vm.roll(block.number + ta.blocksPerWindow());

        // Submit the absence proof
        (address[] memory reporter_selectedRelayers, uint256[] memory reporter_cdfIndex) =
            ta.allocateRelayers(ta.getCdf());
        AbsenceProofReporterData memory reporterData;
        address reporter = reporter_selectedRelayers[0];
        if (reporter == absenteeData.relayerAddress) {
            fail("Reporter and Absentee cannot be the same relayer");
        }
        reporterData.cdfIndex = reporter_cdfIndex[0];
        reporterData.relayerGenerationIterations = new uint256[](1);
        reporterData.relayerGenerationIterations[0] = 0;
        reporterData.cdf = ta.getCdf();
        uint32[] memory stakeArray = ta.getStakeArray();
        vm.startPrank(reporter);
        vm.expectRevert(
            abi.encodeWithSelector(AbsenteeWasPresent.selector, absenteeData.blockNumber / ta.blocksPerWindow())
        );
        ta.processAbsenceProof(reporterData, absenteeData, stakeArray);
        vm.stopPrank();
    }

    function testCannotSubmitAbsenceProofIfAbsenteeWasNotSelected() external withTADeployed {
        vm.roll(block.number + ta.penaltyDelayBlocks() * 2);

        // Select a relayer not selected in the current window
        AbsenceProofAbsenteeData memory absenteeData;
        absenteeData.blockNumber = block.number;
        (address[] memory absence_selectedRelayers,) = ta.allocateRelayers(ta.getCdf());

        for (uint256 i = 0; i < relayerMainAddress.length; i++) {
            bool found = false;
            for (uint256 j = 0; j < absence_selectedRelayers.length; j++) {
                found = found || (relayerMainAddress[i] == absence_selectedRelayers[j]);
            }

            if (!found) {
                // Found unselected relayer
                absenteeData.relayerAddress = relayerMainAddress[i];
                absenteeData.cdf = ta.getCdf();
                absenteeData.relayerGenerationIterations = new uint256[](1);
                absenteeData.latestStakeUpdationCdfLogIndex = 0;

                break;
            }
        }

        if (absenteeData.relayerAddress == address(0)) {
            fail("No unselected relayer found");
        }

        vm.roll(block.number + ta.blocksPerWindow());

        // Try to submit the absence proof for all possible combn of (genItern,  cdfIndex)
        (address[] memory reporter_selectedRelayers, uint256[] memory reporter_cdfIndex) =
            ta.allocateRelayers(ta.getCdf());
        AbsenceProofReporterData memory reporterData;
        address reporter = reporter_selectedRelayers[0];
        if (reporter == absenteeData.relayerAddress) {
            fail("Reporter and Absentee cannot be the same relayer");
        }
        reporterData.cdfIndex = reporter_cdfIndex[0];
        reporterData.relayerGenerationIterations = new uint256[](1);
        reporterData.relayerGenerationIterations[0] = 0;
        reporterData.cdf = ta.getCdf();
        uint32[] memory stakeArray = ta.getStakeArray();
        uint256 relayerCount = ta.relayerCount();
        vm.startPrank(reporter);
        for (
            uint256 relayerGenerationIteration = 0;
            relayerGenerationIteration < relayerCount;
            ++relayerGenerationIteration
        ) {
            for (uint256 cdfIndex = 0; cdfIndex < relayerCount; ++cdfIndex) {
                absenteeData.relayerGenerationIterations[0] = relayerGenerationIteration;
                absenteeData.cdfIndex = cdfIndex;

                vm.expectRevert(InvalidRelayerWindowForAbsentee.selector);
                ta.processAbsenceProof(reporterData, absenteeData, stakeArray);
            }
        }
        vm.stopPrank();
    }
}
