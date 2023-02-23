// SPDX-License-Identifier: MIT

pragma solidity 0.8.17;

import "../library/TAProxyStorage.sol";
import "../interfaces/IProxy.sol";

contract Proxy is IProxy {
    constructor(address[] memory modules, bytes4[][] memory selectors) {
        if (modules.length != selectors.length) {
            revert ParameterLengthMismatch();
        }

        uint256 length = modules.length;
        for (uint256 i = 0; i < length;) {
            addModule(modules[i], selectors[i]);
            unchecked {
                ++i;
            }
        }
    }

    /// @notice pass a call to a module
    /* solhint-disable no-complex-fallback, payable-fallback, no-inline-assembly */
    fallback() external payable {
        TAStorage storage ds = TAProxyStorage.getProxyStorage();
        address implementation = ds.implementations[msg.sig];
        assembly {
            calldatacopy(0, 0, calldatasize())
            let result := delegatecall(gas(), implementation, 0, calldatasize(), 0, 0)
            returndatacopy(0, 0, returndatasize())
            switch result
            case 0 { revert(0, returndatasize()) }
            default { return(0, returndatasize()) }
        }
    }

    receive() external payable {}

    /* solhint-enable no-complex-fallback, payable-fallback, no-inline-assembly */

    /// @notice Adds a new module
    /// @dev function selector should not have been registered.
    /// @param implementation address of the implementation
    /// @param selectors selectors of the implementation contract
    function addModule(address implementation, bytes4[] memory selectors) internal {
        TAStorage storage ds = TAProxyStorage.getProxyStorage();
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
}
