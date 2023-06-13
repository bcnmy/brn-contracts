// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

library VersionManager {
    event VersionManagerSnapshot(bytes32 indexed activeState, bytes32 indexed pendingState);
    event VersionManagerPendingStateSetForActivation(uint256 indexed activationTime, bytes32 indexed pendingState);

    struct VersionManagerState {
        bytes32 slot1;
        bytes32 slot2;
        uint256 pendingHashActivationTime;
    }

    function initialize(VersionManagerState storage _v, bytes32 _currentHash) internal {
        _v.slot1 = _currentHash;
    }

    function activeStateHash(VersionManagerState storage _v, uint256 _currentTime) internal view returns (bytes32) {
        if (_v.pendingHashActivationTime == 0) {
            return _v.slot1;
        }

        if (_currentTime < _v.pendingHashActivationTime) {
            return _v.slot1;
        }

        return _v.slot2;
    }

    function pendingStateHash(VersionManagerState storage _v) internal view returns (bytes32) {
        return _v.slot2 == bytes32(0) ? _v.slot1 : _v.slot2;
    }

    function verifyHashAgainstActiveState(VersionManagerState storage _v, bytes32 _hash, uint256 _currentTime)
        internal
        view
        returns (bool)
    {
        return _hash == activeStateHash(_v, _currentTime);
    }

    function verifyHashAgainstLatestState(VersionManagerState storage _v, bytes32 _hash) internal view returns (bool) {
        return _hash == pendingStateHash(_v);
    }

    function setPendingState(VersionManagerState storage _v, bytes32 _hash, uint256 _currentTime) internal {
        if (_v.pendingHashActivationTime != 0 && _currentTime >= _v.pendingHashActivationTime) {
            _v.slot1 = _v.slot2;
        }
        _v.slot2 = _hash;
        delete _v.pendingHashActivationTime;

        emit VersionManagerSnapshot(activeStateHash(_v, _currentTime), pendingStateHash(_v));
    }

    function setPendingStateForActivation(VersionManagerState storage _v, uint256 _activationTime) internal {
        if (_v.pendingHashActivationTime != 0) {
            // Existing pending state is already scheduled for activation
            return;
        }

        _v.pendingHashActivationTime = _activationTime;
        emit VersionManagerPendingStateSetForActivation(_activationTime, pendingStateHash(_v));
    }
}
