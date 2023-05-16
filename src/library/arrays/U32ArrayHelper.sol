// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

library U32ArrayHelper {
    function cd_append(uint32[] calldata _array, uint32 _value) internal pure returns (uint32[] memory) {
        uint256 length = _array.length;
        uint32[] memory newArray = new uint32[](
            length + 1
        );

        for (uint256 i = 0; i < length;) {
            newArray[i] = _array[i];
            unchecked {
                ++i;
            }
        }
        newArray[length] = _value;

        return newArray;
    }

    function cd_remove(uint32[] calldata _array, uint256 _index) internal pure returns (uint32[] memory) {
        uint256 length = _array.length - 1;
        uint32[] memory newArray = new uint32[](length);

        for (uint256 i = 0; i < length;) {
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

    function cd_update(uint32[] calldata _array, uint256 _index, uint32 _value)
        internal
        pure
        returns (uint32[] memory)
    {
        uint32[] memory newArray = _array;
        newArray[_index] = _value;
        return newArray;
    }

    function cd_hash(uint32[] calldata _array) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked((_array)));
    }

    function m_hash(uint32[] memory _array) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked((_array)));
    }
}
