// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import "ta-common/TATypes.sol";

/// @title Relayer Address Array Helper
/// @dev Helper functions for arrays of RelayerAddress
library RAArrayHelper {
    error IndexOutOfBounds(uint256 index, uint256 length);

    /// @dev Copies the array into memory and appends the value
    /// @param _array The array to append to
    /// @param _value The value to append
    function cd_append(RelayerAddress[] calldata _array, RelayerAddress _value)
        internal
        pure
        returns (RelayerAddress[] memory)
    {
        uint256 length = _array.length;
        RelayerAddress[] memory newArray = new RelayerAddress[](
            length + 1
        );

        for (uint256 i; i != length;) {
            newArray[i] = _array[i];
            unchecked {
                ++i;
            }
        }
        newArray[length] = _value;

        return newArray;
    }

    /// @dev Copies the array into memory and removes the value at the index, substituting the last value
    /// @param _array The array to remove from
    /// @param _index The index to remove
    function cd_remove(RelayerAddress[] calldata _array, uint256 _index)
        internal
        pure
        returns (RelayerAddress[] memory)
    {
        uint256 newLength = _array.length - 1;
        if (_index > newLength) {
            revert IndexOutOfBounds(_index, _array.length);
        }

        RelayerAddress[] memory newArray = new RelayerAddress[](newLength);

        for (uint256 i; i != newLength;) {
            if (i != _index) {
                newArray[i] = _array[i];
            } else {
                newArray[i] = _array[newLength];
            }
            unchecked {
                ++i;
            }
        }

        return newArray;
    }

    /// @dev Copies the array into memory and updates the value at the index
    /// @param _array The array to update
    /// @param _index The index to update
    /// @param _value The value to update
    function cd_update(RelayerAddress[] calldata _array, uint256 _index, RelayerAddress _value)
        internal
        pure
        returns (RelayerAddress[] memory)
    {
        if (_index >= _array.length) {
            revert IndexOutOfBounds(_index, _array.length);
        }

        RelayerAddress[] memory newArray = _array;
        newArray[_index] = _value;
        return newArray;
    }

    /// @dev Calculate the hash of the array by packing the values and hashing them through keccak256
    /// @param _array The array to hash
    function cd_hash(RelayerAddress[] calldata _array) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked((_array)));
    }

    /// @dev Calculate the hash of the array by packing the values and hashing them through keccak256
    /// @param _array The array to hash
    function m_hash(RelayerAddress[] memory _array) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked((_array)));
    }

    /// @dev Removes the value at the index, substituting the last value.
    /// @param _array The array to remove from
    /// @param _index The index to remove
    function m_remove(RelayerAddress[] memory _array, uint256 _index) internal pure {
        uint256 newLength = _array.length - 1;

        if (_index > newLength) {
            revert IndexOutOfBounds(_index, _array.length);
        }

        if (_index != newLength) {
            _array[_index] = _array[newLength];
        }

        // Reduce the array size
        assembly {
            mstore(_array, sub(mload(_array), 1))
        }
    }
}
