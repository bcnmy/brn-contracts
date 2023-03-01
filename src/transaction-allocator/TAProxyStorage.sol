// SPDX-License-Identifier: MIT

pragma solidity 0.8.17;

abstract contract TAProxyStorage {
    bytes32 internal constant PROXY_STORAGE_SLOT = keccak256("Proxy.storage");

    struct TAPStorage {
        mapping(bytes4 => address) implementations;
        mapping(address => bytes32) selectorsHash;
    }

    /* solhint-disable no-inline-assembly */
    function getProxyStorage() internal pure returns (TAPStorage storage ms) {
        bytes32 slot = PROXY_STORAGE_SLOT;
        assembly {
            ms.slot := slot
        }
    }
}
