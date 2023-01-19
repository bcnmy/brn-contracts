// SPDX-License-Identifier: MIT

import "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/math/SafeCast.sol";
import "hardhat/console.sol";

pragma solidity 0.8.17;

interface ITransactionAllocator {
    error InvalidStakeArrayHash();

    error InvalidCdfArrayHash();

    error NoAccountsProvided();

    error InvalidRelayerWindow();

    error InsufficientStake(uint256 stake, uint256 minimumStake);

    error InvalidWithdrawal(uint256 amount, uint256 currentTime, uint256 minValidTime, uint256 maxValidTime);

    error InvalidRelayerWindowForReporter();

    error InvalidAbsenteeBlockNumber();

    error InvalidAbsenteeCdfArrayHash();

    error InvalidRelayeWindowForAbsentee();

    error AbsenteeWasPresent(uint256 absenteeWindowId);

    error NoRelayersRegistered();

    error InsufficientRelayersRegistered();

    error RelayerAllocationResultLengthMismatch(uint256 expectedLength, uint256 actualLength);
}
