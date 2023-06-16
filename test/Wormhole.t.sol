// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import "src/library/AddressUtils.sol";
import "./base/WormholeTestBase.sol";
import "wormhole-application/interfaces/IWormholeApplication.sol";

contract WormholeTest is WormholeTestBase {
    using AddressUtils for address;

    GasPrice constant sourceChainGasPrice = GasPrice.wrap(25 wei); // 25 nAVAX
    GasPrice constant targetChainGasPrice = GasPrice.wrap(16 gwei); // 16 gwei MATIC

    WeiPrice constant sourceChainNativeTokenPrice = WeiPrice.wrap(11.5 * 1 ether); // $11.5, AVAX
    WeiPrice constant targetChainNativeTokenPrice = WeiPrice.wrap(0.59 * 1 ether); // $0.59, MATIC

    function setUp() public override {
        super.setUp();

        // Populate Test Data for Oracles on Source Chain
        vm.selectFork(sourceFork);
        vm.startPrank(brnOwnerAddress);
        deliveryProviderSource.setGasPrice(targetChain, targetChainGasPrice);
        deliveryProviderSource.setNativeCurrencyPrice(sourceChain, sourceChainNativeTokenPrice);
        deliveryProviderSource.setNativeCurrencyPrice(targetChain, targetChainNativeTokenPrice);
        deliveryProviderSource.setDeliverGasOverhead(targetChain, Gas.wrap(100_000));
        deliveryProviderSource.setMaximumBudget(targetChain, Wei.wrap(10_000_000 * 1 ether));
        deliveryProviderSource.setIsWormholeChainSupported(targetChain, true);
        deliveryProviderSource.setBrnRelayerProviderAddress(targetChain, address(deliveryProviderTarget).toBytes32());
        deliveryProviderSource.setAssetConversionBuffer(
            targetChain, IBRNWormholeDeliveryProvider.AssetConversion({denominator: 100, buffer: 10})
        );
        vm.stopPrank();

        deal(address(receiverSource), 10000 ether);

        // Populate Test Data for Oracles on Destination Chain
        vm.selectFork(targetFork);
        vm.startPrank(brnOwnerAddress);
        deliveryProviderTarget.setGasPrice(sourceChain, sourceChainGasPrice);
        deliveryProviderTarget.setNativeCurrencyPrice(sourceChain, sourceChainNativeTokenPrice);
        deliveryProviderTarget.setNativeCurrencyPrice(targetChain, targetChainNativeTokenPrice);
        deliveryProviderTarget.setDeliverGasOverhead(sourceChain, Gas.wrap(100_000));
        deliveryProviderTarget.setMaximumBudget(sourceChain, Wei.wrap(10_000_000 * 1 ether));
        deliveryProviderTarget.setIsWormholeChainSupported(sourceChain, true);
        deliveryProviderTarget.setBrnRelayerProviderAddress(sourceChain, address(deliveryProviderSource).toBytes32());
        deliveryProviderTarget.setAssetConversionBuffer(
            sourceChain, IBRNWormholeDeliveryProvider.AssetConversion({denominator: 100, buffer: 10})
        );
        vm.stopPrank();
    }

    function _allocateTransactions(
        RelayerAddress _relayerAddress,
        bytes[] memory _txns,
        RelayerState memory _relayerState
    ) internal view override returns (bytes[] memory, uint256, uint256) {
        return ta.allocateWormholeDeliveryVAA(_relayerAddress, _txns, _relayerState);
    }

    function testMessagePassing() external {
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
        deliveryVM.emitterChainId = WormholeChainId.unwrap(sourceChain);
        deliveryVM.version = 1;
        bytes memory signedDeliveryVAA = guardianSource.encodeAndSignMessage(deliveryVM);

        // Execute the delivery request on destination chain
        vm.selectFork(targetFork);
        assertEq(receiverTarget.sum(), 0, "Payload was delivered before execution");

        bytes memory txn =
            abi.encodeCall(IWormholeApplication.executeWormhole, (new bytes[](0), signedDeliveryVAA, bytes("")));
        bytes[] memory txns = new bytes[](1);
        txns[0] = txn;
        uint256[] memory forwardedNativeAmounts = new uint256[](1);
        // TODO: Calculate and Validate this amount
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

        assertEq(receiverTarget.sum(), payload, "Payload was not delivered");
    }
}
