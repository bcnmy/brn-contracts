// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

library VersionHistoryManager {
    struct Version {
        bytes32 contentHash;
        uint256 timestamp;
    }

    function verifyLatestContentHash(Version[] storage _versionHistoryContainer, bytes32 _contentHash)
        internal
        view
        returns (bool)
    {
        // Establish that the content hash at the index is correct
        return _versionHistoryContainer[_versionHistoryContainer.length - 1].contentHash == _contentHash;
    }

    function verifyContentHashAtTimestamp(
        Version[] storage _versionHistoryContainer,
        bytes32 _contentHash,
        uint256 _index,
        uint256 _timestamp
    ) internal view returns (bool) {
        uint256 length = _versionHistoryContainer.length;

        // Establish that the index is within bounds
        if (_index >= length) {
            return false;
        }

        // Establish that the index points to the version with the correct timestamp
        if (
            !(
                _versionHistoryContainer[_index].timestamp <= _timestamp
                    && (_index == length - 1 || _versionHistoryContainer[_index + 1].timestamp > _timestamp)
            )
        ) {
            return false;
        }

        // Establish that the content hash at the index is correct
        return _versionHistoryContainer[_index].contentHash == _contentHash;
    }

    function addNewVersion(
        Version[] storage _versionHistoryContainer,
        bytes32 _contentHash,
        uint256 _versionActivationTimestamp
    ) internal {
        uint256 length = _versionHistoryContainer.length;

        if (
            _versionHistoryContainer.length > 0
                && _versionHistoryContainer[length - 1].timestamp == _versionActivationTimestamp
        ) {
            // If a pending version already exists, overwrite it
            _versionHistoryContainer[length - 1].contentHash = _contentHash;
        } else {
            _versionHistoryContainer.push(Version({contentHash: _contentHash, timestamp: _versionActivationTimestamp}));
        }
    }
}
