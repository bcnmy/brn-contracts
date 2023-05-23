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
import "src/library/VersionManager.sol";

contract TAProxy is
    ITAProxy,
    TAProxyStorage,
    TADelegationStorage,
    TARelayerManagementStorage,
    TATransactionAllocationStorage
{
    using VersionManager for VersionManager.VersionManagerState;

    constructor(address[] memory modules, bytes4[][] memory selectors, InitalizerParams memory _params) {
        if (modules.length != selectors.length) {
            revert ParameterLengthMismatch();
        }

        uint256 length = modules.length;
        for (uint256 i; i != length;) {
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

    // TODO: Move to custom calldata?
    function _initialize(InitalizerParams memory _params) internal {
        RMStorage storage rms = getRMStorage();
        TADStorage storage tds = getTADStorage();
        TAStorage storage tas = getTAStorage();

        // Config
        rms.blocksPerWindow = _params.blocksPerWindow;
        rms.relayersPerWindow = _params.relayersPerWindow;
        rms.bondToken = IERC20(TokenAddress.unwrap(_params.bondTokenAddress));
        tds.supportedPools = _params.supportedTokens;
        tas.epochLengthInSec = _params.epochLengthInSec;
        tas.epochEndTimestamp = block.timestamp + _params.epochLengthInSec;

        uint256 length = _params.supportedTokens.length;
        for (uint256 i; i != length;) {
            rms.isGasTokenSupported[_params.supportedTokens[i]] = true;
            unchecked {
                ++i;
            }
        }

        // Initial State
        rms.latestActiveRelayerStakeArrayHash = keccak256(abi.encodePacked(new uint32[](0)));
        tds.delegationArrayHash = keccak256(abi.encodePacked(new uint32[](0)));
        rms.cdfVersionManager.initialize(keccak256(abi.encodePacked(new uint32[](0))));
        rms.activeRelayerListVersionManager.initialize(keccak256(abi.encodePacked(new RelayerAddress[](0))));
        rms.lastUnpaidRewardUpdatedTimestamp = block.timestamp;
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
