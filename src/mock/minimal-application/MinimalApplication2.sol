// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import "./interfaces/IMinimalApplication.sol";
import "ta-base-application/ApplicationBase.sol";

contract MinimalApplication2 is IMinimalApplication, ApplicationBase {
    uint256 public count;

    function _getTransactionHash(bytes calldata _tx) internal pure virtual override returns (bytes32) {
        return keccak256(_tx);
    }

    function executeMinimalApplication(bytes32 _data) external payable override {
        _verifyTransaction(_getTransactionHash(msg.data));

        count++;
        emit MessageEmitted(_data);
    }

    function allocateMinimalApplicationTransaction(
        RelayerAddress _relayerAddress,
        bytes[] calldata _requests,
        RelayerState calldata _currentState
    ) external view override returns (bytes[] memory txns, uint256 rgi, uint256 index) {
        (txns, rgi, index) = _allocateTransaction(_relayerAddress, _requests, _currentState);
    }
}
