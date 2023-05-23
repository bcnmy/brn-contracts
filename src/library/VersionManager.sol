// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import "src/transaction-allocator/common/TATypes.sol";

library VersionManager {
    struct VersionManagerState {
        bytes32 currentHash;
        bytes32 nextHash;
        bytes32 pendingHash;
        WindowIndex nextHashActivationWindowIndex;
    }

    function initialize(VersionManagerState storage _v, bytes32 _currentHash) internal {
        _v.nextHash = _currentHash;
    }

    function _activeStateHash(VersionManagerState storage _v, WindowIndex _currentWindowIndex)
        internal
        view
        returns (bytes32)
    {
        return _currentWindowIndex >= _v.nextHashActivationWindowIndex ? _v.nextHash : _v.currentHash;
    }

    function verifyHashAgainstActiveState(
        VersionManagerState storage _v,
        bytes32 _hash,
        WindowIndex _currentWindowIndex
    ) internal view returns (bool) {
        return _hash == _activeStateHash(_v, _currentWindowIndex);
    }

    function verifyHashAgainstPendingState(VersionManagerState storage _v, bytes32 _hash)
        internal
        view
        returns (bool)
    {
        if (_v.pendingHash != bytes32(0)) {
            return _hash == _v.pendingHash;
        }

        if (_v.nextHash != bytes32(0)) {
            return _hash == _v.nextHash;
        }

        return _hash == _v.currentHash;
    }

    function setPendingState(VersionManagerState storage _v, bytes32 _hash) internal {
        _v.pendingHash = _hash;
    }

    function setPendingStateForActivation(VersionManagerState storage _v, WindowIndex _activationWindow) internal {
        _v.currentHash = _v.nextHash;
        _v.nextHash = _v.pendingHash;
        _v.nextHashActivationWindowIndex = _activationWindow;
        _v.pendingHash = bytes32(0);
    }
}
