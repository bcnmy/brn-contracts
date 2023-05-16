// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import "../TATypes.sol";
import "src/library/FixedPointArithmetic.sol";

interface ITAHelpers {
    error InvalidStakeArrayHash();
    error InvalidCdfArrayHash();
    error InvalidRelayersArrayHash();
    error InvalidDelegationArrayHash();
    error NativeTransferFailed(address to, uint256 amount);
    error InsufficientBalance(TokenAddress token, uint256 balance, uint256 amount);
    error InvalidRelayer(RelayerAddress relayer);
    error InvalidRelayerUpdationLogIndex();
    error ParameterLengthMismatch();
    error InvalidRelayerGenerationIteration();
    error RelayerIndexDoesNotPointToSelectedCdfInterval();
    error RelayerAddressDoesNotMatchSelectedRelayer();

    event StakeArrayUpdated(bytes32 indexed stakeArrayHash);
    event RelayerProtocolRewardMinted(FixedPointType indexed sharesMinted);
    event RelayerProtocolRewardSharesBurnt(
        RelayerAddress indexed relayer,
        FixedPointType indexed sharesBurnt,
        uint256 indexed rewards,
        uint256 relayerRewards,
        uint256 delegatorRewards
    );
    event CdfArrayUpdateQueued(
        bytes32 indexed cdfArrayHash, uint256 indexed effectiveWindowIndex, uint256 indexed cdfLogIndex
    );
    event DelegationArrayUpdated(bytes32 indexed delegationArrayHash);
    event DelegatorRewardsAdded(RelayerAddress indexed _relayer, TokenAddress indexed _token, uint256 indexed _amount);
}
