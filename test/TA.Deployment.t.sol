// SPDX-License-Identifier: MIT

pragma solidity 0.8.17;

import "forge-std/Test.sol";
import "../script/TA.Deployment.s.sol";

contract TADeploymentTest is Test {
    TADeploymentScript script;
    uint256 privateKey;
    string constant mnemonic = "test test test test test test test test test test test junk";

    function setUp() external {
        script = new TADeploymentScript();
        privateKey = vm.deriveKey(mnemonic, 0);
    }

    function testDeployment() external {
        InitalizerParams memory params =
            InitalizerParams({blocksPerWindow: 1, withdrawDelay: 2, relayersPerWindow: 3, penaltyDelayBlocks: 4});

        ITransactionAllocator ta = script.deploy(privateKey, params, false);

        assertEq(ta.blocksPerWindow(), params.blocksPerWindow);
        assertEq(ta.withdrawDelay(), params.withdrawDelay);
        assertEq(ta.relayersPerWindow(), params.relayersPerWindow);
        assertEq(ta.penaltyDelayBlocks(), block.number + params.penaltyDelayBlocks);
    }
}
