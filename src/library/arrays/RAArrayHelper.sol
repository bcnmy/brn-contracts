// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import "ta-common/TATypes.sol";

library RAArrayHelper {
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

    function cd_remove(RelayerAddress[] calldata _array, uint256 _index)
        internal
        pure
        returns (RelayerAddress[] memory)
    {
        uint256 length = _array.length - 1;
        RelayerAddress[] memory newArray = new RelayerAddress[](length);

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

    function cd_update(RelayerAddress[] calldata _array, uint256 _index, RelayerAddress _value)
        internal
        pure
        returns (RelayerAddress[] memory)
    {
        RelayerAddress[] memory newArray = _array;
        newArray[_index] = _value;
        return newArray;
    }

    function cd_hash(RelayerAddress[] calldata _array) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked((_array)));
    }

    function cd_linearSearch(RelayerAddress[] calldata _array, RelayerAddress _x) internal pure returns (uint256) {
        uint256 length = _array.length;
        for (uint256 i; i != length;) {
            if (_array[i] == _x) {
                return i;
            }
            unchecked {
                ++i;
            }
        }
        return length;
    }

    function m_hash(RelayerAddress[] memory _array) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked((_array)));
    }

    function m_remove(RelayerAddress[] memory _array, uint256 _index) internal pure {
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
