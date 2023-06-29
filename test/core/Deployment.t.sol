// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import "openzeppelin-contracts/token/ERC20/ERC20.sol";

import "forge-std/Test.sol";
import "script/TA.Deployment.s.sol";
import "src/library/FixedPointArithmetic.sol";
import "ta-common/TATypes.sol";
import "ta-proxy/interfaces/ITAProxy.sol";
import "ta/interfaces/ITransactionAllocator.sol";

import {IWormhole} from "wormhole-contracts/interfaces/IWormhole.sol";
import {IWormholeRelayer} from "wormhole-contracts/interfaces/relayer/IWormholeRelayerTyped.sol";

contract DeploymentTest is Test {
    using Uint256WrapperHelper for uint256;
    using FixedPointTypeHelper for FixedPointType;

    string constant mnemonic = "test test test test test test test test test test test junk";

    TADeploymentScript script;
    uint256 deployerPrivateKey;
    TokenAddress[] supportedTokens;
    uint256 foundationRelayerKey;
    RelayerAddress foundationRelayerAddress;
    RelayerAccountAddress[] foundationRelayerAccountAddresses;
    ERC20 bico;

    Module[] modules = [
        Module.TADelegation,
        Module.TARelayerManagement,
        Module.TATransactionAllocation,
        Module.TADebug,
        Module.MinimalApplication
    ];

    function setUp() external {
        script = new TADeploymentScript();
        deployerPrivateKey = vm.deriveKey(mnemonic, 0);

        // Foundation Relayer
        foundationRelayerKey = vm.deriveKey(mnemonic, 1);
        foundationRelayerAddress = RelayerAddress.wrap(vm.addr(foundationRelayerKey));
        foundationRelayerAccountAddresses.push(RelayerAccountAddress.wrap(vm.addr(vm.deriveKey(mnemonic, 2))));

        bico = new ERC20("Biconomy", "BICO");
        deal(address(bico), RelayerAddress.unwrap(foundationRelayerAddress), 10000 ether);

        // Approve stake to (to be deployed) TA Contract
        vm.broadcast(foundationRelayerKey);
        bico.approve(computeCreateAddress(vm.addr(deployerPrivateKey), 3), 10000 ether);
    }

    function testDeployment() external {
        supportedTokens.push(TokenAddress.wrap(address(this)));
        ITAProxy.InitializerParams memory params = ITAProxy.InitializerParams({
            blocksPerWindow: 1,
            epochLengthInSec: 100,
            relayersPerWindow: 3,
            jailTimeInSec: 100,
            withdrawDelayInSec: 50,
            absencePenaltyPercentage: 250,
            minimumStakeAmount: 10000 ether,
            stakeThresholdForJailing: 9000 ether,
            minimumDelegationAmount: 100000000000000000,
            baseRewardRatePerMinimumStakePerSec: 1003000000000,
            relayerStateUpdateDelayInWindows: 1,
            livenessZParameter: uint256(33).fp().div(10),
            bondTokenAddress: TokenAddress.wrap(address(bico)),
            supportedTokens: supportedTokens,
            foundationRelayerAddress: foundationRelayerAddress,
            foundationRelayerAccountAddresses: foundationRelayerAccountAddresses,
            foundationRelayerStake: 10000 ether,
            foundationRelayerEndpoint: "endpoint",
            foundationDelegatorPoolPremiumShare: 0
        });

        // ITransactionAllocator ta = script.deploy(deployerPrivateKey, params);

        TADeploymentScript.DeploymentResult memory result = script.deploy(
            params,
            modules,
            WormholeConfig({wormhole: IWormhole(address(0)), relayer: IWormholeRelayer(address(0))}),
            false,
            false,
            deployerPrivateKey,
            foundationRelayerKey
        );
        ITransactionAllocator ta = ITransactionAllocator(address(result.proxy));

        assertEq(ta.blocksPerWindow(), params.blocksPerWindow);
        assertEq(ta.epochLengthInSec(), params.epochLengthInSec);
        assertEq(ta.relayersPerWindow(), params.relayersPerWindow);
        assertEq(ta.jailTimeInSec(), params.jailTimeInSec);
        assertEq(ta.withdrawDelayInSec(), params.withdrawDelayInSec);
        assertEq(ta.absencePenaltyPercentage(), params.absencePenaltyPercentage);
        assertEq(ta.minimumStakeAmount(), params.minimumStakeAmount);
        assertEq(ta.minimumDelegationAmount(), params.minimumDelegationAmount);
        assertEq(ta.baseRewardRatePerMinimumStakePerSec(), params.baseRewardRatePerMinimumStakePerSec);
        assertEq(ta.relayerStateUpdateDelayInWindows(), params.relayerStateUpdateDelayInWindows);
        assertEq(ta.livenessZParameter() == params.livenessZParameter, true);
        assertEq(ta.bondTokenAddress() == params.bondTokenAddress, true);
        assertEq(ta.supportedPools()[0] == params.supportedTokens[0], true);
        for (uint256 i = 0; i < params.supportedTokens.length; i++) {
            assertEq(ta.isGasTokenSupported(params.supportedTokens[i]), true);
        }

        assertEq(ta.relayerInfo(foundationRelayerAddress).stake, params.foundationRelayerStake);
        assertEq(ta.relayerInfo(foundationRelayerAddress).endpoint, params.foundationRelayerEndpoint);
        assertEq(ta.relayerInfo(foundationRelayerAddress).status == RelayerStatus.Active, true);
        assertEq(ta.relayerInfo_isAccount(foundationRelayerAddress, foundationRelayerAccountAddresses[0]), true);
        assertEq(ta.relayerCount(), 1);
        assertEq(ta.totalStake(), params.foundationRelayerStake);
        assertEq(bico.balanceOf(address(ta)), params.foundationRelayerStake);
        assertEq(bico.balanceOf(address(RelayerAddress.unwrap(foundationRelayerAddress))), 0);
    }
}
