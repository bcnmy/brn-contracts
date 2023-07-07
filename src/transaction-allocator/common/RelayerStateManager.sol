// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import {RelayerAddress} from "./TATypes.sol";
import {RAArrayHelper} from "src/library/arrays/RAArrayHelper.sol";
import {U256ArrayHelper} from "src/library/arrays/U256ArrayHelper.sol";

/// @title RelayerStateManager
/// @dev Library for managing the state of the relayers.
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

    /// @dev Appends a new relayer with the given stake to the state.
    /// @param _prev The previous state of the relayers.
    /// @param _relayerAddress The address of the relayer.
    /// @param _stake The stake of the relayer.
    /// @return newState The new state of the relayers.
    function addNewRelayer(RelayerState calldata _prev, RelayerAddress _relayerAddress, uint256 _stake)
        internal
        pure
        returns (RelayerState memory newState)
    {
        newState = RelayerState({
            cdf: _prev.cdf.cd_append(_stake + _prev.cdf[_prev.cdf.length - 1]),
            relayers: _prev.relayers.cd_append(_relayerAddress)
        });
    }

    /// @dev Removes a relayer from the state at the given index
    /// @param _prev The previous state of the relayers.
    /// @param _index The index of the relayer to remove.
    /// @return newState The new state of the relayers.
    function removeRelayer(RelayerState calldata _prev, uint256 _index)
        internal
        pure
        returns (RelayerState memory newState)
    {
        uint256 length = _prev.cdf.length;
        uint256 weightRemoved = _prev.cdf[_index] - (_index == 0 ? 0 : _prev.cdf[_index - 1]);
        uint256 lastWeight = _prev.cdf[length - 1] - (length == 1 ? 0 : _prev.cdf[length - 2]);

        // Copy all the elements except the last one
        uint256[] memory newCdf = new uint256[](length - 1);
        --length;
        for (uint256 i; i != length;) {
            newCdf[i] = _prev.cdf[i];

            unchecked {
                ++i;
            }
        }

        // Update the CDF starting from the index
        if (_index < length) {
            bool elementAtIndexIsIncreased = lastWeight >= weightRemoved;
            uint256 deltaAtIndex = elementAtIndexIsIncreased ? lastWeight - weightRemoved : weightRemoved - lastWeight;

            for (uint256 i = _index; i != length;) {
                if (elementAtIndexIsIncreased) {
                    newCdf[i] += deltaAtIndex;
                } else {
                    newCdf[i] -= deltaAtIndex;
                }

                unchecked {
                    ++i;
                }
            }
        }

        newState = RelayerState({cdf: newCdf, relayers: _prev.relayers.cd_remove(_index)});
    }

    /// @dev Increases the weight of a relayer in the CDF.
    /// @param _prev The previous state of the relayers.
    /// @param _relayerIndex The index of the relayer to update.
    /// @param _value The value to increase the relayer weight by.
    /// @return newCdf The new CDF of the relayers.
    function increaseWeight(RelayerState calldata _prev, uint256 _relayerIndex, uint256 _value)
        internal
        pure
        returns (uint256[] memory newCdf)
    {
        newCdf = _prev.cdf;
        uint256 length = newCdf.length;
        for (uint256 i = _relayerIndex; i != length;) {
            newCdf[i] += _value;
            unchecked {
                ++i;
            }
        }
    }

    /// @dev Decreases the weight of a relayer in the CDF.
    /// @param _prev The previous state of the relayers.
    /// @param _relayerIndex The index of the relayer to update.
    /// @param _value The value to decrease the relayer weight by.
    /// @return newCdf The new CDF of the relayers.
    function decreaseWeight(RelayerState calldata _prev, uint256 _relayerIndex, uint256 _value)
        internal
        pure
        returns (uint256[] memory newCdf)
    {
        newCdf = _prev.cdf;
        uint256 length = newCdf.length;
        for (uint256 i = _relayerIndex; i != length;) {
            newCdf[i] -= _value;
            unchecked {
                ++i;
            }
        }
    }

    /// @dev Given a CDF, calculates an array of individual weights.
    /// @param _cdf The CDF to convert.
    /// @return weights The array of weights.
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

    /// @dev Given an array of weights, calculates the CDF.
    /// @param _weights The array of weights to convert.
    /// @return cdf The CDF.
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

    /// @dev Hash function used to generate the hash of the relayer state.
    /// @param _state The relayer state
    /// @return The hash of the relayer state
    function hash(RelayerState memory _state) internal pure returns (bytes32) {
        return hash(_state.cdf.m_hash(), _state.relayers.m_hash());
    }

    /// @dev Hash function used to generate the hash of the relayer state. This variant is useful when the
    ///      original list of relayers has not changed
    /// @param _cdf The CDF array
    /// @param _relayers The relayer array
    /// @return The hash of the relayer state
    function hash(uint256[] memory _cdf, RelayerAddress[] calldata _relayers) internal pure returns (bytes32) {
        return hash(_cdf.m_hash(), _relayers.cd_hash());
    }
}
