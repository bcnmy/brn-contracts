// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import "forge-std/Script.sol";

import "src/transaction-allocator/TAProxy.sol";
import "src/transaction-allocator/modules/delegation/TADelegation.sol";
import "src/transaction-allocator/modules/relayer-management/TARelayerManagement.sol";
import "src/transaction-allocator/modules/transaction-allocation/TATransactionAllocation.sol";
import "src/transaction-allocator/interfaces/ITransactionAllocator.sol";
import "src/transaction-allocator/modules/application/wormhole/WormholeApplication.sol";

import "test/modules/debug/TADebug.sol";
import "test/modules/minimal-application/MinimalApplication.sol";
import "test/modules/ITransactionAllocatorDebug.sol";

import "src/transaction-allocator/common/TAStructs.sol";
import "src/transaction-allocator/common/TATypes.sol";

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

        address[] memory supportedTokenAddresses = vm.parseJsonAddressArray(deploymentConfigStr, ".supportedTokens");
        TokenAddress[] memory supportedTokens = new TokenAddress[](supportedTokenAddresses.length);
        for (uint256 i = 0; i < supportedTokenAddresses.length; i++) {
            supportedTokens[i] = TokenAddress.wrap(supportedTokenAddresses[i]);
        }

        InitalizerParams memory params = InitalizerParams({
            blocksPerWindow: vm.parseJsonUint(deploymentConfigStr, ".blocksPerWindow"),
            epochLengthInSec: vm.parseJsonUint(deploymentConfigStr, ".epochLengthInSec"),
            relayersPerWindow: vm.parseJsonUint(deploymentConfigStr, ".relayersPerWindow"),
            bondTokenAddress: TokenAddress.wrap(vm.parseJsonAddress(deploymentConfigStr, ".bondToken")),
            supportedTokens: supportedTokens
        });
        console2.log("Deployment Config: ");
        console2.log("  blocksPerWindow: ", params.blocksPerWindow);
        console2.log("  epochLengthInSec: ", params.epochLengthInSec);
        console2.log("  relayersPerWindow: ", params.relayersPerWindow);
        console2.log("  bondToken: ", TokenAddress.unwrap(params.bondTokenAddress));
        console2.log("  supportedTokens: ");
        for (uint256 i = 0; i < params.supportedTokens.length; i++) {
            console2.log("    ", TokenAddress.unwrap(params.supportedTokens[i]));
        }

        // Deploy
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        ITransactionAllocator proxy = deploy(deployerPrivateKey, params, true);
        return proxy;
    }

    //TODO: Create2/Create3
    function _deploy(
        uint256 _deployerPrivateKey,
        InitalizerParams memory _params,
        address[] memory modules,
        bytes4[][] memory selectors,
        bool _debug
    ) internal returns (TAProxy) {
        address deployerAddr = vm.addr(_deployerPrivateKey);
        if (_debug) {
            console2.log("Deploying Transaction Allocator contracts...");
            console2.log("Chain ID: ", block.chainid);
            console2.log("Deployer Address: ", deployerAddr);
            console2.log("Deployer Funds: ", deployerAddr.balance);
        }

        vm.startBroadcast(_deployerPrivateKey);

        // Deploy Proxy
        TAProxy proxy = new TAProxy(modules, selectors, _params);
        if (_debug) {
            console2.log("Proxy address: ", address(proxy));
            console2.log("Transaction Allocator contracts deployed successfully.");
        }

        vm.stopBroadcast();

        return proxy;
    }

    function deploy(uint256 _deployerPrivateKey, InitalizerParams memory _params, bool _debug)
        public
        returns (ITransactionAllocator)
    {
        // Deploy Modules
        uint256 moduleCount = 3;
        address[] memory modules = new address[](moduleCount);
        bytes4[][] memory selectors = new bytes4[][](moduleCount);

        modules[0] = address(new TADelegation());
        selectors[0] = _generateSelectors("TADelegation");

        modules[1] = address(new TARelayerManagement());
        selectors[1] = _generateSelectors("TARelayerManagement");

        modules[2] = address(new TATransactionAllocation());
        selectors[2] = _generateSelectors("TATransactionAllocation");

        TAProxy proxy = _deploy(_deployerPrivateKey, _params, modules, selectors, _debug);

        return ITransactionAllocator(address(proxy));
    }

    function deployTest(uint256 _deployerPrivateKey, InitalizerParams memory _params, bool _debug)
        public
        returns (ITransactionAllocatorDebug)
    {
        // Deploy Modules
        uint256 moduleCount = 6;
        address[] memory modules = new address[](moduleCount);
        bytes4[][] memory selectors = new bytes4[][](moduleCount);

        modules[0] = address(new TADelegation());
        selectors[0] = _generateSelectors("TADelegation");

        modules[1] = address(new TARelayerManagement());
        selectors[1] = _generateSelectors("TARelayerManagement");

        modules[2] = address(new TATransactionAllocation());
        selectors[2] = _generateSelectors("TATransactionAllocation");

        modules[3] = address(new TADebug());
        selectors[3] = _generateSelectors("TADebug");

        modules[4] = address(new MinimalApplication());
        selectors[4] = _generateSelectors("MinimalApplication");

        modules[5] = address(new WormholeApplication());
        selectors[5] = _generateSelectors("WormholeApplication");

        TAProxy proxy = _deploy(_deployerPrivateKey, _params, modules, selectors, _debug);

        return ITransactionAllocatorDebug(address(proxy));
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
