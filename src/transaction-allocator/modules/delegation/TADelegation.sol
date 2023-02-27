// SPDX-License-Identifier: MIT

pragma solidity 0.8.17;

import "./TADelegationStorage.sol";
import "./ITADelegation.sol";

contract TADelegation is TADelegationStorage, ITADelegation {
    function helloWorld() external pure returns (string memory s) {
        s = "Hello World";
    }
}
