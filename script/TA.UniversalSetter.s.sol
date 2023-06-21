// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import "forge-std/Script.sol";

import "test/modules/ITransactionAllocatorDebug.sol";
import "ta-relayer-management/TARelayerManagementStorage.sol";

contract TAUniversalSetter is Script, TARelayerManagementStorage {
    ITransactionAllocatorDebug taDebug = ITransactionAllocatorDebug(0xC5C04dEc932138935b6c1A31206e1FB63e2f5527);

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");

        bytes32 slot = bytes32(uint256(RELAYER_MANAGEMENT_STORAGE_SLOT) + 3);

        vm.startBroadcast(deployerPrivateKey);

        console2.log("blocksPerWindow before: ", taDebug.blocksPerWindow());

        taDebug.updateAtSlot(slot, bytes32(uint256(20)));

        console2.log("blocksPerWindow after: ", taDebug.blocksPerWindow());

        if (taDebug.blocksPerWindow() != 20) {
            revert("failed to update blocksPerWindow");
        }

        vm.stopBroadcast();
    }

    function test() external {}
}
