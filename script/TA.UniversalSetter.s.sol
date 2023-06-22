// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import "forge-std/Script.sol";

import "test/modules/ITransactionAllocatorDebug.sol";
import "ta-relayer-management/TARelayerManagementStorage.sol";

contract TAUniversalSetter is Script, TARelayerManagementStorage {
    ITransactionAllocatorDebug taDebug = ITransactionAllocatorDebug(0x8a4ac83708C95534cfdC3F00833FFdAB3e8ba997);

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");

        vm.startBroadcast(deployerPrivateKey);

        bytes32 slot = bytes32(uint256(RELAYER_MANAGEMENT_STORAGE_SLOT) + 3);
        console2.log("blocksPerWindow before: ", taDebug.blocksPerWindow());
        taDebug.updateAtSlot(slot, bytes32(uint256(20)));
        console2.log("blocksPerWindow after: ", taDebug.blocksPerWindow());
        if (taDebug.blocksPerWindow() != 20) {
            revert("failed to update blocksPerWindow");
        }

        console2.log("relayersPerWindowBefore", taDebug.relayersPerWindow());
        slot = bytes32(uint256(RELAYER_MANAGEMENT_STORAGE_SLOT) + 2);
        taDebug.updateAtSlot(slot, bytes32(uint256(2)));
        console2.log("relayersPerWindowAfter", taDebug.relayersPerWindow());
        if (taDebug.relayersPerWindow() != 2) {
            revert("failed to update relayersPerWindow");
        }

        vm.stopBroadcast();
    }

    function test() external {}
}
