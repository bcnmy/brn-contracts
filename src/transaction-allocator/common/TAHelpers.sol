// SPDX-License-Identifier: MIT

pragma solidity 0.8.17;

import "./interfaces/ITAHelpers.sol";
import "../modules/relayer-management/TARelayerManagementStorage.sol";

contract TAHelpers is TARelayerManagementStorage, ITAHelpers {
    modifier verifyStakeArrayHash(uint32[] calldata _array) {
        if (!_verifyStakeArrayHash(_array)) {
            revert InvalidStakeArrayHash();
        }
        _;
    }

    modifier verifyCdfHash(uint16[] calldata _array) {
        if (!_verifyLatestCdfHash(_array)) {
            revert InvalidCdfArrayHash();
        }
        _;
    }

    function _verifyStakeArrayHash(uint32[] calldata _array) internal view returns (bool) {
        RMStorage storage ds = getRMStorage();
        return ds.stakeArrayHash == keccak256(abi.encodePacked((_array)));
    }

    function _verifyLatestCdfHash(uint16[] calldata _array) internal view returns (bool) {
        RMStorage storage ds = getRMStorage();
        return ds.cdfHashUpdateLog[ds.cdfHashUpdateLog.length - 1].cdfHash == keccak256(abi.encodePacked(_array));
    }

    function _windowIdentifier(uint256 _blockNumber) internal view returns (uint256) {
        RMStorage storage ds = getRMStorage();
        return _blockNumber / ds.blocksPerWindow;
    }

    function _randomCdfNumber(uint256 _blockNumber, uint256 _iter, uint256 _max)
        internal
        view
        returns (uint256 index)
    {
        // The seed for jth iteration is a function of the base seed and j
        uint256 baseSeed = uint256(keccak256(abi.encodePacked(_windowIdentifier(_blockNumber))));
        uint256 seed = uint256(keccak256(abi.encodePacked(baseSeed, _iter)));
        return (seed % _max);
    }

    function _verifyRelayerSelection(
        address _relayer,
        uint16[] calldata _cdf,
        uint256 _cdfIndex,
        uint256[] calldata _relayerGenerationIterations,
        uint256 _blockNumber
    ) internal view returns (bool) {
        RMStorage storage ds = getRMStorage();

        uint256 iterationCount = _relayerGenerationIterations.length;
        uint256 stakeSum = _cdf[_cdf.length - 1];

        // Verify Each Iteration against _cdfIndex in _cdf
        for (uint256 i = 0; i < iterationCount;) {
            uint256 relayerGenerationIteration = _relayerGenerationIterations[i];

            if (relayerGenerationIteration >= ds.relayersPerWindow) {
                return false;
            }

            // Verify if correct stake prefix sum index has been provided
            uint256 randomRelayerStake = _randomCdfNumber(_blockNumber, relayerGenerationIteration, stakeSum);

            if (
                !((_cdfIndex == 0 || _cdf[_cdfIndex - 1] < randomRelayerStake) && randomRelayerStake <= _cdf[_cdfIndex])
            ) {
                // The supplied index does not point to the correct interval
                return false;
            }

            unchecked {
                ++i;
            }
        }

        // Verify if the relayer selected is msg.sender
        address relayerAddress = ds.relayerIndexToRelayer[_cdfIndex];
        RelayerInfo storage node = ds.relayerInfo[relayerAddress];
        if (!node.isAccount[_relayer] && relayerAddress != _relayer) {
            return false;
        }

        return true;
    }
}
