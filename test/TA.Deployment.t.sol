// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import "forge-std/Test.sol";
import "../script/TA.Deployment.s.sol";

contract TADeploymentTest is Test {
    TADeploymentScript script;
    uint256 privateKey;
    string constant mnemonic = "test test test test test test test test test test test junk";
    TokenAddress[] supportedTokens;

    function setUp() external {
        script = new TADeploymentScript();
        privateKey = vm.deriveKey(mnemonic, 0);
    }

    function testDeployment() external {
        supportedTokens.push(TokenAddress.wrap(address(this)));
        InitalizerParams memory params = InitalizerParams({
            blocksPerWindow: 1,
            blocksPerEpoch: 2,
            relayersPerWindow: 3,
            penaltyDelayBlocks: 4,
            bondTokenAddress: TokenAddress.wrap(address(this)),
            supportedTokens: supportedTokens
        });

        ITransactionAllocator ta = script.deploy(privateKey, params, false);

        assertEq(ta.blocksPerWindow(), params.blocksPerWindow);
        assertEq(ta.blocksPerEpoch(), params.blocksPerEpoch);
        assertEq(ta.relayersPerWindow(), params.relayersPerWindow);
        assertEq(ta.penaltyDelayBlocks(), block.number + params.penaltyDelayBlocks);
        assertEq(ta.bondTokenAddress() == params.bondTokenAddress, true);
        assertEq(ta.supportedPools()[0] == params.supportedTokens[0], true);
    }
}
