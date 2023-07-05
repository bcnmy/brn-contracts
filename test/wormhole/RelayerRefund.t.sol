// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import {VaaKey} from "wormhole-contracts/interfaces/relayer/IWormholeRelayerTyped.sol";
import "test/base/WormholeTestBase.sol";
import "wormhole-application/interfaces/IWormholeApplication.sol";
import "wormhole-application/interfaces/IBRNWormholeDeliveryProviderEventsErrors.sol";

contract WormholeRelayerRefundTest is WormholeTestBase, IBRNWormholeDeliveryProviderEventsErrors {
    RelayerAddress relayerAddress;
    VaaKey deliveryVaaKey;
    bytes signedDeliveryVAA;
    uint256 fundsDepositedForRelaying;
    bytes[] refundVAAs;

    function setUp() public override {
        super.setUp();
        _configureWormholeEnvironment();

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
        signedDeliveryVAA = _signWormholeVM(deliveryVM, sourceChain);
        deliveryVaaKey = VaaKey({
            emitterAddress: deliveryVM.emitterAddress,
            chainId: deliveryVM.emitterChainId,
            sequence: deliveryVM.sequence
        });

        fundsDepositedForRelaying = deliveryProviderSource.fundsDepositedForRelaying(deliveryVM.sequence);
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
        (RelayerAddress _relayerAddress, uint256 relayerGenerationIterations, uint256 selectedRelayerCdfIndex) =
            _getRelayerAssignedToTx(txn);
        relayerAddress = _relayerAddress;
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

        // Sign RefundVAA
        IWormhole.VM memory receiptVM =
            guardianTarget.parseVMFromLogs(guardianTarget.fetchWormholeMessageFromLog(vm.getRecordedLogs())[1]);
        bytes memory signedRefundVAA = _signWormholeVM(receiptVM, targetChain);
        refundVAAs.push(signedRefundVAA);
    }

    function _allocateTransactions(
        RelayerAddress _relayerAddress,
        bytes[] memory _txns,
        RelayerStateManager.RelayerState memory _relayerState
    ) internal view override returns (bytes[] memory, uint256, uint256) {
        return ta.allocateWormholeDeliveryVAA(_relayerAddress, _txns, _relayerState);
    }

    function testRelayerRefund() external {
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
        assertEq(deliveryProviderSource.fundsDepositedForRelaying(deliveryVaaKey.sequence), 0, "Funds were not cleared");
    }

    function testRelayerRefundWithRedeliveryRequest() external {
        // Send redelivery request
        vm.selectFork(sourceFork);
        uint256 newGasLimit = 200000;
        (LocalNative deliveryCost,) = deliveryProviderSource.quoteEvmDeliveryPrice(
            WormholeChainId.unwrap(targetChain), Gas.wrap(newGasLimit), TargetNative.wrap(0)
        );
        assertTrue(
            LocalNative.unwrap(deliveryCost) > fundsDepositedForRelaying,
            "Delivery cost is not greater than funds deposited"
        );
        vm.recordLogs();
        relayerSource.resendToEvm{value: LocalNative.unwrap(deliveryCost) - fundsDepositedForRelaying}(
            deliveryVaaKey,
            WormholeChainId.unwrap(targetChain),
            TargetNative.wrap(0),
            Gas.wrap(100000),
            address(deliveryProviderSource)
        );
        fundsDepositedForRelaying = LocalNative.unwrap(deliveryCost);
        // Sign redelivery VAA
        IWormhole.VM memory redeliveryVM = guardianSource.parseVMFromLogs(vm.getRecordedLogs()[0]);
        bytes[][] memory signedRedeliveryVAAs = new bytes[][](1);
        signedRedeliveryVAAs[0] = new bytes[](1);
        signedRedeliveryVAAs[0][0] = _signWormholeVM(redeliveryVM, sourceChain);

        // Claim
        _prankRA(relayerAddress);
        uint256 balance = address(RelayerAddress.unwrap(relayerAddress)).balance;
        deliveryProviderSource.claimFee(refundVAAs, signedRedeliveryVAAs);
        assertEq(
            address(RelayerAddress.unwrap(relayerAddress)).balance,
            balance + fundsDepositedForRelaying,
            "Relayer was not refunded"
        );
        assertEq(deliveryProviderSource.fundsDepositedForRelaying(deliveryVaaKey.sequence), 0, "Funds were not cleared");
    }

    function testShouldNotProcessRefundIfParamtersLengthMismatch() external {
        vm.selectFork(sourceFork);
        _prankRA(relayerAddress);
        vm.expectRevert(ParamterLengthMismatch.selector);
        deliveryProviderSource.claimFee(refundVAAs, new bytes[][](0));
    }

    function testShouldNotProcessRefundWithInvalidReceiptVAA() external {
        vm.selectFork(sourceFork);
        refundVAAs[0][1] = bytes1(uint8(0x12));

        _prankRA(relayerAddress);
        vm.expectRevert(abi.encodeWithSelector(WormholeVAAVerificationFailed.selector, "invalid guardian set"));
        deliveryProviderSource.claimFee(refundVAAs, new bytes[][](1));
    }

    function testShouldNotProcessRefundWithReceiptEmitterFromNonTransactionAllocatorContract() external {
        vm.selectFork(sourceFork);
        // Change transaction allocator contract for target chain
        vm.prank(brnOwnerAddress);
        bytes32 newTransactionAllocatorAddress = toWormholeFormat(address(0x1));
        deliveryProviderSource.setBrnTransactionAllocatorAddress(targetChain, newTransactionAllocatorAddress);

        _prankRA(relayerAddress);
        vm.expectRevert(
            abi.encodeWithSelector(
                WormholeReceiptVAAEmitterMismatch.selector,
                newTransactionAllocatorAddress,
                toWormholeFormat(address(ta))
            )
        );
        deliveryProviderSource.claimFee(refundVAAs, new bytes[][](1));
    }

    function testShouldNotProcessRefundWithReceiptForAnotherChain() external {
        // Submit the delivery request on target chain instead of source chain
        vm.selectFork(targetFork);
        _prankRA(relayerAddress);
        vm.expectRevert(
            abi.encodeWithSelector(WormholeDeliveryVAASourceChainMismatch.selector, targetChain, sourceChain)
        );
        deliveryProviderTarget.claimFee(refundVAAs, new bytes[][](1));
    }

    function testShouldNotProcessRefundIfSenderIsNotTheRelayerWhichExecutedTheTransaction() external {
        vm.selectFork(sourceFork);
        RelayerAddress relayerAddress2;
        for (uint256 i = 0; i < relayerMainAddress.length; i++) {
            relayerAddress2 = relayerMainAddress[i];
            if (relayerAddress2 != relayerAddress) {
                break;
            }
        }

        _prankRA(relayerAddress2);
        vm.expectRevert(NotAuthorized.selector);
        deliveryProviderSource.claimFee(refundVAAs, new bytes[][](1));
    }

    function testShouldNotProcessRefundWithInvalidRedeliveryVAA() external {
        // Send redelivery request
        vm.selectFork(sourceFork);
        uint256 newGasLimit = 200000;
        (LocalNative deliveryCost,) = deliveryProviderSource.quoteEvmDeliveryPrice(
            WormholeChainId.unwrap(targetChain), Gas.wrap(newGasLimit), TargetNative.wrap(0)
        );
        vm.recordLogs();
        relayerSource.resendToEvm{value: LocalNative.unwrap(deliveryCost) - fundsDepositedForRelaying}(
            deliveryVaaKey,
            WormholeChainId.unwrap(targetChain),
            TargetNative.wrap(0),
            Gas.wrap(100000),
            address(deliveryProviderSource)
        );
        fundsDepositedForRelaying = LocalNative.unwrap(deliveryCost);
        // Sign redelivery VAA
        IWormhole.VM memory redeliveryVM = guardianSource.parseVMFromLogs(vm.getRecordedLogs()[0]);
        bytes[][] memory signedRedeliveryVAAs = new bytes[][](1);
        signedRedeliveryVAAs[0] = new bytes[](1);
        signedRedeliveryVAAs[0][0] = _signWormholeVM(redeliveryVM, sourceChain);

        // Corrupt redelivery VAA
        signedRedeliveryVAAs[0][0][1] = bytes1(uint8(0x12));

        _prankRA(relayerAddress);
        vm.expectRevert(abi.encodeWithSelector(WormholeVAAVerificationFailed.selector, "invalid guardian set"));
        deliveryProviderSource.claimFee(refundVAAs, signedRedeliveryVAAs);
    }

    function testShouldNotProcessRefundWithRedeliveryVAAEmittedFromChainOtherThanSourceChain() external {
        // Send redelivery request
        vm.selectFork(sourceFork);
        uint256 newGasLimit = 200000;
        (LocalNative deliveryCost,) = deliveryProviderSource.quoteEvmDeliveryPrice(
            WormholeChainId.unwrap(targetChain), Gas.wrap(newGasLimit), TargetNative.wrap(0)
        );
        vm.recordLogs();
        relayerSource.resendToEvm{value: LocalNative.unwrap(deliveryCost) - fundsDepositedForRelaying}(
            deliveryVaaKey,
            WormholeChainId.unwrap(targetChain),
            TargetNative.wrap(0),
            Gas.wrap(100000),
            address(deliveryProviderSource)
        );
        fundsDepositedForRelaying = LocalNative.unwrap(deliveryCost);
        // Sign redelivery VAA
        IWormhole.VM memory redeliveryVM = guardianSource.parseVMFromLogs(vm.getRecordedLogs()[0]);
        bytes[][] memory signedRedeliveryVAAs = new bytes[][](1);
        signedRedeliveryVAAs[0] = new bytes[](1);
        // Change redelivery VM emitter chain
        vm.selectFork(targetFork);
        signedRedeliveryVAAs[0][0] = _signWormholeVM(redeliveryVM, targetChain);
        vm.selectFork(sourceFork);

        _prankRA(relayerAddress);
        vm.expectRevert(
            abi.encodeWithSelector(WormholeRedeliveryVAAEmitterChainMismatch.selector, sourceChain, targetChain)
        );
        deliveryProviderSource.claimFee(refundVAAs, signedRedeliveryVAAs);
    }

    function testShouldNotProcessRefundWithRedeliveryVAAEmittedFromContractOtherThanWormholeRelayer() external {
        // Send redelivery request
        vm.selectFork(sourceFork);
        uint256 newGasLimit = 200000;
        (LocalNative deliveryCost,) = deliveryProviderSource.quoteEvmDeliveryPrice(
            WormholeChainId.unwrap(targetChain), Gas.wrap(newGasLimit), TargetNative.wrap(0)
        );
        vm.recordLogs();
        relayerSource.resendToEvm{value: LocalNative.unwrap(deliveryCost) - fundsDepositedForRelaying}(
            deliveryVaaKey,
            WormholeChainId.unwrap(targetChain),
            TargetNative.wrap(0),
            Gas.wrap(100000),
            address(deliveryProviderSource)
        );
        fundsDepositedForRelaying = LocalNative.unwrap(deliveryCost);
        // Sign redelivery VAA
        IWormhole.VM memory redeliveryVM = guardianSource.parseVMFromLogs(vm.getRecordedLogs()[0]);
        // Change redelivery VM emitter contract
        redeliveryVM.emitterAddress = keccak256(abi.encodePacked("random address"));

        bytes[][] memory signedRedeliveryVAAs = new bytes[][](1);
        signedRedeliveryVAAs[0] = new bytes[](1);
        signedRedeliveryVAAs[0][0] = _signWormholeVM(redeliveryVM, sourceChain);

        _prankRA(relayerAddress);
        vm.expectRevert(
            abi.encodeWithSelector(
                WormholeRedeliveryVAAEmitterMismatch.selector,
                toWormholeFormat(address(relayerSource)),
                redeliveryVM.emitterAddress
            )
        );
        deliveryProviderSource.claimFee(refundVAAs, signedRedeliveryVAAs);
    }

    function testShouldNotProcessRefundWithRedeliveryVAAIfItDoesNotMatchWithProvidedDeliveryVAA() external {
        // Send redelivery request
        vm.selectFork(sourceFork);
        uint256 newGasLimit = 200000;
        (LocalNative deliveryCost,) = deliveryProviderSource.quoteEvmDeliveryPrice(
            WormholeChainId.unwrap(targetChain), Gas.wrap(newGasLimit), TargetNative.wrap(0)
        );
        vm.recordLogs();

        // Change the delivery VAA key
        VaaKey memory originalDeliveryVaaKey = deliveryVaaKey;
        deliveryVaaKey.sequence += 1;

        relayerSource.resendToEvm{value: LocalNative.unwrap(deliveryCost) - fundsDepositedForRelaying}(
            deliveryVaaKey,
            WormholeChainId.unwrap(targetChain),
            TargetNative.wrap(0),
            Gas.wrap(100000),
            address(deliveryProviderSource)
        );
        fundsDepositedForRelaying = LocalNative.unwrap(deliveryCost);
        // Sign redelivery VAA
        IWormhole.VM memory redeliveryVM = guardianSource.parseVMFromLogs(vm.getRecordedLogs()[0]);

        bytes[][] memory signedRedeliveryVAAs = new bytes[][](1);
        signedRedeliveryVAAs[0] = new bytes[](1);
        signedRedeliveryVAAs[0][0] = _signWormholeVM(redeliveryVM, sourceChain);

        _prankRA(relayerAddress);
        vm.expectRevert(
            abi.encodeWithSelector(WormholeRedeliveryVAAKeyMismatch.selector, originalDeliveryVaaKey, deliveryVaaKey)
        );
        deliveryProviderSource.claimFee(refundVAAs, signedRedeliveryVAAs);
    }
}
