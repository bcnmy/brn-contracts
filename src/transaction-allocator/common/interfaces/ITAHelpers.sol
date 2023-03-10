// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import "../TATypes.sol";

interface ITAHelpers {
    error InvalidStakeArrayHash();
    error InvalidCdfArrayHash();
    error InvalidDelegationArrayHash();
    error NativeTransferFailed(address to, uint256 amount);
    error InsufficientBalance(TokenAddress token, uint256 balance, uint256 amount);
    error InvalidRelayer(RelayerId relayer);
    error NotAuthorized(RelayerAddress relayerAddress, address caller);
    error ParameterLengthMismatch();

    event StakeArrayUpdated(bytes32 indexed stakePercArrayHash);
    event CdfArrayUpdated(bytes32 indexed cdfArrayHash);
    event DelegationArrayUpdated(bytes32 indexed delegationArrayHash);
}
