// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import "lib/wormhole/ethereum/contracts/interfaces/relayer/IDelivery.sol";
import "lib/wormhole/ethereum/contracts/interfaces/IWormhole.sol";
import "lib/wormhole/ethereum/contracts/interfaces/relayer/IDelivery.sol";

import "./IWormholeApplicationEventsErrors.sol";
import "src/transaction-allocator/common/TAStructs.sol";

interface IWormholeApplication is IWormholeApplicationEventsErrors {
    function initialize(IWormhole _wormhole, IDelivery _delivery) external;
    function executeWormhole(IDelivery.TargetDeliveryParameters memory targetParams) external payable;
    function allocateWormholeDeliveryVAA(AllocateTransactionParams calldata _params)
        external
        view
        returns (bytes[] memory, uint256, uint256);
}
