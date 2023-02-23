// SPDX-License-Identifier: MIT

pragma solidity 0.8.17;

import "../../library/TAProxyStorage.sol";
import "../../interfaces/ITAInitializer.sol";

contract TAInitializer is ITAInitializer {
    modifier initializer() {
        TAStorage storage ps = TAProxyStorage.getProxyStorage();

        if (!ps.initialized) {
            ps.initialized = true;
            emit Initialized();
        } else {
            revert AlreadyInitialized();
        }
        _;
    }

    function initialize(
        uint256 blocksPerNode_,
        uint256 withdrawDelay_,
        uint256 relayersPerWindow_,
        uint256 penaltyDelayBlocks_
    ) external initializer {
        TAStorage storage ps = TAProxyStorage.getProxyStorage();

        ps.blocksWindow = blocksPerNode_;
        ps.withdrawDelay = withdrawDelay_;
        ps.relayersPerWindow = relayersPerWindow_;
        ps.stakeArrayHash = keccak256(abi.encodePacked(new uint256[](0)));
        ps.MIN_PENATLY_BLOCK_NUMBER = block.number + penaltyDelayBlocks_;
    }
}
