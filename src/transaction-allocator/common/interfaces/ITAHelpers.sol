// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import {RelayerAddress, TokenAddress} from "../TATypes.sol";
import {FixedPointType} from "src/library/FixedPointArithmetic.sol";

/// @title ITAHelpers
interface ITAHelpers {
    error RelayerIsNotActive(RelayerAddress relayer);
    error ParameterLengthMismatch();
    error InvalidLatestRelayerState();
    error InvalidActiveRelayerState();

    event DelegatorRewardsAdded(RelayerAddress indexed _relayer, TokenAddress indexed _token, uint256 indexed _amount);
    event RelayerProtocolSharesBurnt(RelayerAddress indexed relayerAddress, FixedPointType indexed sharesBurnt);
}
