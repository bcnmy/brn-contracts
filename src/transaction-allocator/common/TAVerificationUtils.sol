// SPDX-License-Identifier: MIT

import "../../library/TAProxyStorage.sol";
import "../../interfaces/ITAVerificationUtils.sol";
import "../../structs/Transaction.sol";

pragma solidity 0.8.17;

contract TAVerificationUtils is ITAVerificationUtils {
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

    function _verifyLatestCdfHash(uint16[] calldata _array) internal view returns (bool) {
        TAStorage storage ps = TAProxyStorage.getProxyStorage();
        return ps.cdfHashUpdateLog[ps.cdfHashUpdateLog.length - 1].cdfHash == keccak256(abi.encodePacked(_array));
    }

    function _verifyPrevCdfHash(uint16[] calldata _array, uint256 _windowId, uint256 _cdfLogIndex)
        internal
        view
        returns (bool)
    {
        // Validate _cdfLogIndex
        TAStorage storage ps = TAProxyStorage.getProxyStorage();
        if (
            !(
                ps.cdfHashUpdateLog[_cdfLogIndex].windowId <= _windowId
                    && (
                        _cdfLogIndex == ps.cdfHashUpdateLog.length - 1
                            || ps.cdfHashUpdateLog[_cdfLogIndex + 1].windowId > _windowId
                    )
            )
        ) {
            return false;
        }

        return ps.cdfHashUpdateLog[_cdfLogIndex].cdfHash == keccak256(abi.encodePacked(_array));
    }

    function _verifyStakeArrayHash(uint32[] calldata _array) internal view returns (bool) {
        TAStorage storage ps = TAProxyStorage.getProxyStorage();
        return ps.stakeArrayHash == keccak256(abi.encodePacked((_array)));
    }

    function _windowIdentifier(uint256 _blockNumber) internal view returns (uint256) {
        TAStorage storage ps = TAProxyStorage.getProxyStorage();
        return _blockNumber / ps.blocksWindow;
    }

    function _assignRelayer(bytes calldata _calldata) internal view returns (uint256 relayerIndex) {
        TAStorage storage ps = TAProxyStorage.getProxyStorage();
        relayerIndex = uint256(keccak256(abi.encodePacked(_calldata))) % ps.relayersPerWindow;
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

    /// @notice returns true if the current sender is allowed to relay transaction in this block
    function _verifyTransactionAllocation(
        uint16[] calldata _cdf,
        uint256 _cdfIndex,
        uint256[] calldata _relayerGenerationIteration,
        uint256 _blockNumber,
        ForwardRequest[] calldata _txs
    ) internal view returns (bool) {
        if (!_verifyRelayerSelection(msg.sender, _cdf, _cdfIndex, _relayerGenerationIteration, _blockNumber)) {
            return false;
        }

        // Store all relayerGenerationIterations in a bitmap to efficiently check for existence in _relayerGenerationIteration
        // ASSUMPTION: Max no. of iterations required to generate 'relayersPerWindow' unique relayers <= 256
        uint256 bitmap = 0;
        uint256 length = _relayerGenerationIteration.length;
        for (uint256 i = 0; i < length;) {
            bitmap |= (1 << _relayerGenerationIteration[i]);
            unchecked {
                ++i;
            }
        }

        // Verify if the transaction was alloted to the relayer
        length = _txs.length;
        for (uint256 i = 0; i < length;) {
            uint256 relayerGenerationIteration = _assignRelayer(_txs[i].data);
            if ((bitmap & (1 << relayerGenerationIteration)) == 0) {
                return false;
            }
            unchecked {
                ++i;
            }
        }

        return true;
    }

    function _verifyRelayerSelection(
        address _relayer,
        uint16[] calldata _cdf,
        uint256 _cdfIndex,
        uint256[] calldata _relayerGenerationIterations,
        uint256 _blockNumber
    ) internal view returns (bool) {
        TAStorage storage ps = TAProxyStorage.getProxyStorage();

        uint256 iterationCount = _relayerGenerationIterations.length;
        uint256 stakeSum = _cdf[_cdf.length - 1];

        // Verify Each Iteration against _cdfIndex in _cdf
        for (uint256 i = 0; i < iterationCount;) {
            uint256 relayerGenerationIteration = _relayerGenerationIterations[i];

            if (relayerGenerationIteration >= ps.relayersPerWindow) {
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
        address relayerAddress = ps.relayerIndexToRelayer[_cdfIndex];
        RelayerInfo storage node = ps.relayerInfo[relayerAddress];
        if (!node.isAccount[_relayer] && relayerAddress != _relayer) {
            return false;
        }

        return true;
    }
}
