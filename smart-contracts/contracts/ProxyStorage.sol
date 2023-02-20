// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8;

contract ProxyStorage {
    bytes32 internal constant PROXY_STORAGE_SLOT = keccak256("Proxy.storage");

    struct PStorage {
        mapping(bytes4 => address) implementations;
        mapping(address => bytes32) selectorsHash;
    }

    /* solhint-disable no-inline-assembly */
    function getProxyStorage() internal pure returns (PStorage storage ms) {
        bytes32 slot = PROXY_STORAGE_SLOT;
        assembly {
            ms.slot := slot
        }
    }
    /* solhint-enable no-inline-assembly */
}
