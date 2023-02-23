// SPDX-License-Identifier: MIT

import "openzeppelin-contracts/contracts/utils/cryptography/EIP712.sol";
import "openzeppelin-contracts/contracts/utils/cryptography/ECDSA.sol";
import "openzeppelin-contracts/contracts/access/Ownable.sol";
import "openzeppelin-contracts/contracts/utils/math/SafeCast.sol";

pragma solidity 0.8.17;

interface ITAAllocationHelper {
    error NoRelayersRegistered();
    error InsufficientRelayersRegistered();
    error RelayerAllocationResultLengthMismatch(uint256 expectedLength, uint256 actualLength);

    function allocateRelayers(uint256 _blockNumber, uint16[] calldata _cdf)
        external
        view
        returns (address[] memory, uint256[] memory);

    function allocateTransaction(
        address _relayer,
        uint256 _blockNumber,
        bytes[] calldata _txnCalldata,
        uint16[] calldata _cdf
    ) external view returns (bytes[] memory, uint256[] memory, uint256);
}
