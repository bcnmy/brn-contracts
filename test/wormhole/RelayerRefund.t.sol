// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import "test/base/WormholeTestBase.sol";
import "wormhole-application/interfaces/IWormholeApplication.sol";

contract WormholeRelayerRefundTest is WormholeTestBase {
    function setUp() public override {
        super.setUp();
        _configureWormholeEnvironment();
    }

    function _allocateTransactions(
        RelayerAddress _relayerAddress,
        bytes[] memory _txns,
        RelayerState memory _relayerState
    ) internal view override returns (bytes[] memory, uint256, uint256) {
        return ta.allocateWormholeDeliveryVAA(_relayerAddress, _txns, _relayerState);
    }

    function testRelayerRefund() external {
        uint256 payload = 0x123;

        // Send payload from source chain
        vm.selectFork(sourceFork);
        vm.recordLogs();
        receiverSource.sendPayload(
            targetChain, payload, Gas.wrap(100000), TargetNative.wrap(0), address(receiverTarget)
        );
        Vm.Log[] memory deliveryVMLogs = guardianSource.fetchWormholeMessageFromLog(vm.getRecordedLogs());

        // Sign the delivery request
        IWormhole.VM memory deliveryVM = guardianSource.parseVMFromLogs(deliveryVMLogs[0]);
        bytes memory signedDeliveryVAA = _signWormholeVM(deliveryVM, sourceChain);

        uint256 fundsDepositedForRelaying = deliveryProviderSource.fundsDepositedForRelaying(deliveryVM.sequence);
        assertTrue(fundsDepositedForRelaying > 0, "No funds deposited");

        // Execute the delivery request on destination chain
        vm.selectFork(targetFork);

        bytes memory txn =
            abi.encodeCall(IWormholeApplication.executeWormhole, (new bytes[](0), signedDeliveryVAA, bytes("")));
        bytes[] memory txns = new bytes[](1);
        txns[0] = txn;
        uint256[] memory forwardedNativeAmounts = new uint256[](1);
        vm.recordLogs();
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
                latestState: latestRelayerState,
                activeStateToPendingStateMap: _generateActiveStateToPendingStateMap(latestRelayerState)
            })
        );

        // Sign RefundVAA
        IWormhole.VM memory receiptVM =
            guardianTarget.parseVMFromLogs(guardianTarget.fetchWormholeMessageFromLog(vm.getRecordedLogs())[1]);
        bytes memory signedRefundVAA = _signWormholeVM(receiptVM, targetChain);
        bytes[] memory refundVAAs = new bytes[](1);
        refundVAAs[0] = signedRefundVAA;

        // Claim
        vm.selectFork(sourceFork);
        _prankRA(relayerAddress);
        uint256 balance = address(RelayerAddress.unwrap(relayerAddress)).balance;
        deliveryProviderSource.claimFee(refundVAAs, new bytes[][](1));
        assertEq(
            address(RelayerAddress.unwrap(relayerAddress)).balance,
            balance + fundsDepositedForRelaying,
            "Relayer was not refunded"
        );
        assertEq(deliveryProviderSource.fundsDepositedForRelaying(deliveryVM.sequence), 0, "Funds were not cleared");
    }
}
