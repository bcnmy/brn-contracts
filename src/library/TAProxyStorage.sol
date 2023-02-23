// SPDX-License-Identifier: MIT

pragma solidity 0.8.17;

import "../structs/TAStorage.sol";

library TAProxyStorage {
    bytes32 internal constant PROXY_STORAGE_SLOT = keccak256("Proxy.storage");

    /* solhint-disable no-inline-assembly */
    function getProxyStorage() internal pure returns (TAStorage storage ms) {
        bytes32 slot = PROXY_STORAGE_SLOT;
        assembly {
            ms.slot := slot
        }
    }
}
