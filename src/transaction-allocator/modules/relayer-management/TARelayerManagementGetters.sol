// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import {Guards} from "src/utils/Guards.sol";
import {FixedPointType} from "src/library/FixedPointArithmetic.sol";
import {RelayerAddress, RelayerAccountAddress, TokenAddress} from "ta-common/TATypes.sol";
import {VersionManager} from "src/library/VersionManager.sol";
import {U256ArrayHelper} from "src/library/arrays/U256ArrayHelper.sol";
import {RAArrayHelper} from "src/library/arrays/RAArrayHelper.sol";

import {TARelayerManagementStorage} from "./TARelayerManagementStorage.sol";
import {ITARelayerManagementGetters} from "./interfaces/ITARelayerManagementGetters.sol";
import {TAHelpers} from "ta-common/TAHelpers.sol";
import {RelayerStateManager} from "ta-common/RelayerStateManager.sol";

/// @title TARelayerManagementGetters
abstract contract TARelayerManagementGetters is
    Guards,
    TARelayerManagementStorage,
    ITARelayerManagementGetters,
    TAHelpers
{
    using VersionManager for VersionManager.VersionManagerState;
    using U256ArrayHelper for uint256[];
    using RAArrayHelper for RelayerAddress[];
    using RelayerStateManager for RelayerStateManager.RelayerState;

    function relayerCount() external view override noSelfCall returns (uint256) {
        return getRMStorage().relayerCount;
    }

    function totalStake() external view override noSelfCall returns (uint256) {
        return getRMStorage().totalStake;
    }

    function relayerInfo(RelayerAddress _relayerAddress)
        external
        view
        override
        noSelfCall
        returns (RelayerInfoView memory)
    {
        RMStorage storage rms = getRMStorage();
        RelayerInfo storage node = rms.relayerInfo[_relayerAddress];

        return RelayerInfoView({
            stake: node.stake,
            endpoint: node.endpoint,
            delegatorPoolPremiumShare: node.delegatorPoolPremiumShare,
            status: node.status,
            minExitTimestamp: node.minExitTimestamp,
            unpaidProtocolRewards: node.unpaidProtocolRewards,
            rewardShares: node.rewardShares
        });
    }

    function relayerInfo_isAccount(RelayerAddress _relayerAddress, RelayerAccountAddress _account)
        external
        view
        override
        noSelfCall
        returns (bool)
    {
        return getRMStorage().relayerInfo[_relayerAddress].isAccount[_account];
    }

    function relayersPerWindow() external view override noSelfCall returns (uint256) {
        return getRMStorage().relayersPerWindow;
    }

    function blocksPerWindow() external view override noSelfCall returns (uint256) {
        return getRMStorage().blocksPerWindow;
    }

    function bondTokenAddress() external view override noSelfCall returns (TokenAddress) {
        return TokenAddress.wrap(address(getRMStorage().bondToken));
    }

    function jailTimeInSec() external view override noSelfCall returns (uint256) {
        return getRMStorage().jailTimeInSec;
    }

    function withdrawDelayInSec() external view override noSelfCall returns (uint256) {
        return getRMStorage().withdrawDelayInSec;
    }

    function absencePenaltyPercentage() external view override noSelfCall returns (uint256) {
        return getRMStorage().absencePenaltyPercentage;
    }

    function minimumStakeAmount() external view override noSelfCall returns (uint256) {
        return getRMStorage().minimumStakeAmount;
    }

    function relayerStateUpdateDelayInWindows() external view override noSelfCall returns (uint256) {
        return getRMStorage().relayerStateUpdateDelayInWindows;
    }

    function totalUnpaidProtocolRewards() external view override noSelfCall returns (uint256) {
        return getRMStorage().totalUnpaidProtocolRewards;
    }

    function lastUnpaidRewardUpdatedTimestamp() external view override noSelfCall returns (uint256) {
        return getRMStorage().lastUnpaidRewardUpdatedTimestamp;
    }

    function totalProtocolRewardShares() external view override noSelfCall returns (FixedPointType) {
        return getRMStorage().totalProtocolRewardShares;
    }

    function baseRewardRatePerMinimumStakePerSec() external view override noSelfCall returns (uint256) {
        return getRMStorage().baseRewardRatePerMinimumStakePerSec;
    }

    function protocolRewardRate() external view override noSelfCall returns (uint256) {
        return _protocolRewardRate();
    }

    function relayerStateHash()
        external
        view
        override
        noSelfCall
        returns (bytes32 activeStateHash, bytes32 latestStateHash)
    {
        RMStorage storage rms = getRMStorage();
        activeStateHash = rms.relayerStateVersionManager.activeStateHash(_windowIndex(block.number));
        latestStateHash = rms.relayerStateVersionManager.latestStateHash();
    }

    function getLatestCdfArray(RelayerAddress[] calldata _latestActiveRelayers)
        external
        view
        override
        noSelfCall
        returns (uint256[] memory)
    {
        RMStorage storage rs = getRMStorage();
        TADStorage storage ds = getTADStorage();

        uint256 length = _latestActiveRelayers.length;
        uint256[] memory cdf = new uint256[](length);

        cdf[0] = rs.relayerInfo[_latestActiveRelayers[0]].stake + ds.totalDelegation[_latestActiveRelayers[0]];
        for (uint256 i = 1; i != length;) {
            cdf[i] = rs.relayerInfo[_latestActiveRelayers[i]].stake + ds.totalDelegation[_latestActiveRelayers[i]]
                + cdf[i - 1];
            unchecked {
                ++i;
            }
        }

        RelayerStateManager.RelayerState memory latestState =
            RelayerStateManager.RelayerState({cdf: cdf, relayers: _latestActiveRelayers});
        if (!getRMStorage().relayerStateVersionManager.verifyHashAgainstLatestState(latestState.hash())) {
            revert InvalidLatestRelayerState();
        }

        return cdf;
    }
}
