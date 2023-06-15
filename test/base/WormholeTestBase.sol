// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import "wormhole-contracts-test/relayer/WormholeSimulator.sol";

import {TATestBase} from "./TATestBase.sol";
import "ta-transaction-allocation/interfaces/ITATransactionAllocationEventsErrors.sol";
import "ta-relayer-management/interfaces/ITARelayerManagementEventsErrors.sol";
import "ta-common/interfaces/ITAHelpers.sol";
import "wormhole-application/BRNWormholeDeliveryProvider.sol";
import "src/mock/wormhole/MockWormholeReceiver.sol";

contract WormholeTestBase is
    TATestBase,
    ITATransactionAllocationEventsErrors,
    ITARelayerManagementEventsErrors,
    ITAHelpers,
    IMockWormholeReceiver
{
    string FUJI_URL;
    string MUMBAI_URL;

    WormholeChainId constant sourceChain = WormholeChainId.wrap(6); // fuji testnet
    WormholeChainId constant targetChain = WormholeChainId.wrap(5); // mumbai testnet

    uint256 constant sourceChainForkBlock = 23134119;
    uint256 constant targetChainForkBlock = 36895494;

    uint256 sourceFork;
    uint256 targetFork;

    uint256 devnetPrivateKey;
    uint256 brnOwner;

    // fuji testnet contracts
    IWormholeRelayer relayerSource = IWormholeRelayer(0xA3cF45939bD6260bcFe3D66bc73d60f19e49a8BB);
    IWormhole wormholeSource = IWormhole(0x7bbcE28e64B3F8b84d876Ab298393c38ad7aac4C);
    BRNWormholeDeliveryProvider deliveryProviderSource;
    SigningWormholeSimulator guardianSource;

    // mumbai testnet contracts
    IWormholeRelayer relayerTarget = IWormholeRelayer(0x0591C25ebd0580E0d4F27A82Fc2e24E7489CB5e0);
    IWormhole wormholeTarget = IWormhole(0x0CBE91CF822c73C2315FB05100C2F714765d5c20);
    SigningWormholeSimulator guardianTarget;
    MockWormholeReceiver receiverTarget;

    function setUp() public override {
        // Set up forks
        FUJI_URL = vm.envString("FUJI_RPC_URL");
        MUMBAI_URL = vm.envString("MUMBAI_RPC_URL");

        // Set up Wormhole
        devnetPrivateKey = getNextPrivateKey();
        brnOwner = getNextPrivateKey();

        // Source Chain
        sourceFork = vm.createSelectFork(FUJI_URL, sourceChainForkBlock);
        guardianSource = new SigningWormholeSimulator(
            wormholeSource,
            devnetPrivateKey
        );
        deliveryProviderSource = new BRNWormholeDeliveryProvider(
            wormholeSource,
            relayerSource,
            vm.addr(brnOwner)
        );

        // Destination Chain
        targetFork = vm.createSelectFork(MUMBAI_URL, targetChainForkBlock);
        if (tx.gasprice == 0) {
            fail("Gas Price is 0. Please set it to 1 gwei or more.");
        }

        // BRN Deployment on destination chain
        super.setUp();

        RelayerState memory currentState = latestRelayerState;
        _registerAllNonFoundationRelayers();
        _moveForwardToNextEpoch();
        _sendEmptyTransaction(currentState);
        _moveForwardByWindowsInActiveFork(deployParams.relayerStateUpdateDelayInWindows);

        // Wormhole simulator on destination chain
        guardianTarget = new SigningWormholeSimulator(
            wormholeTarget,
            devnetPrivateKey
        );
        receiverTarget = new MockWormholeReceiver();
    }
}
