// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

interface ITATestnetDebug {
    function addModule(address implementation, bytes4[] memory selectors) external;
    function updateAtSlot(bytes32 slot, bytes32 value) external;
}
