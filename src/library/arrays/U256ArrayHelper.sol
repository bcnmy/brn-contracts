// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

/// @title uint256 Array Helper
/// @dev Helper functions for arrays of uint256
library U256ArrayHelper {
    error IndexOutOfBoundsU256(uint256 index, uint256 length);

    /// @dev Copies the array into memory and appends the value
    /// @param _array The array to append to
    /// @param _value The value to append
    /// @return The new array
    function cd_append(uint256[] calldata _array, uint256 _value) internal pure returns (uint256[] memory) {
        uint256 length = _array.length;
        uint256[] memory newArray = new uint256[](
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
    /// @return The new array
    function cd_remove(uint256[] calldata _array, uint256 _index) internal pure returns (uint256[] memory) {
        uint256 newLength = _array.length - 1;
        if (_index > newLength) {
            revert IndexOutOfBoundsU256(_index, _array.length);
        }

        uint256[] memory newArray = new uint256[](newLength);

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
    /// @return The new array
    function cd_update(uint256[] calldata _array, uint256 _index, uint256 _value)
        internal
        pure
        returns (uint256[] memory)
    {
        if (_index >= _array.length) {
            revert IndexOutOfBoundsU256(_index, _array.length);
        }

        uint256[] memory newArray = _array;
        newArray[_index] = _value;
        return newArray;
    }

    /// @dev Calculate the hash of the array by packing the values and hashing them through keccak256
    /// @param _array The array to hash
    /// @return The hash of the array
    function cd_hash(uint256[] calldata _array) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked((_array)));
    }

    /// @dev Returns the index of the first element in _array greater than or equal to _target
    ///      The array must be sorted
    /// @param _array The array to find in
    /// @param _target The target value
    /// @return The index of the first element greater than or equal to _target
    function cd_lowerBound(uint256[] calldata _array, uint256 _target) internal pure returns (uint256) {
        uint256 low;
        uint256 high = _array.length;
        unchecked {
            while (low < high) {
                uint256 mid = (low + high) / 2;
                if (_array[mid] < _target) {
                    low = mid + 1;
                } else {
                    high = mid;
                }
            }
        }
        return low;
    }

    /// @dev Calculate the hash of the array by packing the values and hashing them through keccak256
    /// @param _array The array to hash
    /// @return The hash of the array
    function m_hash(uint256[] memory _array) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked((_array)));
    }

    /// @dev Removes the value at the index, substituting the last value.
    /// @param _array The array to remove from
    /// @param _index The index to remove
    function m_remove(uint256[] memory _array, uint256 _index) internal pure {
        uint256 newLength = _array.length - 1;

        if (_index > newLength) {
            revert IndexOutOfBoundsU256(_index, _array.length);
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
