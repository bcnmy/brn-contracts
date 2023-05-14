// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import "src/transaction-allocator/common/TATypes.sol";

// TODO: Optimize

library U32CalldataArrayHelpers {
    function append(uint32[] calldata _array, uint32 _value) internal pure returns (uint32[] memory) {
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

    function remove(uint32[] calldata _array, uint256 _index) internal pure returns (uint32[] memory) {
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

    function update(uint32[] calldata _array, uint256 _index, uint32 _value) internal pure returns (uint32[] memory) {
        uint32[] memory newArray = _array;
        newArray[_index] = _value;
        return newArray;
    }
}

library RelayerAddressCalldataArrayHelpers {
    function append(RelayerAddress[] calldata _array, RelayerAddress _value)
        internal
        pure
        returns (RelayerAddress[] memory)
    {
        uint256 length = _array.length;
        RelayerAddress[] memory newArray = new RelayerAddress[](
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

    function remove(RelayerAddress[] calldata _array, uint256 _index) internal pure returns (RelayerAddress[] memory) {
        uint256 length = _array.length - 1;
        RelayerAddress[] memory newArray = new RelayerAddress[](length);

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

    function update(RelayerAddress[] calldata _array, uint256 _index, RelayerAddress _value)
        internal
        pure
        returns (RelayerAddress[] memory)
    {
        RelayerAddress[] memory newArray = _array;
        newArray[_index] = _value;
        return newArray;
    }
}
