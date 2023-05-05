// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import "./interfaces/IWormholeApplication.sol";
import "../base-application/ApplicationBase.sol";

contract WormholeApplication is IWormholeApplication, ApplicationBase {
    function _getTransactionHash(bytes calldata _txCalldata) internal pure virtual override returns (bytes32) {}

    function _getVAASequenceNumber(bytes calldata _encodedVAA) internal pure returns (uint256) {}

    function executeWormhole(IWormholeDelivery.TargetDeliveryParameters calldata _targetParams)
        external
        payable
        override
        applicationHandler(_targetParams.encodedDeliveryVAA)
    {}
}
