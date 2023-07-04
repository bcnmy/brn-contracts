// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import {SigningWormholeSimulator} from "wormhole-contracts-test/relayer/WormholeSimulator.sol";
import {toWormholeFormat} from "wormhole-contracts/libraries/relayer/Utils.sol";

import "./TATestBase.sol";
import "wormhole-application/BRNWormholeDeliveryProvider.sol";
import "src/mock/wormhole/MockWormholeReceiver.sol";

abstract contract WormholeTestBase is TATestBase, IMockWormholeReceiver {
    uint256 constant sourceChainForkBlock = 23134119;
    uint256 constant targetChainForkBlock = 36895494;
    uint8 constant wormholeVMVersion = 1;

    WormholeChainId constant sourceChain = WormholeChainId.wrap(6); // fuji testnet
    WormholeChainId constant targetChain = WormholeChainId.wrap(5); // mumbai testnet

    uint256 sourceFork;
    uint256 targetFork;

    uint256 devnetPrivateKey;
    uint256 brnOwner;
    address brnOwnerAddress;

    // fuji testnet contracts
    IWormholeRelayer relayerSource = IWormholeRelayer(0xA3cF45939bD6260bcFe3D66bc73d60f19e49a8BB);
    IWormhole wormholeSource = IWormhole(0x7bbcE28e64B3F8b84d876Ab298393c38ad7aac4C);
    BRNWormholeDeliveryProvider deliveryProviderSource;
    SigningWormholeSimulator guardianSource;
    MockWormholeReceiver receiverSource;

    // mumbai testnet contracts
    IWormholeRelayer relayerTarget = IWormholeRelayer(0x0591C25ebd0580E0d4F27A82Fc2e24E7489CB5e0);
    IWormhole wormholeTarget = IWormhole(0x0CBE91CF822c73C2315FB05100C2F714765d5c20);
    BRNWormholeDeliveryProvider deliveryProviderTarget;
    SigningWormholeSimulator guardianTarget;
    MockWormholeReceiver receiverTarget;

    GasPrice sourceChainGasPrice = GasPrice.wrap(25 wei); // 25 nAVAX
    GasPrice targetChainGasPrice = GasPrice.wrap(16 gwei); // 16 gwei MATIC

    WeiPrice sourceChainNativeTokenPrice = WeiPrice.wrap(11.5 * 1 ether); // $11.5, AVAX
    WeiPrice targetChainNativeTokenPrice = WeiPrice.wrap(0.59 * 1 ether); // $0.59, MATIC

    mapping(WormholeChainId => SigningWormholeSimulator) guardians;

    function setUp() public virtual override {
        vm.label(address(relayerSource), "WormholeRelayerSource");
        vm.label(address(wormholeSource), "WormholeCoreSource");

        vm.label(address(relayerTarget), "WormholeRelayerTarget");
        vm.label(address(wormholeTarget), "WormholeCoreTarget");

        // Set up forks
        string memory sourceChainUrl = vm.envString("FUJI_RPC_URL");
        string memory targetChainUrl = vm.envString("MUMBAI_RPC_URL");

        // Set up Wormhole
        devnetPrivateKey = getNextPrivateKey();
        brnOwner = getNextPrivateKey();
        brnOwnerAddress = vm.addr(brnOwner);
        vm.label(brnOwnerAddress, "brnOwner");

        // Source Chain
        sourceFork = vm.createSelectFork(sourceChainUrl, sourceChainForkBlock);
        guardianSource = new SigningWormholeSimulator(
            wormholeSource,
            devnetPrivateKey
        );
        guardians[sourceChain] = guardianSource;
        vm.label(address(guardianSource), "SigningWormholeSimulatorSource");
        deliveryProviderSource = new BRNWormholeDeliveryProvider(
            wormholeSource,
            relayerSource,
            vm.addr(brnOwner)
        );
        vm.label(address(deliveryProviderSource), "BRNWormholeDeliveryProviderSource");
        receiverSource = new MockWormholeReceiver(
            wormholeSource,
            deliveryProviderSource,
            relayerSource,
            sourceChain

        );
        vm.label(address(receiverSource), "MockWormholeReceiverSource");

        // Destination Chain
        targetFork = vm.createSelectFork(targetChainUrl, targetChainForkBlock);
        if (tx.gasprice == 0) {
            fail("Gas Price is 0. Please set it to 1 gwei or more.");
        }

        // BRN Deployment on destination chain
        super.setUp();

        RelayerStateManager.RelayerState memory currentState = latestRelayerState;
        _registerAllNonFoundationRelayers();
        _moveForwardToNextEpoch();
        _sendEmptyTransaction(currentState);
        _moveForwardByWindowsInActiveFork(deployParams.relayerStateUpdateDelayInWindows);
        ta.initializeWormholeApplication(wormholeTarget, relayerTarget);

        // Wormhole simulator on destination chain
        deliveryProviderTarget = new BRNWormholeDeliveryProvider(
            wormholeTarget,
            relayerTarget,
            vm.addr(brnOwner)
        );
        vm.label(address(deliveryProviderTarget), "BRNWormholeDeliveryProviderTarget");
        guardianTarget = new SigningWormholeSimulator(
            wormholeTarget,
            devnetPrivateKey
        );
        guardians[targetChain] = guardianTarget;
        vm.label(address(guardianTarget), "SigningWormholeSimulatorTarget");
        receiverTarget = new MockWormholeReceiver(
            wormholeTarget,
            deliveryProviderTarget,
            relayerTarget,
            targetChain
        );
        vm.label(address(receiverTarget), "MockWormholeReceiverTarget");
    }

    function _configureWormholeEnvironment() internal {
        // Populate Test Data for Oracles on Source Chain
        vm.selectFork(sourceFork);
        vm.startPrank(brnOwnerAddress);
        deliveryProviderSource.setGasPrice(targetChain, targetChainGasPrice);
        deliveryProviderSource.setNativeCurrencyPrice(sourceChain, sourceChainNativeTokenPrice);
        deliveryProviderSource.setNativeCurrencyPrice(targetChain, targetChainNativeTokenPrice);
        deliveryProviderSource.setDeliverGasOverhead(targetChain, Gas.wrap(100_000));
        deliveryProviderSource.setMaximumBudget(targetChain, Wei.wrap(10_000_000 * 1 ether));
        deliveryProviderSource.setIsWormholeChainSupported(targetChain, true);
        deliveryProviderSource.setBrnRelayerProviderAddress(
            targetChain, toWormholeFormat(address(deliveryProviderTarget))
        );
        deliveryProviderSource.setBrnTransactionAllocatorAddress(targetChain, toWormholeFormat(address(ta)));
        deliveryProviderSource.setAssetConversionBuffer(
            targetChain, IBRNWormholeDeliveryProvider.AssetConversion({denominator: 100, buffer: 10})
        );
        receiverSource.setMockWormholeReceiverAddress(targetChain, address(receiverTarget));
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
        deliveryProviderTarget.setBrnRelayerProviderAddress(
            sourceChain, toWormholeFormat(address(deliveryProviderSource))
        );
        deliveryProviderTarget.setAssetConversionBuffer(
            sourceChain, IBRNWormholeDeliveryProvider.AssetConversion({denominator: 100, buffer: 10})
        );
        receiverTarget.setMockWormholeReceiverAddress(sourceChain, address(receiverSource));
        vm.stopPrank();
    }

    // For forked contracts traces are not visible in the console
    // This gives forge enough information to display the traces.
    // Great for debuggging
    function _overrideWormholeRelayerCode(IWormholeRelayer _relayer, IWormhole _wormhole) internal {
        // Deploy a copy of the WormholeRelayer contract with the new Wormhole address
        bytes memory args = abi.encode(_wormhole);
        bytes memory bytecode = abi.encodePacked(vm.getCode("WormholeRelayerMock.sol:WormholeRelayerMock"), args);
        require(bytecode.length > 0, "Invalid Bytecode");
        address deployed;
        assembly {
            deployed := create(0, add(bytecode, 0x20), mload(bytecode))
        }

        // Override the bytecode of the existing WormholeRelayer contract
        vm.etch(address(_relayer), deployed.code);
    }

    function _overrideMockWormholeReceiver(
        MockWormholeReceiver _receiver,
        IWormholeRelayer _relayer,
        IWormhole _wormhole,
        IBRNWormholeDeliveryProvider _deliveryProvider,
        WormholeChainId _chainId
    ) internal {
        // Deploy a copy of the WormholeRelayer contract with the new Wormhole address
        bytes memory args = abi.encode(_wormhole, _deliveryProvider, _relayer, _chainId);
        bytes memory bytecode = abi.encodePacked(vm.getCode("MockWormholeReceiver.sol:MockWormholeReceiver"), args);
        require(bytecode.length > 0, "Invalid Bytecode");
        address deployed;
        assembly {
            deployed := create(0, add(bytecode, 0x20), mload(bytecode))
        }

        // Override the bytecode of the existing WormholeRelayer contract
        vm.etch(address(_receiver), deployed.code);
    }

    function _signWormholeVM(IWormhole.VM memory _vm, WormholeChainId _emitterChain) internal returns (bytes memory) {
        _vm.emitterChainId = WormholeChainId.unwrap(_emitterChain);
        _vm.version = wormholeVMVersion;
        return guardians[_emitterChain].encodeAndSignMessage(_vm);
    }
}
