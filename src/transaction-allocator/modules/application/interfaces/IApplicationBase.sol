// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

/// @title IApplicationBase
/// @dev Interface for the ApplicationBase contract, which can be inherted by all applications wishing to use BRN's services.
interface IApplicationBase {
    error ExternalCallsNotAllowed();
    error RelayerNotAssignedToTransaction();
}
