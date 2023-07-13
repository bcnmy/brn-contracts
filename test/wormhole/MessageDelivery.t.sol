// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import "test/base/WormholeTestBase.sol";
import "wormhole-application/interfaces/IWormholeApplication.sol";
import "ta-transaction-allocation/interfaces/ITATransactionAllocation.sol";

contract WormholeMessageDeliveryTest is WormholeTestBase, ITATransactionAllocationEventsErrors {
    using BytesLib for bytes;

    function setUp() public override {
        super.setUp();
        _configureWormholeEnvironment();
    }

    function _allocateTransactions(
        RelayerAddress _relayerAddress,
        bytes[] memory _txns,
        RelayerStateManager.RelayerState memory _relayerState
    ) internal view override returns (bytes[] memory, uint256, uint256) {
        return ta.allocateWormholeDeliveryVAA(_relayerAddress, _txns, _relayerState);
    }

    function testMessagePassingWithPayloadInDeliveryRequest() external {
        uint256 payload = 0x123;

        // Send payload from source chain
        vm.selectFork(sourceFork);
        vm.recordLogs();
        receiverSource.sendPayload(
            targetChain, payload, Gas.wrap(100000), TargetNative.wrap(0), address(receiverTarget)
        );
        Vm.Log[] memory deliveryVMLogs = guardianSource.fetchWormholeMessageFromLog(vm.getRecordedLogs());
        assertTrue(deliveryVMLogs.length > 0, "No delivery request was published");

        // Sign the delivery request
        IWormhole.VM memory deliveryVM = guardianSource.parseVMFromLogs(deliveryVMLogs[0]);
        bytes memory signedDeliveryVAA = _signWormholeVM(deliveryVM, sourceChain);

        // Execute the delivery request on destination chain
        vm.selectFork(targetFork);
        assertEq(receiverTarget.sum(), 0, "Payload was delivered before execution");

        bytes memory txn =
            abi.encodeCall(IWormholeApplication.executeWormhole, (new bytes[](0), signedDeliveryVAA, bytes("")));
        bytes[] memory txns = new bytes[](1);
        txns[0] = txn;
        uint256[] memory forwardedNativeAmounts = new uint256[](1);
        forwardedNativeAmounts[0] = 1 ether;
        (RelayerAddress relayerAddress, uint256 relayerGenerationIterations, uint256 selectedRelayerCdfIndex) =
            _getRelayerAssignedToTx(txn);
        _prankRA(relayerAddress);
        ta.execute{value: forwardedNativeAmounts[0]}(
            ITATransactionAllocation.ExecuteParams({
                reqs: txns,
                forwardedNativeAmounts: forwardedNativeAmounts,
                relayerIndex: selectedRelayerCdfIndex,
                relayerGenerationIterationBitmap: relayerGenerationIterations,
                activeState: latestRelayerState,
                latestState: latestRelayerState
            })
        );

        assertEq(receiverTarget.sum(), payload, "Payload was not delivered");
    }

    function testMessagePassingWithPaylodInVAA() external {
        // Prepare the payloads
        uint256 payload = 0x123;
        uint256[] memory vaaPayloads = new uint256[](10);
        uint256 payloadSum = payload;
        for (uint256 i = 0; i < vaaPayloads.length; i++) {
            vaaPayloads[i] = payload * (i + 1);
            payloadSum += vaaPayloads[i];
        }

        // Send payload from source chain
        vm.selectFork(sourceFork);
        vm.recordLogs();
        receiverSource.sendPayloadAndAdditionalVAA(
            targetChain, payload, vaaPayloads, Gas.wrap(1000000), TargetNative.wrap(0), address(receiverTarget)
        );
        Vm.Log[] memory deliveryVMLogs = guardianSource.fetchWormholeMessageFromLog(vm.getRecordedLogs());
        assertTrue(deliveryVMLogs.length > 0, "No delivery request was published");

        // Sign the message vm and delivery request vm
        bytes[] memory vaaPayloadsSigned = new bytes[](vaaPayloads.length);
        for (uint256 i = 0; i < vaaPayloads.length; ++i) {
            IWormhole.VM memory payloadVM = guardianSource.parseVMFromLogs(deliveryVMLogs[i]);
            vaaPayloadsSigned[i] = _signWormholeVM(payloadVM, sourceChain);
        }
        IWormhole.VM memory deliveryVM = guardianSource.parseVMFromLogs(deliveryVMLogs[vaaPayloads.length]);
        bytes memory signedDeliveryVAA = _signWormholeVM(deliveryVM, sourceChain);

        // Execute the delivery request on destination chain
        vm.selectFork(targetFork);
        assertEq(receiverTarget.sum(), 0, "Payload was delivered before execution");

        bytes memory txn =
            abi.encodeCall(IWormholeApplication.executeWormhole, (vaaPayloadsSigned, signedDeliveryVAA, bytes("")));
        bytes[] memory txns = new bytes[](1);
        txns[0] = txn;
        uint256[] memory forwardedNativeAmounts = new uint256[](1);
        forwardedNativeAmounts[0] = 1 ether;
        (RelayerAddress relayerAddress, uint256 relayerGenerationIterations, uint256 selectedRelayerCdfIndex) =
            _getRelayerAssignedToTx(txn);
        _prankRA(relayerAddress);
        ta.execute{value: forwardedNativeAmounts[0]}(
            ITATransactionAllocation.ExecuteParams({
                reqs: txns,
                forwardedNativeAmounts: forwardedNativeAmounts,
                relayerIndex: selectedRelayerCdfIndex,
                relayerGenerationIterationBitmap: relayerGenerationIterations,
                activeState: latestRelayerState,
                latestState: latestRelayerState
            })
        );

        assertEq(receiverTarget.sum(), payloadSum, "Payload was not delivered");
    }

    function testShouldNotGenerateReceiptIfVAAIsInvalid() external {
        uint256 payload = 0x123;

        // Send payload from source chain
        vm.selectFork(sourceFork);
        vm.recordLogs();
        receiverSource.sendPayload(
            targetChain, payload, Gas.wrap(100000), TargetNative.wrap(0), address(receiverTarget)
        );
        Vm.Log[] memory deliveryVMLogs = guardianSource.fetchWormholeMessageFromLog(vm.getRecordedLogs());
        assertTrue(deliveryVMLogs.length > 0, "No delivery request was published");

        // Sign the delivery request
        IWormhole.VM memory deliveryVM = guardianSource.parseVMFromLogs(deliveryVMLogs[0]);
        bytes memory signedDeliveryVAA = _signWormholeVM(deliveryVM, sourceChain);

        // Execute the delivery request on destination chain
        vm.selectFork(targetFork);
        assertEq(receiverTarget.sum(), 0, "Payload was delivered before execution");

        // Mock wormhole core to revert when parseAndVerifyVM is called
        bytes memory error = abi.encode("MOCKED_REVERT");
        vm.mockCallRevert(
            address(wormholeTarget), abi.encodeWithSelector(wormholeTarget.parseAndVerifyVM.selector), error
        );

        bytes memory txn =
            abi.encodeCall(IWormholeApplication.executeWormhole, (new bytes[](0), signedDeliveryVAA, bytes("")));
        bytes[] memory txns = new bytes[](1);
        txns[0] = txn;
        uint256[] memory forwardedNativeAmounts = new uint256[](1);
        forwardedNativeAmounts[0] = 1 ether;
        (RelayerAddress relayerAddress, uint256 relayerGenerationIterations, uint256 selectedRelayerCdfIndex) =
            _getRelayerAssignedToTx(txn);
        _prankRA(relayerAddress);

        vm.expectRevert(abi.encodeWithSelector(TransactionExecutionFailed.selector, 0, error));
        ta.execute{value: forwardedNativeAmounts[0]}(
            ITATransactionAllocation.ExecuteParams({
                reqs: txns,
                forwardedNativeAmounts: forwardedNativeAmounts,
                relayerIndex: selectedRelayerCdfIndex,
                relayerGenerationIterationBitmap: relayerGenerationIterations,
                activeState: latestRelayerState,
                latestState: latestRelayerState
            })
        );
    }
}
