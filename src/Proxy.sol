// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8;

import "./library/ProxyStorage.sol";

contract Proxy {
    /// @dev Emitted when a module has been added
    event ModuleAdded(address indexed moduleAddr, bytes4[] selectors);

    constructor() {
        ///TODO: add logic to add modules. Should receive a list of implementations and a list of lists with selectors
    }

    /// @notice pass a call to a module
    /* solhint-disable no-complex-fallback, payable-fallback, no-inline-assembly */
    fallback() external payable {
        PStorage storage ds = ProxyStorage.getProxyStorage();
        address implementation = ds.implementations[msg.sig];
        assembly {
            calldatacopy(0, 0, calldatasize())
            let result := delegatecall(
                gas(),
                implementation,
                0,
                calldatasize(),
                0,
                0
            )
            returndatacopy(0, 0, returndatasize())
            switch result
            case 0 {
                revert(0, returndatasize())
            }
            default {
                return(0, returndatasize())
            }
        }
    }

    receive() external payable {}

    /* solhint-enable no-complex-fallback, payable-fallback, no-inline-assembly */

    /// @notice Adds a new module
    /// @dev function selector should not have been registered.
    /// @param implementation address of the implementation
    /// @param selectors selectors of the implementation contract
    function addModule(
        address implementation,
        bytes4[] calldata selectors
    ) internal {
        PStorage storage ds = ProxyStorage.getProxyStorage();
        for (uint256 i = 0; i < selectors.length; i++) {
            require(
                ds.implementations[selectors[i]] == address(0),
                "Selector already registered"
            );
            ds.implementations[selectors[i]] = implementation;
        }
        bytes32 hash = keccak256(abi.encode(selectors));
        ds.selectorsHash[implementation] = hash;
        emit ModuleAdded(implementation, selectors);
    }
}
