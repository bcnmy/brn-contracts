// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import "forge-std/Script.sol";
import "src/mock/token/ERC20FreeMint.sol";

contract TestTokenDeploymentScript is Script {
    error EmptyDeploymentConfigPath();

    address[] mintAddresses;
    uint256[] mintAmounts;

    function run() external returns (ERC20FreeMint) {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);
        ERC20FreeMint token = new ERC20FreeMint("Bond Token", "BOND");
        if (mintAddresses.length > 0) {
            token.batchMint(mintAddresses, mintAmounts);
        }
        console2.log("Bond Token address: ", address(token));
        vm.stopBroadcast();

        return token;
    }
}
