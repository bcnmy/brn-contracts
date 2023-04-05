// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

interface IApplicationMockEventsErrors {
    error AppPrepaymentFailed();

    event UpdatedA(uint256 a);
}
