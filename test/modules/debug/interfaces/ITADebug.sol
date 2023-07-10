// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import "src/library/FixedPointArithmetic.sol";
import "ta-common/TATypes.sol";
import "ta-common/RelayerStateManager.sol";

interface ITADebug {
    function debug_verifyRelayerStateAtWindow(
        RelayerStateManager.RelayerState calldata _relayerState,
        uint256 __windowIndex
    ) external view returns (bool);

    function debug_currentWindowIndex() external view returns (uint256);

    function debug_relayerStateHash(RelayerStateManager.RelayerState calldata _relayerState)
        external
        pure
        returns (bytes32);

    function debug_setTransactionsProcessedByRelayer(RelayerAddress _relayerAddress, uint256 _transactionsProcessed)
        external;

    function debug_setRelayerCount(uint256 _relayerCount) external;

    function debug_setTotalStake(uint256 _totalStake) external;

    function debug_protocolRewardsSharePrice() external view returns (FixedPointType);

    function debug_setBaseProtoocolRewardRate(uint256 _rate) external;

    function debug_getPendingProtocolRewardsData(RelayerAddress _relayerAddress)
        external
        view
        returns (uint256, uint256, FixedPointType);

    function debug_setStakeThresholdForJailing(uint256 _amount) external;

    function debug_setWithdrawal(
        RelayerAddress _relayerAddress,
        DelegatorAddress _delegatorAddress,
        TokenAddress[] calldata _tokens,
        uint256[] calldata _amounts
    ) external;
}
