// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import {IERC20} from "openzeppelin-contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "openzeppelin-contracts/token/ERC20/utils/SafeERC20.sol";

import {ITAProxy} from "./interfaces/ITAProxy.sol";
import {TAProxyStorage} from "./TAProxyStorage.sol";
import {TADelegationStorage} from "ta-delegation/TADelegationStorage.sol";
import {TARelayerManagementStorage} from "ta-relayer-management/TARelayerManagementStorage.sol";
import {TATransactionAllocationStorage} from "ta-transaction-allocation/TATransactionAllocationStorage.sol";
import {ITARelayerManagement} from "ta-relayer-management/interfaces/ITARelayerManagement.sol";

import {VersionManager} from "src/library/VersionManager.sol";
import {U16ArrayHelper} from "src/library/arrays/U16ArrayHelper.sol";
import {RAArrayHelper} from "src/library/arrays/RAArrayHelper.sol";

import {RelayerAddress, TokenAddress} from "ta-common/TATypes.sol";

/// @title TAProxy
/// @notice The proxy contract for the Transaction Allocator.
contract TAProxy is
    ITAProxy,
    TAProxyStorage,
    TADelegationStorage,
    TARelayerManagementStorage,
    TATransactionAllocationStorage
{
    using VersionManager for VersionManager.VersionManagerState;
    using U16ArrayHelper for uint16[];
    using RAArrayHelper for RelayerAddress[];
    using SafeERC20 for IERC20;

    constructor(address[] memory modules, bytes4[][] memory selectors, InitializerParams memory _params) {
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

    /// @dev Initialize the Transaction Allocator contract.
    /// @param _params The parameters used to initialize the Transaction Allocator contract.
    function _initialize(InitializerParams memory _params) internal {
        RMStorage storage rms = getRMStorage();
        TADStorage storage tds = getTADStorage();
        TAStorage storage tas = getTAStorage();

        // Config
        rms.blocksPerWindow = _params.blocksPerWindow;
        tas.epochLengthInSec = _params.epochLengthInSec;
        rms.relayersPerWindow = _params.relayersPerWindow;
        rms.jailTimeInSec = _params.jailTimeInSec;
        rms.withdrawDelayInSec = _params.withdrawDelayInSec;
        rms.absencePenaltyPercentage = _params.absencePenaltyPercentage;
        rms.minimumStakeAmount = _params.minimumStakeAmount;
        rms.baseRewardRatePerMinimumStakePerSec = _params.baseRewardRatePerMinimumStakePerSec;
        tds.minimumDelegationAmount = _params.minimumDelegationAmount;
        rms.relayerStateUpdateDelayInWindows = _params.relayerStateUpdateDelayInWindows;
        tas.livenessZParameter = _params.livenessZParameter;
        tas.stakeThresholdForJailing = _params.stakeThresholdForJailing;
        rms.bondToken = IERC20(TokenAddress.unwrap(_params.bondTokenAddress));
        tds.supportedPools = _params.supportedTokens;

        // Initial State
        tas.epochEndTimestamp = block.timestamp;
        rms.lastUnpaidRewardUpdatedTimestamp = block.timestamp;

        // Register Foundation Relayer
        address relayerManagementModule =
            getProxyStorage().implementations[ITARelayerManagement.registerFoundationRelayer.selector];
        (bool success,) = relayerManagementModule.delegatecall(
            abi.encodeCall(
                ITARelayerManagement.registerFoundationRelayer,
                (
                    _params.foundationRelayerAddress,
                    _params.foundationRelayerStake,
                    _params.foundationRelayerAccountAddresses,
                    _params.foundationRelayerEndpoint,
                    _params.foundationDelegatorPoolPremiumShare
                )
            )
        );
        require(success, "registerFoundationRelayer failed");
    }

    /// @dev Adds a new module
    ///      function selector should not have been registered.
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
