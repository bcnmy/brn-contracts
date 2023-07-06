// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import {Script} from "forge-std/Script.sol";

import {IWormhole} from "wormhole-contracts/interfaces/IWormhole.sol";
import {IWormholeRelayer} from "wormhole-contracts/interfaces/relayer/IWormholeRelayerTyped.sol";

import {ITAProxy} from "ta-proxy/interfaces/ITAProxy.sol";
import {TokenAddress, RelayerAddress, RelayerAccountAddress} from "ta-common/TATypes.sol";
import {Uint256WrapperHelper} from "src/library/FixedPointArithmetic.sol";
import {NATIVE_TOKEN} from "ta-common/TAConstants.sol";

enum Module {
    TADelegation,
    TARelayerManagement,
    TATransactionAllocation,
    TADebug,
    TATestnetDebug,
    WormholeApplication,
    MinimalApplication
}

struct WormholeConfig {
    IWormhole wormhole;
    IWormholeRelayer relayer;
}

abstract contract TADeploymentConfig is Script {
    using Uint256WrapperHelper for uint256;

    uint256 public LOCAL_SIMULATION_CHAIN_ID;
    uint256 public TESTNET_FOUNDATION_RELAYER_PRIVATE_KEY;
    uint256 public ANVIL_DEFAULT_PRIVATE_KEY;
    uint256 public DEPLOYER_PRIVATE_KEY;
    RelayerAddress public FOUNDATION_RELAYER_ADDRESS;
    address public DEPLOYER_ADDRESS;
    address public ANVIL_DEFAULT_ADDRESS;

    mapping(uint256 chainId => ITAProxy.InitializerParams) deploymentConfig;
    mapping(uint256 chainId => WormholeConfig) wormholeConfig;
    mapping(uint256 chainId => Module[]) modulesToDeploy;
    mapping(uint256 chainId => bool) shouldDeployBondToken;
    mapping(uint256 chainId => bool) shouldConfigureWormhole;
    mapping(address => uint256) public addressToPrivateKey;

    function _setUpConfiguration() internal {
        LOCAL_SIMULATION_CHAIN_ID = vm.envUint("SIMULATION_CHAIN_ID");
        TESTNET_FOUNDATION_RELAYER_PRIVATE_KEY = vm.envUint("TESTNET_FOUNDATION_RELAYER_PRIVATE_KEY");
        ANVIL_DEFAULT_PRIVATE_KEY = vm.envUint("ANVIL_DEFAULT_PRIVATE_KEY");
        DEPLOYER_PRIVATE_KEY = vm.envUint("DEPLOYER_PRIVATE_KEY");
        FOUNDATION_RELAYER_ADDRESS = RelayerAddress.wrap(vm.addr(TESTNET_FOUNDATION_RELAYER_PRIVATE_KEY));
        DEPLOYER_ADDRESS = vm.addr(DEPLOYER_PRIVATE_KEY);
        ANVIL_DEFAULT_ADDRESS = vm.addr(ANVIL_DEFAULT_PRIVATE_KEY);

        ////////////// Local Simulation //////////////
        deploymentConfig[LOCAL_SIMULATION_CHAIN_ID] = ITAProxy.InitializerParams({
            delegationWithdrawDelayInSec: 100,
            blocksPerWindow: 2,
            epochLengthInSec: 4500,
            relayersPerWindow: 3,
            jailTimeInSec: 1000,
            withdrawDelayInSec: 50,
            absencePenaltyPercentage: 200,
            minimumStakeAmount: 10000 ether,
            stakeThresholdForJailing: 10000 ether,
            minimumDelegationAmount: 0.1 ether,
            baseRewardRatePerMinimumStakePerSec: 1003000000000,
            relayerStateUpdateDelayInWindows: 1,
            livenessZParameter: uint256(4).fp(),
            bondTokenAddress: TokenAddress.wrap(address(0)),
            supportedTokens: _toDyn([NATIVE_TOKEN]),
            foundationRelayerAddress: RelayerAddress.wrap(ANVIL_DEFAULT_ADDRESS),
            foundationRelayerAccountAddresses: _toDyn([RelayerAccountAddress.wrap(ANVIL_DEFAULT_ADDRESS)]),
            foundationRelayerStake: 10000 ether,
            foundationRelayerEndpoint: "https://api.abc.com",
            foundationDelegatorPoolPremiumShare: 0
        });
        modulesToDeploy[LOCAL_SIMULATION_CHAIN_ID] = [
            Module.TADelegation,
            Module.TARelayerManagement,
            Module.TATransactionAllocation,
            Module.TATestnetDebug,
            Module.MinimalApplication
        ];
        shouldDeployBondToken[LOCAL_SIMULATION_CHAIN_ID] = true;

        ////////////// Fuji //////////////
        deploymentConfig[43113] = ITAProxy.InitializerParams({
            delegationWithdrawDelayInSec: 100,
            blocksPerWindow: 20,
            epochLengthInSec: 4500,
            relayersPerWindow: 3,
            jailTimeInSec: 100,
            withdrawDelayInSec: 50,
            absencePenaltyPercentage: 200,
            minimumStakeAmount: 10000 ether,
            stakeThresholdForJailing: 10000 ether,
            minimumDelegationAmount: 0.1 ether,
            baseRewardRatePerMinimumStakePerSec: 1003000000000,
            relayerStateUpdateDelayInWindows: 1,
            livenessZParameter: uint256(4).fp(),
            bondTokenAddress: TokenAddress.wrap(0xF9C3e58C6ca8DF57F5BC94c7ecCCABFaE3845068),
            supportedTokens: _toDyn([NATIVE_TOKEN, TokenAddress.wrap(0xF9C3e58C6ca8DF57F5BC94c7ecCCABFaE3845068)]),
            foundationRelayerAddress: FOUNDATION_RELAYER_ADDRESS,
            foundationRelayerAccountAddresses: _toDyn(
                [RelayerAccountAddress.wrap(RelayerAddress.unwrap(FOUNDATION_RELAYER_ADDRESS))]
                ),
            foundationRelayerStake: 10000 ether,
            foundationRelayerEndpoint: "https://api.abc.com",
            foundationDelegatorPoolPremiumShare: 0
        });
        modulesToDeploy[43113] = [
            Module.TADelegation,
            Module.TARelayerManagement,
            Module.TATransactionAllocation,
            Module.TATestnetDebug,
            Module.WormholeApplication
        ];
        wormholeConfig[43113] = WormholeConfig({
            wormhole: IWormhole(0x7bbcE28e64B3F8b84d876Ab298393c38ad7aac4C),
            relayer: IWormholeRelayer(0xA3cF45939bD6260bcFe3D66bc73d60f19e49a8BB)
        });
        shouldConfigureWormhole[43113] = true;

        vm.label(RelayerAddress.unwrap(FOUNDATION_RELAYER_ADDRESS), "foundationRelayer");
        vm.label(DEPLOYER_ADDRESS, "deployer");

        addressToPrivateKey[RelayerAddress.unwrap(FOUNDATION_RELAYER_ADDRESS)] = TESTNET_FOUNDATION_RELAYER_PRIVATE_KEY;
        addressToPrivateKey[ANVIL_DEFAULT_ADDRESS] = ANVIL_DEFAULT_PRIVATE_KEY;
    }

    function _toDyn(TokenAddress[1] memory _arr) private pure returns (TokenAddress[] memory arr) {
        arr = new TokenAddress[](_arr.length);
        for (uint256 i = 0; i < _arr.length; i++) {
            arr[i] = _arr[i];
        }
    }

    function _toDyn(TokenAddress[2] memory _arr) private pure returns (TokenAddress[] memory arr) {
        arr = new TokenAddress[](_arr.length);
        for (uint256 i = 0; i < _arr.length; i++) {
            arr[i] = _arr[i];
        }
    }

    function _toDyn(RelayerAccountAddress[1] memory _arr) private pure returns (RelayerAccountAddress[] memory arr) {
        arr = new RelayerAccountAddress[](_arr.length);
        for (uint256 i = 0; i < _arr.length; i++) {
            arr[i] = _arr[i];
        }
    }
}
