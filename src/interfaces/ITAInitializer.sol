// SPDX-License-Identifier: MIT

pragma solidity 0.8.17;

interface ITAInitializer {
    error AlreadyInitialized();

    event Initialized();

    function initialize(
        uint256 blocksPerNode_,
        uint256 withdrawDelay_,
        uint256 relayersPerWindow_,
        uint256 penaltyDelayBlocks_
    ) external;
}
