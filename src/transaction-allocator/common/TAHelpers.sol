// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";

import "./interfaces/ITAHelpers.sol";
import "./TAConstants.sol";
import "./TATypes.sol";
import "../modules/relayer-management/TARelayerManagementStorage.sol";

abstract contract TAHelpers is TARelayerManagementStorage, ITAHelpers {
    using SafeERC20 for IERC20;

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

        RelayerAddress relayerAddress = ds.relayerIndexToRelayer[_cdfIndex];
        RelayerInfo storage node = ds.relayerInfo[relayerAddress];
        if (!node.isAccount[RelayerAccountAddress.wrap(_relayer)] && relayerAddress != RelayerAddress.wrap(_relayer)) {
            return false;
        }

        return true;
    }

    // Token Helpers
    function _transfer(TokenAddress _token, address _to, uint256 _amount) internal {
        if (_token == NATIVE_TOKEN) {
            uint256 balance = address(this).balance;
            if (balance < _amount) {
                revert InsufficientBalance(_token, balance, _amount);
            }

            (bool status,) = payable(_to).call{value: _amount}("");
            if (!status) {
                revert NativeTransferFailed(_to, _amount);
            }
        } else {
            IERC20 token = IERC20(TokenAddress.unwrap(_token));
            uint256 balance = token.balanceOf(address(this));
            if (balance < _amount) {
                revert InsufficientBalance(_token, balance, _amount);
            }

            token.safeTransfer(_to, _amount);
        }
    }
}
