// SPDX-License-Identifier: MIT

pragma solidity 0.8.17;

import "../common/TAVerificationUtils.sol";
import "../../library/TAProxyStorage.sol";
import "../../interfaces/ITAAllocationHelper.sol";

contract TAAllocationHelper is TAVerificationUtils, ITAAllocationHelper {
    function _lowerBound(uint16[] calldata arr, uint256 target) internal pure returns (uint256) {
        uint256 low = 0;
        uint256 high = arr.length;
        unchecked {
            while (low < high) {
                uint256 mid = (low + high) / 2;
                if (arr[mid] < target) {
                    low = mid + 1;
                } else {
                    high = mid;
                }
            }
        }
        return low;
    }

    /// @notice Given a block number, the function generates a list of pseudo-random relayers
    ///         for the window of which the block in a part of. The generated list of relayers
    ///         is pseudo-random but deterministic
    /// @param _blockNumber block number for which the relayers are to be generated
    /// @return selectedRelayers list of relayers selected of length relayersPerWindow, but
    ///                          there can be duplicates
    /// @return cdfIndex list of indices of the selected relayers in the cdf, used for verification
    function allocateRelayers(uint256 _blockNumber, uint16[] calldata _cdf)
        public
        view
        verifyCdfHash(_cdf)
        returns (address[] memory, uint256[] memory)
    {
        TAStorage storage ps = TAProxyStorage.getProxyStorage();

        if (_cdf.length == 0) {
            revert NoRelayersRegistered();
        }
        if (ps.relayerCount < ps.relayersPerWindow) {
            revert InsufficientRelayersRegistered();
        }
        if (_blockNumber == 0) {
            _blockNumber = block.number;
        }

        // Generate `relayersPerWindow` pseudo-random distinct relayers
        address[] memory selectedRelayers = new address[](ps.relayersPerWindow);
        uint256[] memory cdfIndex = new uint256[](ps.relayersPerWindow);

        uint256 cdfLength = _cdf.length;
        if (_cdf[cdfLength - 1] == 0) {
            revert NoRelayersRegistered();
        }

        for (uint256 i = 0; i < ps.relayersPerWindow;) {
            uint256 randomCdfNumber = _randomCdfNumber(_blockNumber, i, _cdf[cdfLength - 1]);
            cdfIndex[i] = _lowerBound(_cdf, randomCdfNumber);
            RelayerInfo storage relayer = ps.relayerInfo[ps.relayerIndexToRelayer[cdfIndex[i]]];
            uint256 relayerIndex = relayer.index;
            address relayerAddress = ps.relayerIndexToRelayer[relayerIndex];
            selectedRelayers[i] = relayerAddress;

            unchecked {
                ++i;
            }
        }
        return (selectedRelayers, cdfIndex);
    }

    /// @notice determine what transactions can be relayed by the sender
    /// @param _relayer Address of the relayer to allocate transactions for
    /// @param _blockNumber block number for which the relayers are to be generated
    /// @param _txnCalldata list with all transactions calldata to be filtered
    /// @return txnAllocated list of transactions that can be relayed by the relayer
    /// @return relayerGenerationIteration list of iterations of the relayer generation corresponding
    ///                                    to the selected transactions
    /// @return selectedRelayersCdfIndex index of the selected relayer in the cdf
    function allocateTransaction(
        address _relayer,
        uint256 _blockNumber,
        bytes[] calldata _txnCalldata,
        uint16[] calldata _cdf
    ) public view verifyCdfHash(_cdf) returns (bytes[] memory, uint256[] memory, uint256) {
        TAStorage storage ps = TAProxyStorage.getProxyStorage();

        if (_blockNumber == 0) {
            _blockNumber = block.number;
        }

        (address[] memory relayersAllocated, uint256[] memory relayerStakePrefixSumIndex) =
            allocateRelayers(_blockNumber, _cdf);
        if (relayersAllocated.length != ps.relayersPerWindow) {
            revert RelayerAllocationResultLengthMismatch(ps.relayersPerWindow, relayersAllocated.length);
        }

        // Filter the transactions
        uint256 selectedRelayerCdfIndex;
        bytes[] memory txnAllocated = new bytes[](_txnCalldata.length);
        uint256[] memory relayerGenerationIteration = new uint256[](
            _txnCalldata.length
        );
        uint256 j;

        // Filter the transactions
        for (uint256 i = 0; i < _txnCalldata.length;) {
            uint256 relayerIndex = _assignRelayer(_txnCalldata[i]);
            address relayerAddress = relayersAllocated[relayerIndex];
            RelayerInfo storage node = ps.relayerInfo[relayerAddress];

            // If the transaction can be processed by this relayer, store it's info
            if (node.isAccount[_relayer] || relayerAddress == _relayer) {
                relayerGenerationIteration[j] = relayerIndex;
                txnAllocated[j] = _txnCalldata[i];
                selectedRelayerCdfIndex = relayerStakePrefixSumIndex[relayerIndex];
                unchecked {
                    ++j;
                }
            }

            unchecked {
                ++i;
            }
        }

        // Reduce the array sizes if needed
        uint256 extraLength = _txnCalldata.length - j;
        assembly {
            mstore(txnAllocated, sub(mload(txnAllocated), extraLength))
            mstore(relayerGenerationIteration, sub(mload(relayerGenerationIteration), extraLength))
        }

        return (txnAllocated, relayerGenerationIteration, selectedRelayerCdfIndex);
    }
}
