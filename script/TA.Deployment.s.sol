// SPDX-License-Identifier: MIT

pragma solidity 0.8.17;

import "forge-std/Script.sol";

import "src/transaction-allocator/Proxy.sol";
import "src/transaction-allocator/modules/TAAllocationHelper.sol";
import "src/transaction-allocator/modules/TAInitializer.sol";
import "src/transaction-allocator/modules/TARelayerManagement.sol";
import "src/transaction-allocator/modules/TATransactionExecution.sol";

import "src/interfaces/ITransactionAllocator.sol";

import "src/structs/TAStructs.sol";

contract TADeploymentScript is Script {
    error EmptyDeploymentConfigPath();

    function run() external returns (ITransactionAllocator) {
        // Load Deployment Config
        string memory deployConfigPath = vm.envString("TRANSACTION_ALLOCATOR_DEPLOYMENT_CONFIG_JSON");
        if (keccak256(abi.encode(deployConfigPath)) == keccak256(abi.encode(""))) {
            revert EmptyDeploymentConfigPath();
        }
        string memory deploymentConfigStr = vm.readFile(deployConfigPath);
        console2.log("Deployment Config Path: ", deployConfigPath);
        InitalizerParams memory params = InitalizerParams({
            blocksPerWindow: vm.parseJsonUint(deploymentConfigStr, ".blocksPerWindow"),
            withdrawDelay: vm.parseJsonUint(deploymentConfigStr, ".withdrawDelay"),
            relayersPerWindow: vm.parseJsonUint(deploymentConfigStr, ".relayersPerWindow"),
            penaltyDelayBlocks: vm.parseJsonUint(deploymentConfigStr, ".penaltyDelayBlocks")
        });
        console2.log("Deployment Config: ");
        console2.log("  blocksPerWindow: ", params.blocksPerWindow);
        console2.log("  withdrawDelay: ", params.withdrawDelay);
        console2.log("  relayersPerWindow: ", params.relayersPerWindow);
        console2.log("  penaltyDelayBlocks: ", params.penaltyDelayBlocks);

        // Deploy
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        ITransactionAllocator proxy = deploy(deployerPrivateKey, true);
        configure(deployerPrivateKey, true, proxy, params);
        return proxy;
    }

    function deploy(uint256 _deployerPrivateKey, bool _debug) public returns (ITransactionAllocator) {
        address deployerAddr = vm.addr(_deployerPrivateKey);
        if (_debug) {
            console2.log("Deploying Transaction Allocator contracts...");
            console2.log("Chain ID: ", block.chainid);
            console2.log("Deployer Address: ", deployerAddr);
            console2.log("Deployer Funds:", deployerAddr.balance);
        }

        vm.startBroadcast(_deployerPrivateKey);

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
        Proxy proxy = new Proxy(moduleAddresses, selectors);
        if (_debug) {
            console2.log("Proxy address: ", address(proxy));
            console2.log("Transaction Allocator contracts deployed successfully.");
        }

        vm.stopBroadcast();

        return ITransactionAllocator(address(proxy));
    }

    function configure(
        uint256 _configurePrivateKey,
        bool _debug,
        ITransactionAllocator _proxy,
        InitalizerParams memory _params
    ) public {
        address configureAddr = vm.addr(_configurePrivateKey);
        if (_debug) {
            console2.log("Configuring Transaction Allocator...");
            console2.log("Chain ID: ", block.chainid);
            console2.log("Configure Address: ", configureAddr);
            console2.log("Configure Funds:", configureAddr.balance);
        }

        vm.broadcast(_configurePrivateKey);
        _proxy.initialize(_params);

        if (_debug) {
            console2.log("Transaction Allocator configured successfully.");
        }
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
