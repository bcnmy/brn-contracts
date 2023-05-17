// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import "./base/TATestBase.t.sol";
import "src/transaction-allocator/common/TAConstants.sol";
import "src/transaction-allocator/modules/transaction-allocation/interfaces/ITATransactionAllocationEventsErrors.sol";
import "src/transaction-allocator/common/interfaces/ITAHelpers.sol";
import "src/transaction-allocator/modules/application/wormhole/interfaces/IWormholeApplicationEventsErrors.sol";

contract WormholeApplicationTest is
    TATestBase,
    ITATransactionAllocationEventsErrors,
    ITAHelpers,
    IWormholeApplicationEventsErrors
{
    uint256 constant initialApplicationFunds = 10 ether;

    uint256 private _postRegistrationSnapshotId;
    uint256 private constant _initialStakeAmount = MINIMUM_STAKE_AMOUNT;
    bytes[] private txns;

    bytes constant defaultVAA =
        hex"01000000000100dd9410ea42cce096a51f9c02a91ed565d71e5cfdd09966e5246c1d3cd4064ad97fb8bce9993227fbaf4d366fc8b3e73029bc7565f6ad4473f29a3532e8b1f9060163bff8f400000041000500000000000000000000000084fee39095b18962b875588df7f9ad1be87e86530000000000000041c875e5f7065b71d698d6ab1bf73f7b0604a5c9f3015ab01248fbc127af5a8e3c2a";

    IDelivery deliveryMock = IDelivery(address(0xFFF01));
    IWormhole wormholeMock = IWormhole(address(0xFFF02));
    IWormholeApplication taw;

    function setUp() public override {
        if (_postRegistrationSnapshotId != 0) {
            return;
        }

        if (tx.gasprice == 0) {
            fail("Gas Price is 0. Please set it to 1 gwei or more.");
        }

        super.setUp();

        taw = IWormholeApplication(address(ta));
        taw.initialize(wormholeMock, deliveryMock);

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
            txns.push(
                abi.encodeCall(
                    taw.executeWormhole,
                    (
                        IDelivery.TargetDeliveryParameters({
                            encodedVMs: new bytes[](0),
                            encodedDeliveryVAA: defaultVAA,
                            relayerRefundAddress: payable(address(taw)),
                            overrides: bytes("")
                        })
                    )
                )
            );
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
            taw.allocateWormholeDeliveryVAA(
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

    function testWHTransactionExecution() external atSnapshot {
        vm.roll(block.number + WINDOWS_PER_EPOCH * deployParams.blocksPerWindow);

        // Setup Mocks
        vm.mockCall(
            address(wormholeMock), abi.encodePacked(wormholeMock.publishMessage.selector), abi.encode(uint64(1))
        );
        vm.etch(address(wormholeMock), address(ta).code);
        vm.mockCall(address(deliveryMock), abi.encodePacked(deliveryMock.deliver.selector), bytes(""));
        vm.etch(address(deliveryMock), address(ta).code);

        uint256 executionCount = 0;
        uint16[] memory cdf = ta.getCdfArray(activeRelayers);
        for (uint256 i = 0; i < relayerMainAddress.length; i++) {
            RelayerAddress relayerAddress = relayerMainAddress[i];
            (bytes[] memory allotedTransactions, uint256 relayerGenerationIterations, uint256 selectedRelayerCdfIndex) =
            taw.allocateWormholeDeliveryVAA(
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

            // Create native value array
            uint256[] memory values = new uint256[](allotedTransactions.length);
            for (uint256 j = 0; j < allotedTransactions.length; j++) {
                values[j] = 0.001 ether;
            }

            // Check Events
            for (uint256 j = 0; j < allotedTransactions.length; ++j) {
                vm.expectEmit(true, true, false, false);
                emit WormholeDeliveryExecuted(defaultVAA);
            }

            ta.execute{value: 0.001 ether * allotedTransactions.length}(
                allotedTransactions,
                values,
                cdf,
                1,
                activeRelayers,
                1,
                selectedRelayerCdfIndex,
                relayerGenerationIterations
            );
            vm.stopPrank();

            executionCount += allotedTransactions.length;
        }

        assertEq(executionCount, txns.length);
        vm.clearMockedCalls();
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
            taw.allocateWormholeDeliveryVAA(
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
            taw.allocateWormholeDeliveryVAA(
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

            _startPrankRAA(relayerAccountAddresses[relayerMainAddress[(i + 1) % relayerMainAddress.length]][0]);
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
            (bytes[] memory allotedTransactions, uint256 relayerGenerationIteration, uint256 selectedRelayerCdfIndex) =
            taw.allocateWormholeDeliveryVAA(
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

            if (selectedRelayers[1] == relayerAddress) {
                continue;
            }

            testRun = true;

            _startPrankRAA(relayerAccountAddresses[selectedRelayers[1]][0]);
            vm.expectRevert(RelayerIndexDoesNotPointToSelectedCdfInterval.selector);
            ta.execute(
                allotedTransactions,
                new uint256[](allotedTransactions.length),
                cdf,
                1,
                activeRelayers,
                1,
                selectedRelayerCdfIndex + 1,
                relayerGenerationIteration
            );
            vm.stopPrank();
        }

        assertEq(testRun, true);
    }
}
