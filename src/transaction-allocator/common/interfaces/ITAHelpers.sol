// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import "../TATypes.sol";
import "src/library/FixedPointArithmetic.sol";

interface ITAHelpers {
    error NativeTransferFailed(address to, uint256 amount);
    error InvalidRelayer(RelayerAddress relayer);
    error ParameterLengthMismatch();
    error InvalidRelayerGenerationIteration();
    error RelayerIndexDoesNotPointToSelectedCdfInterval();
    error RelayerAddressDoesNotMatchSelectedRelayer();
    error InvalidLatestRelayerState();
    error InvalidActiveRelayerState();
    error OnlySelf();
    error NoSelfCall();

    event DelegatorRewardsAdded(RelayerAddress indexed _relayer, TokenAddress indexed _token, uint256 indexed _amount);
    event NewRelayerState(bytes32 indexed relayerStateHash, RelayerState relayerState);
}
