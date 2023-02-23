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

    function initialize(InitalizerParams calldata _params) external initializer {
        TAStorage storage ps = TAProxyStorage.getProxyStorage();

        ps.blocksWindow = _params.blocksPerWindow;
        ps.withdrawDelay = _params.withdrawDelay;
        ps.relayersPerWindow = _params.relayersPerWindow;
        ps.stakeArrayHash = keccak256(abi.encodePacked(new uint256[](0)));
        ps.MIN_PENATLY_BLOCK_NUMBER = block.number + _params.penaltyDelayBlocks;
    }
}
