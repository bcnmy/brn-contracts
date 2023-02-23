// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8;

import "../structs/ProxyStorageStructs.sol";

library ProxyStorage {
    bytes32 internal constant PROXY_STORAGE_SLOT = keccak256("Proxy.storage");

    /* solhint-disable no-inline-assembly */
    function getProxyStorage() internal pure returns (PStorage storage ms) {
        bytes32 slot = PROXY_STORAGE_SLOT;
        assembly {
            ms.slot := slot
        }
    }
}
