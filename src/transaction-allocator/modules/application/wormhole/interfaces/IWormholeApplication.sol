// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import "./IWormholeApplicationEventsErrors.sol";
import "lib/wormhole/ethereum/contracts/interfaces/relayer/IDelivery.sol";

interface IWormholeApplication is IWormholeApplicationEventsErrors {
    function executeWormhole(IDelivery.TargetDeliveryParameters memory targetParams) external payable;
}
