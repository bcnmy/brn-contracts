// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import "./interfaces/ITATestnetDebug.sol";
import "ta-transaction-allocation/TATransactionAllocationStorage.sol";
import "ta-proxy/TAProxyStorage.sol";
import "ta-proxy/interfaces/ITAProxy.sol";

contract TATestnetDebug is ITATestnetDebug, TATransactionAllocationStorage, TAProxyStorage, ITAProxy {
    function addModule(address implementation, bytes4[] memory selectors) external override {
        TAPStorage storage ds = getProxyStorage();
        for (uint256 i = 0; i < selectors.length; i++) {
            if (ds.implementations[selectors[i]] != address(0)) {
                revert SelectorAlreadyRegistered(ds.implementations[selectors[i]], implementation, selectors[i]);
            }
            ds.implementations[selectors[i]] = implementation;
        }
        bytes32 hash = keccak256(abi.encode(selectors));
        ds.selectorsHash[implementation] = hash;
        emit ModuleAdded(implementation, selectors);
    }

    function updateAtSlot(bytes32 slot, bytes32 value) external override {
        assembly {
            sstore(slot, value)
        }
    }
}
