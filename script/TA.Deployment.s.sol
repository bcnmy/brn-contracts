// SPDX-License-Identifier: MIT

pragma solidity 0.8.17;

import "forge-std/Script.sol";

import "src/transaction-allocator/Proxy.sol";
import "src/transaction-allocator/modules/TAAllocationHelper.sol";
import "src/transaction-allocator/modules/TAInitializer.sol";
import "src/transaction-allocator/modules/TARelayerManagement.sol";
import "src/transaction-allocator/modules/TATransactionExecution.sol";

import "src/interfaces/ITransactionAllocator.sol";

contract TADeploymentScript is Script {
    function run() external returns (Proxy proxy) {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");

        vm.startBroadcast(deployerPrivateKey);

        // Deploy Modules
        address[] memory moduleAddresses = new address[](4);
        bytes4[][] memory selectors = new bytes4[][](4);

        TAAllocationHelper taAllocationHelper = new TAAllocationHelper();
        moduleAddresses[0] = address(taAllocationHelper);
        selectors[0] = _generateSelectors("TAAllocationHelper");

        TAInitializer taInitializer = new TAInitializer();
        moduleAddresses[1] = address(taInitializer);
        selectors[1] = _generateSelectors("TAInitializer");

        TARelayerManagement taRelayerManagement = new TARelayerManagement();
        moduleAddresses[2] = address(taRelayerManagement);
        selectors[2] = _generateSelectors("TARelayerManagement");

        TATransactionExecution taTransactionExecution = new TATransactionExecution();
        moduleAddresses[3] = address(taTransactionExecution);
        selectors[3] = _generateSelectors("TATransactionExecution");

        // Deploy Proxy
        proxy = new Proxy(moduleAddresses, selectors);
        console2.log("Proxy address: ", address(proxy));

        vm.stopBroadcast();
    }

    function _generateSelectors(string memory _contractName) internal returns (bytes4[] memory selectors) {
        string[] memory cmd = new string[](4);
        cmd[0] = "npx";
        cmd[1] = "ts-node";
        cmd[2] = "hscript/generateSelectors.ts";
        cmd[3] = _contractName;
        bytes memory res = vm.ffi(cmd);
        selectors = abi.decode(res, (bytes4[]));
    }
}
