// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import {RelayerAddress} from "./TATypes.sol";
import {RAArrayHelper} from "src/library/arrays/RAArrayHelper.sol";
import {U256ArrayHelper} from "src/library/arrays/U256ArrayHelper.sol";

library RelayerStateManager {
    using RAArrayHelper for RelayerAddress[];
    using U256ArrayHelper for uint256[];

    /// @dev Struct for storing the state of all relayers in the system.
    /// @custom:member cdf The cumulative distribution function of the relayers.
    /// @custom:member relayers The list of relayers.
    struct RelayerState {
        uint256[] cdf;
        RelayerAddress[] relayers;
    }

    function addNewRelayer(RelayerState calldata _prev, RelayerAddress _relayerAddress, uint256 _stake)
        internal
        pure
        returns (RelayerState memory _newState)
    {
        _newState = RelayerState({
            cdf: _prev.cdf.cd_append(_stake + _prev.cdf[_prev.cdf.length - 1]),
            relayers: _prev.relayers.cd_append(_relayerAddress)
        });
    }

    function removeRelayer(RelayerState calldata _prev, uint256 _index)
        internal
        pure
        returns (RelayerState memory _newState)
    {
        _newState = RelayerState({cdf: _prev.cdf.cd_remove(_index), relayers: _prev.relayers.cd_remove(_index)});
    }

    function increaseWeight(RelayerState calldata _prev, uint256 _relayerIndex, uint256 _value)
        internal
        pure
        returns (uint256[] memory _newCdf)
    {
        _newCdf = _prev.cdf;
        uint256 length = _newCdf.length;
        for (uint256 i = _relayerIndex; i != length;) {
            _newCdf[i] += _value;
            unchecked {
                ++i;
            }
        }
    }

    function decreaseWeight(RelayerState calldata _prev, uint256 _relayerIndex, uint256 _value)
        internal
        pure
        returns (uint256[] memory _newCdf)
    {
        _newCdf = _prev.cdf;
        uint256 length = _newCdf.length;
        for (uint256 i = _relayerIndex; i != length;) {
            _newCdf[i] -= _value;
            unchecked {
                ++i;
            }
        }
    }

    function cdfToWeights(uint256[] calldata _cdf) internal pure returns (uint256[] memory weights) {
        uint256 length = _cdf.length;
        weights = new uint256[](length);
        weights[0] = _cdf[0];
        for (uint256 i = 1; i != length;) {
            weights[i] = _cdf[i] - _cdf[i - 1];
            unchecked {
                ++i;
            }
        }
    }

    function weightsToCdf(uint256[] memory _weights) internal pure returns (uint256[] memory cdf) {
        uint256 length = _weights.length;
        cdf = new uint256[](length);
        uint256 sum;
        for (uint256 i; i != length;) {
            sum += _weights[i];
            cdf[i] = sum;
            unchecked {
                ++i;
            }
        }
    }

    /// @dev Hash function used to generate the hash of the relayer state.
    /// @param _cdfHash The hash of the CDF array
    /// @param _relayerArrayHash The hash of the relayer array
    /// @return The hash of the relayer state
    function hash(bytes32 _cdfHash, bytes32 _relayerArrayHash) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked(_cdfHash, _relayerArrayHash));
    }

    function hash(RelayerState memory _state) internal pure returns (bytes32) {
        return hash(_state.cdf.m_hash(), _state.relayers.m_hash());
    }

    function hash(uint256[] memory _cdf, RelayerAddress[] calldata _relayers) internal pure returns (bytes32) {
        return hash(_cdf.m_hash(), _relayers.cd_hash());
    }
}
