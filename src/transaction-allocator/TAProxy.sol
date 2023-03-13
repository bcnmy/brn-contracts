// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

import "./interfaces/ITAProxy.sol";
import "./TAProxyStorage.sol";
import "./modules/delegation/TADelegationStorage.sol";
import "./modules/relayer-management/TARelayerManagementStorage.sol";
import "./modules/transaction-allocation/TATransactionAllocationStorage.sol";
import "src/transaction-allocator/common/TAStructs.sol";
import "src/transaction-allocator/common/TATypes.sol";

contract TAProxy is
    ITAProxy,
    TAProxyStorage,
    TADelegationStorage,
    TARelayerManagementStorage,
    TATransactionAllocationStorage
{
    constructor(address[] memory modules, bytes4[][] memory selectors, InitalizerParams memory _params) {
        if (modules.length != selectors.length) {
            revert ParameterLengthMismatch();
        }

        uint256 length = modules.length;
        for (uint256 i = 0; i < length;) {
            _addModule(modules[i], selectors[i]);
            unchecked {
                ++i;
            }
        }

        _initialize(_params);
    }

    /// @notice pass a call to a module
    /* solhint-disable no-complex-fallback, payable-fallback, no-inline-assembly */
    fallback() external payable {
        TAPStorage storage ds = getProxyStorage();
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

    function _initialize(InitalizerParams memory _params) internal {
        RMStorage storage rms = getRMStorage();
        TADStorage storage tds = getTADStorage();

        // Config
        rms.blocksPerWindow = _params.blocksPerWindow;
        rms.relayersPerWindow = _params.relayersPerWindow;
        rms.penaltyDelayBlocks = block.number + _params.penaltyDelayBlocks;
        rms.bondToken = IERC20(TokenAddress.unwrap(_params.bondTokenAddress));

        // Initial State
        rms.stakeArrayHash = keccak256(abi.encodePacked(new uint32[](0)));
        tds.delegationArrayHash = keccak256(abi.encodePacked(new uint32[](0)));
    }

    /// @notice Adds a new module
    /// @dev function selector should not have been registered.
    /// @param implementation address of the implementation
    /// @param selectors selectors of the implementation contract
    function _addModule(address implementation, bytes4[] memory selectors) internal {
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
}
