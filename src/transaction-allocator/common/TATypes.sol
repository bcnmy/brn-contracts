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

type WindowIndex is uint64;

function windowIndexEquality(WindowIndex a, WindowIndex b) pure returns (bool) {
    return WindowIndex.unwrap(a) == WindowIndex.unwrap(b);
}

function windowIndexInequality(WindowIndex a, WindowIndex b) pure returns (bool) {
    return WindowIndex.unwrap(a) != WindowIndex.unwrap(b);
}

function windowIndexGte(WindowIndex a, WindowIndex b) pure returns (bool) {
    return WindowIndex.unwrap(a) >= WindowIndex.unwrap(b);
}

function windowIndexLte(WindowIndex a, WindowIndex b) pure returns (bool) {
    return WindowIndex.unwrap(a) <= WindowIndex.unwrap(b);
}

function windowIndexGt(WindowIndex a, WindowIndex b) pure returns (bool) {
    return WindowIndex.unwrap(a) > WindowIndex.unwrap(b);
}

function windowIndexLt(WindowIndex a, WindowIndex b) pure returns (bool) {
    return WindowIndex.unwrap(a) < WindowIndex.unwrap(b);
}

using {
    windowIndexEquality as ==,
    windowIndexInequality as !=,
    windowIndexGte as >=,
    windowIndexLte as <=,
    windowIndexGt as >,
    windowIndexLt as <
} for WindowIndex global;
