// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import "../TATypes.sol";

interface ITAHelpers {
    error InvalidStakeArrayHash();
    error InvalidCdfArrayHash();
    error InvalidDelegationArrayHash();
    error NativeTransferFailed(address to, uint256 amount);
    error InsufficientBalance(TokenAddress token, uint256 balance, uint256 amount);
    error InvalidRelayer(RelayerAddress relayer);
    error InvalidRelayerUpdationLogIndex();
    error ParameterLengthMismatch();

    event StakeArrayUpdated(bytes32 indexed stakePercArrayHash);
    event CdfArrayUpdateQueued(
        bytes32 indexed cdfArrayHash, uint256 indexed effectiveWindowIndex, uint256 indexed cdfLogIndex
    );
    event DelegationArrayUpdated(bytes32 indexed delegationArrayHash);
}
