// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

type RelayerAddress is address;

function relayerEquality(RelayerAddress a, RelayerAddress b) pure returns (bool) {
    return RelayerAddress.unwrap(a) == RelayerAddress.unwrap(b);
}

function relayerInequality(RelayerAddress a, RelayerAddress b) pure returns (bool) {
    return RelayerAddress.unwrap(a) != RelayerAddress.unwrap(b);
}

using {relayerEquality as ==, relayerInequality as !=} for RelayerAddress global;

type DelegatorAddress is address;

function delegatorEquality(DelegatorAddress a, DelegatorAddress b) pure returns (bool) {
    return DelegatorAddress.unwrap(a) == DelegatorAddress.unwrap(b);
}

function delegatorInequality(DelegatorAddress a, DelegatorAddress b) pure returns (bool) {
    return DelegatorAddress.unwrap(a) != DelegatorAddress.unwrap(b);
}

using {delegatorEquality as ==, delegatorInequality as !=} for DelegatorAddress global;

type RelayerAccountAddress is address;

function relayerAccountEquality(RelayerAccountAddress a, RelayerAccountAddress b) pure returns (bool) {
    return RelayerAccountAddress.unwrap(a) == RelayerAccountAddress.unwrap(b);
}

function relayerAccountInequality(RelayerAccountAddress a, RelayerAccountAddress b) pure returns (bool) {
    return RelayerAccountAddress.unwrap(a) != RelayerAccountAddress.unwrap(b);
}

using {relayerAccountEquality as ==, relayerAccountInequality as !=} for RelayerAccountAddress global;

type TokenAddress is address;

function tokenEquality(TokenAddress a, TokenAddress b) pure returns (bool) {
    return TokenAddress.unwrap(a) == TokenAddress.unwrap(b);
}

function tokenInequality(TokenAddress a, TokenAddress b) pure returns (bool) {
    return TokenAddress.unwrap(a) != TokenAddress.unwrap(b);
}

using {tokenEquality as ==, tokenInequality as !=} for TokenAddress global;

type WindowId is uint256;

function windowIdentifierEquality(WindowId a, WindowId b) pure returns (bool) {
    return WindowId.unwrap(a) == WindowId.unwrap(b);
}

function windowIdentifierInequality(WindowId a, WindowId b) pure returns (bool) {
    return WindowId.unwrap(a) != WindowId.unwrap(b);
}

using {windowIdentifierEquality as ==, windowIdentifierInequality as !=} for WindowId global;

type EpochId is uint256;

function epochIdentifierEquality(EpochId a, EpochId b) pure returns (bool) {
    return EpochId.unwrap(a) == EpochId.unwrap(b);
}

function epochIdentifierInequality(EpochId a, EpochId b) pure returns (bool) {
    return EpochId.unwrap(a) != EpochId.unwrap(b);
}

using {epochIdentifierEquality as ==, epochIdentifierInequality as !=} for EpochId global;
