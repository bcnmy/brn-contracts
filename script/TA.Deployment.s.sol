// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import "forge-std/Script.sol";

import "ta/interfaces/ITransactionAllocator.sol";
import "ta-proxy/TAProxy.sol";
import "ta-delegation/TADelegation.sol";
import "ta-relayer-management/TARelayerManagement.sol";
import "ta-transaction-allocation/TATransactionAllocation.sol";
import "ta-wormhole-application/WormholeApplication.sol";
import "ta-common/TATypes.sol";

import "test/modules/debug/TADebug.sol";
import "mock/minimal-application/MinimalApplication.sol";
import "test/modules/ITransactionAllocatorDebug.sol";
import "test/modules/testnet-debug/TATestnetDebug.sol";
import "test/modules/testnet-debug/interfaces/ITATestnetDebug.sol";
import "src/mock/token/ERC20FreeMint.sol";

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
        for (uint256 i; i != supportedTokenAddresses.length;) {
            supportedTokens[i] = TokenAddress.wrap(supportedTokenAddresses[i]);
            unchecked {
                ++i;
            }
        }

        address[] memory foundationRelayerAccountAddresses_ =
            vm.parseJsonAddressArray(deploymentConfigStr, ".foundationRelayerAccountAddresses");
        RelayerAccountAddress[] memory foundationRelayerAccountAddresses =
            new RelayerAccountAddress[](foundationRelayerAccountAddresses_.length);
        for (uint256 i; i != foundationRelayerAccountAddresses_.length;) {
            foundationRelayerAccountAddresses[i] = RelayerAccountAddress.wrap(foundationRelayerAccountAddresses_[i]);
            unchecked {
                ++i;
            }
        }

        ITAProxy.InitializerParams memory params = ITAProxy.InitializerParams({
            blocksPerWindow: vm.parseJsonUint(deploymentConfigStr, ".blocksPerWindow"),
            epochLengthInSec: vm.parseJsonUint(deploymentConfigStr, ".epochLengthInSec"),
            relayersPerWindow: vm.parseJsonUint(deploymentConfigStr, ".relayersPerWindow"),
            jailTimeInSec: vm.parseJsonUint(deploymentConfigStr, ".jailTimeInSec"),
            withdrawDelayInSec: vm.parseJsonUint(deploymentConfigStr, ".withdrawDelayInSec"),
            absencePenaltyPercentage: vm.parseJsonUint(deploymentConfigStr, ".absencePenaltyPercentage"),
            minimumStakeAmount: vm.parseJsonUint(deploymentConfigStr, ".minimumStakeAmount"),
            minimumDelegationAmount: vm.parseJsonUint(deploymentConfigStr, ".minimumDelegationAmount"),
            baseRewardRatePerMinimumStakePerSec: vm.parseJsonUint(
                deploymentConfigStr, ".baseRewardRatePerMinimumStakePerSec"
                ),
            relayerStateUpdateDelayInWindows: vm.parseJsonUint(deploymentConfigStr, ".relayerStateUpdateDelayInWindows"),
            livenessZParameter: vm.parseJsonUint(deploymentConfigStr, ".livenessZParameter"),
            bondTokenAddress: TokenAddress.wrap(vm.parseJsonAddress(deploymentConfigStr, ".bondToken")),
            supportedTokens: supportedTokens,
            foundationRelayerAddress: RelayerAddress.wrap(
                vm.parseJsonAddress(deploymentConfigStr, ".foundationRelayerAddress")
                ),
            foundationRelayerAccountAddresses: foundationRelayerAccountAddresses,
            foundationRelayerStake: vm.parseJsonUint(deploymentConfigStr, ".foundationRelayerStake"),
            foundationRelayerEndpoint: vm.parseJsonString(deploymentConfigStr, ".foundationRelayerEndpoint"),
            foundationDelegatorPoolPremiumShare: vm.parseJsonUint(
                deploymentConfigStr, ".foundationDelegatorPoolPremiumShare"
                )
        });

        // Deploy
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        if (keccak256(abi.encode(vm.envString("DEPLOYMENT_MODE"))) == keccak256(abi.encode("MAINNET"))) {
            return deploy(deployerPrivateKey, params);
        } else if (keccak256(abi.encode(vm.envString("DEPLOYMENT_MODE"))) == keccak256(abi.encode("TESTNET_DEBUG"))) {
            return deployTestnet(deployerPrivateKey, params);
        }
        return ITransactionAllocator(address(0));
    }

    //TODO: Create2/Create3
    function _deploy(
        uint256 _deployerPrivateKey,
        ITAProxy.InitializerParams memory _params,
        address[] memory modules,
        bytes4[][] memory selectors
    ) internal returns (TAProxy) {
        address deployerAddr = vm.addr(_deployerPrivateKey);
        console2.log("Deploying Transaction Allocator contracts...");
        console2.log("Chain ID: ", block.chainid);
        console2.log("Deployer Address: ", deployerAddr);
        console2.log("Deployer Funds: ", deployerAddr.balance);

        vm.startBroadcast(_deployerPrivateKey);

        // Deploy Proxy
        TAProxy proxy = new TAProxy(modules, selectors, _params);
        console2.log("Proxy address: ", address(proxy));
        console2.log("Transaction Allocator contracts deployed successfully.");

        vm.stopBroadcast();

        return proxy;
    }

    function deploy(uint256 _deployerPrivateKey, ITAProxy.InitializerParams memory _params)
        public
        returns (ITransactionAllocator)
    {
        // Deploy Modules
        uint256 moduleCount = 3;
        address[] memory modules = new address[](moduleCount);
        bytes4[][] memory selectors = new bytes4[][](moduleCount);

        vm.startBroadcast(_deployerPrivateKey);

        modules[0] = address(new TADelegation());
        selectors[0] = _generateSelectors("TADelegation");

        modules[1] = address(new TARelayerManagement());
        selectors[1] = _generateSelectors("TARelayerManagement");

        modules[2] = address(new TATransactionAllocation());
        selectors[2] = _generateSelectors("TATransactionAllocation");

        vm.stopBroadcast();

        TAProxy proxy = _deploy(_deployerPrivateKey, _params, modules, selectors);

        return ITransactionAllocator(address(proxy));
    }

    function deployInternalTestSetup(uint256 _deployerPrivateKey, ITAProxy.InitializerParams memory _params)
        public
        returns (ITransactionAllocatorDebug)
    {
        // Deploy Modules
        uint256 moduleCount = 6;
        address[] memory modules = new address[](moduleCount);
        bytes4[][] memory selectors = new bytes4[][](moduleCount);

        vm.startBroadcast(_deployerPrivateKey);

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

        vm.stopBroadcast();
        TAProxy proxy = _deploy(_deployerPrivateKey, _params, modules, selectors);

        return ITransactionAllocatorDebug(address(proxy));
    }

    function deployTestnet(uint256 _deployerPrivateKey, ITAProxy.InitializerParams memory _params)
        public
        returns (ITransactionAllocatorDebug)
    {
        // Deploy Token
        _params.bondTokenAddress = _deployTestToken(_deployerPrivateKey);

        // Foundation Relayer Setup
        address deployer = vm.addr(_deployerPrivateKey);
        _foundationRelayerSetup(
            vm.envUint("FOUNDATION_RELAYER_PRIVATE_KEY"),
            _params,
            computeCreateAddress(deployer, vm.getNonce(deployer) + 5)
        );

        // Deploy Modules
        vm.startBroadcast(_deployerPrivateKey);

        uint256 moduleCount = 5;
        address[] memory modules = new address[](moduleCount);
        bytes4[][] memory selectors = new bytes4[][](moduleCount);

        modules[0] = address(new TADelegation());
        selectors[0] = _generateSelectors("TADelegation");

        modules[1] = address(new TARelayerManagement());
        selectors[1] = _generateSelectors("TARelayerManagement");

        modules[2] = address(new TATransactionAllocation());
        selectors[2] = _generateSelectors("TATransactionAllocation");

        modules[3] = address(new TATestnetDebug());
        selectors[3] = _generateSelectors("TATestnetDebug");

        modules[4] = address(new MinimalApplication());
        selectors[4] = _generateSelectors("MinimalApplication");

        vm.stopBroadcast();
        TAProxy proxy = _deploy(_deployerPrivateKey, _params, modules, selectors);

        return ITransactionAllocatorDebug(address(proxy));
    }

    function _deployTestToken(uint256 _deployerPrivateKey) internal returns (TokenAddress) {
        vm.startBroadcast(_deployerPrivateKey);
        ERC20FreeMint token = new ERC20FreeMint("Bond Token", "BOND");
        console2.log("Bond Token address: ", address(token));
        vm.stopBroadcast();
        return TokenAddress.wrap(address(token));
    }

    function _foundationRelayerSetup(
        uint256 _foundationRelayerPrivateKey,
        ITAProxy.InitializerParams memory _params,
        address _expectedTransactionAllocatorAddress
    ) internal {
        vm.startBroadcast(_foundationRelayerPrivateKey);
        ERC20FreeMint token = ERC20FreeMint(TokenAddress.unwrap(_params.bondTokenAddress));
        token.mint(vm.addr(_foundationRelayerPrivateKey), _params.minimumStakeAmount);
        token.approve(_expectedTransactionAllocatorAddress, _params.minimumStakeAmount);
        vm.stopBroadcast();
    }

    function _generateSelectors(string memory _contractName) internal returns (bytes4[] memory selectors) {
        string[] memory cmd = new string[](4);
        cmd[0] = "npx";
        cmd[1] = "ts-node";
        cmd[2] = "hardhat/scripts/generateSelectors.ts";
        cmd[3] = _contractName;
        bytes memory res = vm.ffi(cmd);
        selectors = abi.decode(res, (bytes4[]));
    }

    function test() external {}
}
