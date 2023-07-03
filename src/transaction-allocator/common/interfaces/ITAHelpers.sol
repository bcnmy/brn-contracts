// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import {RelayerAddress, TokenAddress, RelayerState} from "../TATypes.sol";

interface ITAHelpers {
    error RelayerIsNotActive(RelayerAddress relayer);
    error ParameterLengthMismatch();
    error RelayerIndexDoesNotPointToSelectedCdfInterval();
    error RelayerAddressDoesNotMatchSelectedRelayer();
    error InvalidLatestRelayerState();
    error InvalidActiveRelayerState();
    error OnlySelf();

    event DelegatorRewardsAdded(RelayerAddress indexed _relayer, TokenAddress indexed _token, uint256 indexed _amount);
    event NewRelayerState(bytes32 indexed relayerStateHash, RelayerState relayerState);
}
