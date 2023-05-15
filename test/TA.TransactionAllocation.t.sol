// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import "./base/TATestBase.t.sol";
import "src/transaction-allocator/common/TAConstants.sol";
import "src/transaction-allocator/modules/transaction-allocation/interfaces/ITATransactionAllocationEventsErrors.sol";
import "src/transaction-allocator/common/interfaces/ITAHelpers.sol";
import "./modules/minimal-application/interfaces/IMinimalApplicationEventsErrors.sol";

contract TATransactionAllocationTest is
    TATestBase,
    ITATransactionAllocationEventsErrors,
    ITAHelpers,
    IMinimalApplicationEventsErrors
{
    uint256 constant initialApplicationFunds = 10 ether;

    uint256 private _postRegistrationSnapshotId;
    uint256 private constant _initialStakeAmount = MINIMUM_STAKE_AMOUNT;
    bytes[] private txns;

    IMinimalApplication tam;

    function setUp() public override {
        if (_postRegistrationSnapshotId != 0) {
            return;
        }

        if (tx.gasprice == 0) {
            fail("Gas Price is 0. Please set it to 1 gwei or more.");
        }

        super.setUp();

        tam = IMinimalApplication(address(ta));

        // Register all Relayers
        for (uint256 i = 0; i < relayerCount; i++) {
            uint256 stake = _initialStakeAmount;
            string memory endpoint = "test";
            uint256 delegatorPoolPremiumShare = 100;
            RelayerAddress relayerAddress = relayerMainAddress[i];

            _startPrankRA(relayerAddress);
            bico.approve(address(ta), stake);
            vm.stopPrank();

            _register(
                relayerAddress,
                ta.getStakeArray(activeRelayers),
                ta.getDelegationArray(activeRelayers),
                stake,
                relayerAccountAddresses[relayerAddress],
                endpoint,
                delegatorPoolPremiumShare
            );
        }

        for (uint256 i = 0; i < userCount; i++) {
            txns.push(abi.encodeCall(IMinimalApplication.executeMinimalApplication, (keccak256(abi.encodePacked(i)))));
        }

        _postRegistrationSnapshotId = vm.snapshot();
    }

    function _preTestSnapshotId() internal view virtual override returns (uint256) {
        return _postRegistrationSnapshotId;
    }

    function _getRelayerAssignedToTx(bytes memory _tx, uint16[] memory _cdf, uint256 _currentCdfLogIndex)
        internal
        returns (RelayerAddress, uint256, uint256)
    {
        bytes[] memory txns_ = new bytes[](1);
        txns_[0] = _tx;

        for (uint256 i = 0; i < relayerMainAddress.length; i++) {
            RelayerAddress relayerAddress = relayerMainAddress[i];
            (bytes[] memory allotedTransactions, uint256 relayerGenerationIterations, uint256 selectedRelayerCdfIndex) =
            tam.allocateMinimalApplicationTransaction(
                AllocateTransactionParams({
                    relayerAddress: relayerAddress,
                    requests: txns_,
                    cdf: _cdf,
                    currentCdfLogIndex: _currentCdfLogIndex,
                    activeRelayers: activeRelayers,
                    relayerLogIndex: 1
                })
            );

            if (allotedTransactions.length == 1) {
                return (relayerAddress, relayerGenerationIterations, selectedRelayerCdfIndex);
            }
        }

        fail("No relayer found");
        return (RelayerAddress.wrap(address(0)), 0, 0);
    }

    function testTransactionExecution() external atSnapshot {
        vm.roll(block.number + WINDOWS_PER_EPOCH * deployParams.blocksPerWindow);

        uint256 executionCount = 0;
        uint16[] memory cdf = ta.getCdfArray(activeRelayers);
        for (uint256 i = 0; i < relayerMainAddress.length; i++) {
            RelayerAddress relayerAddress = relayerMainAddress[i];
            (bytes[] memory allotedTransactions, uint256 relayerGenerationIterations, uint256 selectedRelayerCdfIndex) =
            tam.allocateMinimalApplicationTransaction(
                AllocateTransactionParams({
                    relayerAddress: relayerAddress,
                    requests: txns,
                    cdf: cdf,
                    currentCdfLogIndex: 1,
                    activeRelayers: activeRelayers,
                    relayerLogIndex: 1
                })
            );

            if (allotedTransactions.length == 0) {
                continue;
            }

            _startPrankRAA(relayerAccountAddresses[relayerMainAddress[i]][0]);
            bool[] memory successes = ta.execute(
                allotedTransactions,
                new uint256[](allotedTransactions.length),
                cdf,
                1,
                activeRelayers,
                1,
                selectedRelayerCdfIndex,
                relayerGenerationIterations
            );
            vm.stopPrank();

            executionCount += allotedTransactions.length;

            assertEq(successes.length, allotedTransactions.length);

            for (uint256 j = 0; j < allotedTransactions.length; j++) {
                assertEq(successes[j], true);
            }
        }

        assertEq(executionCount, txns.length);
        assertEq(tam.count(), executionCount);
    }

    function testCannotExecuteTransactionWithInvalidCdf() external atSnapshot {
        vm.roll(block.number + WINDOWS_PER_EPOCH * deployParams.blocksPerWindow);

        uint16[] memory cdf = ta.getCdfArray(activeRelayers);
        uint16[] memory cdf2 = ta.getCdfArray(activeRelayers);
        // Corrupt the CDF
        cdf2[0] += 1;

        for (uint256 i = 0; i < relayerMainAddress.length; i++) {
            RelayerAddress relayerAddress = relayerMainAddress[i];
            (bytes[] memory allotedTransactions, uint256 relayerGenerationIterations, uint256 selectedRelayerCdfIndex) =
            tam.allocateMinimalApplicationTransaction(
                AllocateTransactionParams({
                    relayerAddress: relayerAddress,
                    requests: txns,
                    cdf: cdf,
                    currentCdfLogIndex: 1,
                    activeRelayers: activeRelayers,
                    relayerLogIndex: 1
                })
            );

            if (allotedTransactions.length == 0) {
                continue;
            }

            _startPrankRAA(relayerAccountAddresses[relayerMainAddress[i]][0]);
            vm.expectRevert(InvalidCdfArrayHash.selector);
            ta.execute(
                allotedTransactions,
                new uint256[](allotedTransactions.length),
                cdf2,
                1,
                activeRelayers,
                1,
                selectedRelayerCdfIndex,
                relayerGenerationIterations
            );
            vm.stopPrank();
        }
    }

    function testCannotExecuteTransactionFromUnselectedRelayer() external atSnapshot {
        vm.roll(block.number + WINDOWS_PER_EPOCH * deployParams.blocksPerWindow);
        uint16[] memory cdf = ta.getCdfArray(activeRelayers);

        for (uint256 i = 0; i < relayerMainAddress.length; i++) {
            RelayerAddress relayerAddress = relayerMainAddress[i];
            (bytes[] memory allotedTransactions, uint256 relayerGenerationIterations, uint256 selectedRelayerCdfIndex) =
            tam.allocateMinimalApplicationTransaction(
                AllocateTransactionParams({
                    relayerAddress: relayerAddress,
                    requests: txns,
                    cdf: cdf,
                    currentCdfLogIndex: 1,
                    activeRelayers: activeRelayers,
                    relayerLogIndex: 1
                })
            );

            if (allotedTransactions.length == 0) {
                continue;
            }

            uint256 testRelayerIndex = (i + 1) % relayerMainAddress.length;

            _startPrankRAA(relayerAccountAddresses[relayerMainAddress[testRelayerIndex]][0]);
            vm.expectRevert(RelayerIndexDoesNotPointToSelectedCdfInterval.selector);
            ta.execute(
                allotedTransactions,
                new uint256[](allotedTransactions.length),
                cdf,
                1,
                activeRelayers,
                1,
                selectedRelayerCdfIndex + 1,
                relayerGenerationIterations
            );
            vm.stopPrank();
        }
    }

    // TODO: This test is suspicious
    function testCannotExecuteTransactionFromSelectedButNonAllotedRelayer() external atSnapshot {
        vm.roll(block.number + WINDOWS_PER_EPOCH * deployParams.blocksPerWindow);

        uint16[] memory cdf = ta.getCdfArray(activeRelayers);
        (RelayerAddress[] memory selectedRelayers,) = ta.allocateRelayers(cdf, 1, activeRelayers, 1);
        bool testRun = false;

        for (uint256 i = 0; i < relayerMainAddress.length; i++) {
            RelayerAddress relayerAddress = relayerMainAddress[i];
            (bytes[] memory allotedTransactions, uint256 relayerGenerationIterations, uint256 selectedRelayerCdfIndex) =
            tam.allocateMinimalApplicationTransaction(
                AllocateTransactionParams({
                    relayerAddress: relayerAddress,
                    requests: txns,
                    cdf: cdf,
                    currentCdfLogIndex: 1,
                    activeRelayers: activeRelayers,
                    relayerLogIndex: 1
                })
            );

            if (allotedTransactions.length == 0) {
                continue;
            }

            if (selectedRelayers[0] == relayerAddress) {
                continue;
            }

            testRun = true;

            _startPrankRAA(relayerAccountAddresses[selectedRelayers[0]][0]);
            vm.expectRevert(RelayerIndexDoesNotPointToSelectedCdfInterval.selector);
            ta.execute(
                allotedTransactions,
                new uint256[](allotedTransactions.length),
                cdf,
                1,
                activeRelayers,
                1,
                selectedRelayerCdfIndex + 1,
                relayerGenerationIterations
            );
            vm.stopPrank();
        }

        assertEq(testRun, true);
    }
}
