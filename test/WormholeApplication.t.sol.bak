// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import "./base/TATestBase.sol";
import "ta-transaction-allocation/interfaces/ITATransactionAllocationEventsErrors.sol";
import "ta-common/interfaces/ITAHelpers.sol";
import "wormhole-application/interfaces/IWormholeApplicationEventsErrors.sol";

contract WormholeApplicationTest is
    TATestBase,
    ITATransactionAllocationEventsErrors,
    ITAHelpers,
    IWormholeApplicationEventsErrors
{
    bytes[] private txns;

    bytes constant defaultVAA =
        hex"01000000000100dd9410ea42cce096a51f9c02a91ed565d71e5cfdd09966e5246c1d3cd4064ad97fb8bce9993227fbaf4d366fc8b3e73029bc7565f6ad4473f29a3532e8b1f9060163bff8f400000041000500000000000000000000000084fee39095b18962b875588df7f9ad1be87e86530000000000000041c875e5f7065b71d698d6ab1bf73f7b0604a5c9f3015ab01248fbc127af5a8e3c2a";

    IWormholeRelayerDelivery deliveryMock = IWormholeRelayerDelivery(address(0xFFF01));
    IWormhole wormholeMock = IWormhole(address(0xFFF02));

    function setUp() public override {
        if (tx.gasprice == 0) {
            fail("Gas Price is 0. Please set it to 1 gwei or more.");
        }

        super.setUp();

        ta.initialize(wormholeMock, deliveryMock);

        RelayerState memory currentState = latestRelayerState;
        _registerAllNonFoundationRelayers();
        _moveForwardToNextEpoch();
        _sendEmptyTransaction(currentState);
        _moveForwardByWindows(deployParams.relayerStateUpdateDelayInWindows);

        for (uint256 i = 0; i < userCount; i++) {
            txns.push(abi.encodeCall(ta.executeWormhole, (new bytes[](0), defaultVAA, payable(address(ta)), bytes(""))));
        }
    }

    function _allocateTransactions(
        RelayerAddress _relayerAddress,
        bytes[] memory _txns,
        RelayerState memory _relayerState
    ) internal view override returns (bytes[] memory, uint256, uint256) {
        return ta.allocateWormholeDeliveryVAA(_relayerAddress, _txns, _relayerState);
    }

    function testWHTransactionExecution() external {
        // Setup Mocks
        vm.mockCall(
            address(wormholeMock), abi.encodePacked(wormholeMock.publishMessage.selector), abi.encode(uint64(1))
        );
        vm.etch(address(wormholeMock), address(ta).code);
        vm.mockCall(address(deliveryMock), abi.encodePacked(deliveryMock.deliver.selector), bytes(""));
        vm.etch(address(deliveryMock), address(ta).code);

        uint256 executionCount = 0;

        for (uint256 i = 0; i < relayerMainAddress.length; i++) {
            RelayerAddress relayerAddress = relayerMainAddress[i];
            (bytes[] memory allotedTransactions, uint256 relayerGenerationIterations, uint256 selectedRelayerCdfIndex) =
                _allocateTransactions(relayerAddress, txns, latestRelayerState);

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
                ITATransactionAllocation.ExecuteParams({
                    reqs: allotedTransactions,
                    forwardedNativeAmounts: values,
                    relayerIndex: selectedRelayerCdfIndex,
                    relayerGenerationIterationBitmap: relayerGenerationIterations,
                    activeState: latestRelayerState,
                    latestState: latestRelayerState,
                    activeStateToPendingStateMap: _generateActiveStateToPendingStateMap(latestRelayerState)
                })
            );

            vm.stopPrank();

            executionCount += allotedTransactions.length;
        }

        assertEq(executionCount, txns.length);
        vm.clearMockedCalls();
    }

    function testCannotExecuteTransactionFromSelectedButNonAllotedRelayer() external {
        (RelayerAddress[] memory selectedRelayers,) = ta.allocateRelayers(latestRelayerState);
        bool testRun = false;

        for (uint256 i = 0; i < relayerMainAddress.length; i++) {
            RelayerAddress relayerAddress = relayerMainAddress[i];
            (bytes[] memory allotedTransactions, uint256 relayerGenerationIterations,) =
                _allocateTransactions(relayerAddress, txns, latestRelayerState);

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
                ITATransactionAllocation.ExecuteParams({
                    reqs: allotedTransactions,
                    forwardedNativeAmounts: new uint256[](allotedTransactions.length),
                    relayerIndex: _findRelayerIndex(selectedRelayers[0]),
                    relayerGenerationIterationBitmap: relayerGenerationIterations,
                    activeState: latestRelayerState,
                    latestState: latestRelayerState,
                    activeStateToPendingStateMap: _generateActiveStateToPendingStateMap(latestRelayerState)
                })
            );
            vm.stopPrank();
        }

        assertEq(testRun, true);
    }
}
