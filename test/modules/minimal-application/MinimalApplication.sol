// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import "./interfaces/IMinimalApplication.sol";
import "src/transaction-allocator/modules/application/base-application/ApplicationBase.sol";

contract MinimalApplication is IMinimalApplication, ApplicationBase {
    uint256 public count = 0;

    function _getTransactionHash(bytes calldata _tx) internal pure virtual override returns (bytes32) {
        return keccak256(_tx[:20]);
    }

    function executeMinimalApplication(bytes32 _data) external payable override applicationHandler(msg.data) {
        count++;
        emit MessageEmitted(_data);
    }

    function allocateMinimalApplicationTransaction(AllocateTransactionParams calldata _params)
        external
        view
        override
        returns (bytes[] memory, uint256, uint256)
    {
        return _allocateTransaction(_params);
    }
}