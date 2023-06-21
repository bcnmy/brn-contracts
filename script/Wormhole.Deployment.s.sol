// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import "forge-std/Script.sol";

import "ta/interfaces/ITransactionAllocator.sol";
import "wormhole-application/BRNWormholeDeliveryProvider.sol";
import "src/mock/wormhole/MockWormholeReceiver.sol";
import "src/library/AddressUtils.sol";

// TODO: Add code to verify deployment
contract WormholeDeployer is Script {
    using AddressUtils for address;

    struct ChainConfig {
        uint256 fork;
        WormholeChainId chainId;
        IWormhole wormholeCore;
        IWormholeRelayer wormholeRelayer;
        GasPrice gasPrice;
        WeiPrice nativeCurrencyPrice;
        Gas deliveryGasOverhead;
        Wei maximumBudget;
        ITransactionAllocator transactionAllocator;
        IBRNWormholeDeliveryProvider.AssetConversion assetConversionBuffer;
    }

    mapping(uint256 chainId => ChainConfig) deploymentConfig;
    mapping(uint256 chainId => BRNWormholeDeliveryProvider) deliveryProviders;
    mapping(uint256 chainId => MockWormholeReceiver) receivers;
    uint256[] chainIds;

    uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");

    constructor() {
        // Mumbai
        deploymentConfig[80001] = ChainConfig({
            fork: vm.createFork(vm.envString("MUMBAI_RPC_URL")),
            chainId: WormholeChainId.wrap(5),
            wormholeCore: IWormhole(0x0CBE91CF822c73C2315FB05100C2F714765d5c20),
            wormholeRelayer: IWormholeRelayer(0x0591C25ebd0580E0d4F27A82Fc2e24E7489CB5e0),
            gasPrice: GasPrice.wrap(16 gwei),
            nativeCurrencyPrice: WeiPrice.wrap(0.59 ether),
            deliveryGasOverhead: Gas.wrap(100000),
            maximumBudget: Wei.wrap(10 ether),
            transactionAllocator: ITransactionAllocator(address(0)),
            assetConversionBuffer: IBRNWormholeDeliveryProvider.AssetConversion({denominator: 100, buffer: 10})
        });
        chainIds.push(80001);

        // Fuji
        deploymentConfig[43113] = ChainConfig({
            fork: vm.createFork(vm.envString("FUJI_RPC_URL")),
            chainId: WormholeChainId.wrap(6),
            wormholeCore: IWormhole(0x7bbcE28e64B3F8b84d876Ab298393c38ad7aac4C),
            wormholeRelayer: IWormholeRelayer(0xA3cF45939bD6260bcFe3D66bc73d60f19e49a8BB),
            gasPrice: GasPrice.wrap(16 gwei),
            nativeCurrencyPrice: WeiPrice.wrap(11.5 ether),
            deliveryGasOverhead: Gas.wrap(100000),
            maximumBudget: Wei.wrap(10 ether),
            transactionAllocator: ITransactionAllocator(0xC5C04dEc932138935b6c1A31206e1FB63e2f5527),
            assetConversionBuffer: IBRNWormholeDeliveryProvider.AssetConversion({denominator: 100, buffer: 10})
        });
        chainIds.push(43113);
    }

    function run() external {
        for (uint256 i = 0; i < chainIds.length; ++i) {
            _deploy(chainIds[i]);
        }

        for (uint256 i = 0; i < chainIds.length; ++i) {
            _configure(chainIds[i]);
        }
    }

    function _deploy(uint256 _chainId) internal {
        console2.log("Deploying on chain %s", _chainId);

        ChainConfig memory config = deploymentConfig[_chainId];

        vm.selectFork(config.fork);
        vm.startBroadcast(deployerPrivateKey);

        deliveryProviders[_chainId] =
            new BRNWormholeDeliveryProvider(config.wormholeCore, config.wormholeRelayer, vm.addr(deployerPrivateKey));
        receivers[_chainId] =
        new MockWormholeReceiver(config.wormholeCore, deliveryProviders[_chainId], config.wormholeRelayer,config.chainId);

        console2.log("deliveryProvider on chain %s: %s", _chainId, address(deliveryProviders[_chainId]));
        console2.log("receiver on chain %s: %s", _chainId, address(receivers[_chainId]));

        vm.stopBroadcast();
    }

    function _configure(uint256 _chainId) internal {
        ChainConfig memory config = deploymentConfig[_chainId];

        console2.log("Configuring on chain %s", _chainId);
        BRNWormholeDeliveryProvider deliveryProvider = deliveryProviders[_chainId];
        MockWormholeReceiver receiver = receivers[_chainId];

        vm.selectFork(config.fork);

        vm.startBroadcast(deployerPrivateKey);
        deliveryProvider.setNativeCurrencyPrice(config.chainId, config.nativeCurrencyPrice);

        for (uint256 i = 0; i < chainIds.length; ++i) {
            if (chainIds[i] == _chainId) {
                continue;
            }

            console2.log("Configuring on chain %s", _chainId, " for", chainIds[i]);

            ChainConfig memory targetConfig = deploymentConfig[chainIds[i]];

            deliveryProvider.setGasPrice(targetConfig.chainId, targetConfig.gasPrice);
            deliveryProvider.setNativeCurrencyPrice(targetConfig.chainId, targetConfig.nativeCurrencyPrice);
            deliveryProvider.setDeliverGasOverhead(targetConfig.chainId, targetConfig.deliveryGasOverhead);
            deliveryProvider.setMaximumBudget(targetConfig.chainId, targetConfig.maximumBudget);
            deliveryProvider.setIsWormholeChainSupported(targetConfig.chainId, true);
            deliveryProvider.setBrnTransactionAllocatorAddress(
                targetConfig.chainId, address(targetConfig.transactionAllocator).toBytes32()
            );
            deliveryProvider.setAssetConversionBuffer(targetConfig.chainId, targetConfig.assetConversionBuffer);
            deliveryProvider.setBrnRelayerProviderAddress(
                targetConfig.chainId, address(deliveryProviders[chainIds[i]]).toBytes32()
            );

            receiver.setMockWormholeReceiverAddress(targetConfig.chainId, address(receivers[chainIds[i]]));
        }

        vm.stopBroadcast();
    }
}
