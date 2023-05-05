// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import "./IWormholeApplicationEventsErrors.sol";
import "./IWormholeDelivery.sol";

interface IWormholeApplication is IWormholeApplicationEventsErrors {
    function executeWormhole(IWormholeDelivery.TargetDeliveryParameters memory targetParams) external payable;
}
