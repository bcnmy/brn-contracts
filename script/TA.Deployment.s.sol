// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import {TAProxy} from "ta-proxy/TAProxy.sol";
import {TADelegation} from "ta-delegation/TADelegation.sol";
import {TARelayerManagement} from "ta-relayer-management/TARelayerManagement.sol";
import {TATransactionAllocation} from "ta-transaction-allocation/TATransactionAllocation.sol";
import {WormholeApplication} from "wormhole-application/WormholeApplication.sol";
import {TADebug} from "test/modules/debug/TADebug.sol";
import {MinimalApplication} from "mock/minimal-application/MinimalApplication.sol";
import {TATestnetDebug} from "test/modules/testnet-debug/TATestnetDebug.sol";
import {ERC20FreeMint} from "src/mock/token/ERC20FreeMint.sol";
import {TADeploymentConfig, Module, WormholeConfig} from "./TA.DeploymentConfig.sol";
import {TokenAddress, RelayerAddress} from "ta-common/TATypes.sol";

// TODO: create2/create3

contract TADeploymentScript is TADeploymentConfig {
    struct DeploymentResult {
        TAProxy proxy;
        address bondToken;
        TADelegation delegation;
        TARelayerManagement relayerManagement;
        TATransactionAllocation transactionAllocation;
        TADebug debug;
        TATestnetDebug testnetDebug;
        WormholeApplication wormholeApplication;
        MinimalApplication minimalApplication;
    }

    address[] public modules;
    bytes4[][] public selectors;
    DeploymentResult public result;

    function run() external returns (DeploymentResult memory) {
        TAProxy.InitializerParams storage params = deploymentConfig[block.chainid];
        Module[] storage modulesToDeploy = modulesToDeploy[block.chainid];

        return deploy(
            params,
            modulesToDeploy,
            wormholeConfig[block.chainid],
            shouldDeployBondToken[block.chainid],
            shouldConfigureWormhole[block.chainid],
            DEPLOYER_PRIVATE_KEY,
            FOUNDATION_RELAYER_PRIVATE_KEY
        );
    }

    function deploy(
        TAProxy.InitializerParams memory _params,
        Module[] memory _modulesToDeploy,
        WormholeConfig memory _wormholeConfig,
        bool _shouldDeployBondToken,
        bool _shouldConfigureWormhole,
        uint256 _deployerPrivateKey,
        uint256 _foundationRelayerPrivateKey
    ) public returns (DeploymentResult memory) {
        vm.startBroadcast(_deployerPrivateKey);

        // Deploy Bond Token if needed
        if (_shouldDeployBondToken) {
            result.bondToken = address(new ERC20FreeMint("Bond Token", "BOND"));
            _params.bondTokenAddress = TokenAddress.wrap(result.bondToken);
        } else {
            result.bondToken = TokenAddress.unwrap(_params.bondTokenAddress);
        }

        // Deploy Modules
        for (uint256 i = 0; i < _modulesToDeploy.length; i++) {
            _deployModule(_modulesToDeploy[i]);
        }

        vm.stopBroadcast();

        // Setup the Foundation Relayer
        vm.startBroadcast(_foundationRelayerPrivateKey);

        address expectedTAProxyAddr =
            computeCreateAddress(vm.addr(_deployerPrivateKey), vm.getNonce(vm.addr(_deployerPrivateKey)));

        {
            address foundationRelayerAddr = vm.addr(_foundationRelayerPrivateKey);

            ERC20FreeMint token = ERC20FreeMint(TokenAddress.unwrap(_params.bondTokenAddress));
            uint256 foundationRelayerBalance = token.balanceOf(foundationRelayerAddr);
            if (foundationRelayerBalance < _params.foundationRelayerStake) {
                token.mint(foundationRelayerAddr, _params.foundationRelayerStake - foundationRelayerBalance);
            }
            uint256 allowance = token.allowance(foundationRelayerAddr, expectedTAProxyAddr);
            if (allowance < _params.foundationRelayerStake) {
                token.approve(expectedTAProxyAddr, _params.foundationRelayerStake);
            }
        }

        vm.stopBroadcast();

        // Deploy TAProxy
        vm.startBroadcast(_deployerPrivateKey);

        TAProxy proxy = new TAProxy(modules, selectors, _params);
        result.proxy = proxy;
        if (address(proxy) != expectedTAProxyAddr) {
            revert("TAProxy address mismatch");
        }

        // Setup Wormhole Application if needed
        if (_shouldConfigureWormhole) {
            WormholeApplication(address(proxy)).initializeWormholeApplication(
                _wormholeConfig.wormhole, _wormholeConfig.relayer
            );
        }
        vm.stopBroadcast();

        return result;
    }

    function _deployModule(Module _moduleId) internal {
        address moduleAddr;
        bytes4[] memory moduleSelectors;

        if (_moduleId == Module.TADelegation) {
            moduleAddr = address(new TADelegation());
            moduleSelectors = _generateSelectors("TADelegation");
            result.delegation = TADelegation(moduleAddr);
        }
        if (_moduleId == Module.TARelayerManagement) {
            moduleAddr = address(new TARelayerManagement());
            moduleSelectors = _generateSelectors("TARelayerManagement");
            result.relayerManagement = TARelayerManagement(moduleAddr);
        }
        if (_moduleId == Module.TATransactionAllocation) {
            moduleAddr = address(new TATransactionAllocation());
            moduleSelectors = _generateSelectors("TATransactionAllocation");
            result.transactionAllocation = TATransactionAllocation(moduleAddr);
        }
        if (_moduleId == Module.TADebug) {
            moduleAddr = address(new TADebug());
            moduleSelectors = _generateSelectors("TADebug");
            result.debug = TADebug(moduleAddr);
        }
        if (_moduleId == Module.TATestnetDebug) {
            moduleAddr = address(new TATestnetDebug());
            moduleSelectors = _generateSelectors("TATestnetDebug");
            result.testnetDebug = TATestnetDebug(moduleAddr);
        }
        if (_moduleId == Module.WormholeApplication) {
            moduleAddr = address(new WormholeApplication());
            moduleSelectors = _generateSelectors("WormholeApplication");
            result.wormholeApplication = WormholeApplication(moduleAddr);
        }
        if (_moduleId == Module.MinimalApplication) {
            moduleAddr = address(new MinimalApplication());
            moduleSelectors = _generateSelectors("MinimalApplication");
            result.minimalApplication = MinimalApplication(moduleAddr);
        }

        modules.push(moduleAddr);
        selectors.push(moduleSelectors);
    }

    function _generateSelectors(string memory _contractName) internal returns (bytes4[] memory) {
        string[] memory cmd = new string[](4);
        cmd[0] = "npx";
        cmd[1] = "ts-node";
        cmd[2] = "hardhat/scripts/generateSelectors.ts";
        cmd[3] = _contractName;
        bytes memory res = vm.ffi(cmd);
        return abi.decode(res, (bytes4[]));
    }
}
