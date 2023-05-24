// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import "forge-std/Test.sol";
import "script/TA.Deployment.s.sol";

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
        ITAProxy.InitalizerParams memory params = ITAProxy.InitalizerParams({
            blocksPerWindow: 1,
            epochLengthInSec: 100,
            relayersPerWindow: 3,
            bondTokenAddress: TokenAddress.wrap(address(this)),
            supportedTokens: supportedTokens
        });

        ITransactionAllocator ta = script.deploy(privateKey, params, false);

        assertEq(ta.blocksPerWindow(), params.blocksPerWindow);
        assertEq(ta.relayersPerWindow(), params.relayersPerWindow);
        assertEq(ta.epochLengthInSec(), params.epochLengthInSec);
        assertEq(ta.bondTokenAddress() == params.bondTokenAddress, true);
        assertEq(ta.supportedPools()[0] == params.supportedTokens[0], true);
    }
}
