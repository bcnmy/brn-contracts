// SPDX-License-Identifier: MIT

import "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/math/SafeCast.sol";

pragma solidity 0.8.17;

interface ITransactionAllocator {
    error InvalidStakeArrayHash();
    error InvalidCdfArrayHash();
    error NoAccountsProvided();
    error InvalidRelayerWindow();
    error InsufficientStake(uint256 stake, uint256 minimumStake);
    error InvalidWithdrawal(
        uint256 amount,
        uint256 currentTime,
        uint256 minValidTime,
        uint256 maxValidTime
    );
    error InvalidRelayerWindowForReporter();
    error InvalidAbsenteeBlockNumber();
    error InvalidAbsenteeCdfArrayHash();
    error InvalidRelayeWindowForAbsentee();
    error AbsenteeWasPresent(uint256 absenteeWindowId);
    error NoRelayersRegistered();
    error InsufficientRelayersRegistered();
    error RelayerAllocationResultLengthMismatch(
        uint256 expectedLength,
        uint256 actualLength
    );
    error ReporterTransferFailed(address reporter, uint256 amount);

    event RelayerRegistered(
        address indexed relayer,
        string endpoint,
        address[] accounts,
        uint256 stake
    );
    event RelayerUnRegistered(address indexed relayer);
    event Withdraw(address indexed relayer, uint256 amount);
    event StakeArrayUpdated(bytes32 indexed stakePercArrayHash);
    event CdfArrayUpdated(bytes32 indexed cdfArrayHash);
    event AbsenceProofProcessed(
        uint256 indexed windowId,
        address indexed reporter,
        address indexed absentRelayer,
        uint256 absenceWindowId,
        uint256 penalty
    );
    event GenericGasConsumed(string label, uint256 gasConsumed);
}
