// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

library VersionManager {
    struct VersionManagerState {
        bytes32 currentHash;
        bytes32 pendingHash;
        uint256 pendingHashActivationTime;
    }

    function initialize(VersionManagerState storage _v, bytes32 _currentHash) internal {
        _v.currentHash = _currentHash;
    }

    function _activeStateHash(VersionManagerState storage _v, uint256 _currentTime) internal view returns (bytes32) {
        if (_v.pendingHashActivationTime == 0) {
            return _v.currentHash;
        }

        if (_currentTime < _v.pendingHashActivationTime) {
            return _v.currentHash;
        }

        return _v.pendingHash;
    }

    function verifyHashAgainstActiveState(VersionManagerState storage _v, bytes32 _hash, uint256 _currentTime)
        internal
        view
        returns (bool)
    {
        return _hash == _activeStateHash(_v, _currentTime);
    }

    function verifyHashAgainstLatestState(VersionManagerState storage _v, bytes32 _hash) internal view returns (bool) {
        if (_v.pendingHash != bytes32(0)) {
            return _hash == _v.pendingHash;
        }

        return _hash == _v.currentHash;
    }

    function setPendingState(VersionManagerState storage _v, bytes32 _hash, uint256 _currentTime) internal {
        if (_v.pendingHashActivationTime != 0 && _currentTime >= _v.pendingHashActivationTime) {
            _v.currentHash = _v.pendingHash;
        }
        _v.pendingHash = _hash;
        delete _v.pendingHashActivationTime;
    }

    function setPendingStateForActivation(VersionManagerState storage _v, uint256 _activationTime) internal {
        if (_v.pendingHashActivationTime != 0) {
            // Existing pending state is already scheduled for activation
            return;
        }

        _v.pendingHashActivationTime = _activationTime;
    }
}
