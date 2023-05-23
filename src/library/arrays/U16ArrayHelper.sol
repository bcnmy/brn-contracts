// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

library U16ArrayHelper {
    function cd_append(uint16[] calldata _array, uint16 _value) internal pure returns (uint16[] memory) {
        uint256 length = _array.length;
        uint16[] memory newArray = new uint16[](
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

    function cd_remove(uint16[] calldata _array, uint256 _index) internal pure returns (uint16[] memory) {
        uint256 length = _array.length - 1;
        uint16[] memory newArray = new uint16[](length);

        for (uint256 i; i != length;) {
            if (i != _index) {
                newArray[i] = _array[i];
            } else {
                newArray[i] = _array[length];
            }
            unchecked {
                ++i;
            }
        }

        return newArray;
    }

    function cd_update(uint16[] calldata _array, uint256 _index, uint16 _value)
        internal
        pure
        returns (uint16[] memory)
    {
        uint16[] memory newArray = _array;
        newArray[_index] = _value;
        return newArray;
    }

    function cd_hash(uint16[] calldata _array) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked((_array)));
    }

    function m_hash(uint16[] memory _array) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked((_array)));
    }

    function m_remove(uint16[] memory _array, uint256 _index) internal pure {
        uint256 length = _array.length - 1;
        if (_index != length) {
            _array[_index] = _array[length];
        }

        // Reduce the array sizes
        assembly {
            mstore(_array, sub(mload(_array), 1))
        }
    }
}
