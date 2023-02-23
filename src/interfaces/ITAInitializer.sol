// SPDX-License-Identifier: MIT

pragma solidity 0.8.17;

import "../structs/TAStructs.sol";

interface ITAInitializer {
    error AlreadyInitialized();

    event Initialized();

    function initialize(InitalizerParams calldata _params) external;
}
