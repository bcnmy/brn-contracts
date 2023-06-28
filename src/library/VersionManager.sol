// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

/// @title VersionManager
/// @dev A Data Structure for applying delayed updates to a stored state, the state being a single bytes32 value.
/// The state active at the current point of time is the "active state", while any state that has been set but not yet activated is the "latest state".
/// In the absence of any pending state, the active state is the latest state.
/// The active state is generally used to perform any validations in the current context, while the latest state is used to accumulate changes to the state.
/// Time is assumed to be any non-decreasing value, like block.timestamp.
library VersionManager {
    /// @dev Emitted when a new latest state is set for activation.
    /// @param activationTime The time at which the latest state will become the active state.
    /// @param latestState The latest state that will become the active state.
    event VersionManagerLatestStateSetForActivation(uint256 indexed activationTime, bytes32 indexed latestState);

    /// @dev The internal state of the VersionManager.
    /// @custom:member slot1 The first storage slot of the VersionManager. Stores the state which entered the VersionManager "earlier"
    /// @custom:member slot2 The second storage slot of the VersionManager. Stores the state which entered the VersionManager "later"
    /// @custom:member pendingHashActivationTime The time at which the latest state will become the active state, used to decide which of the two slots is the active state and latest state
    struct VersionManagerState {
        bytes32 slot1;
        bytes32 slot2;
        uint256 pendingHashActivationTime;
    }

    /// @dev Initializes the VersionManager with a given state to be set as the active state.
    function initialize(VersionManagerState storage _v, bytes32 _currentHash) internal {
        _v.slot1 = _currentHash;
        _v.slot2 = _currentHash;
    }

    /// @dev Returns the active state hash.
    /// @param _v Version Manager Internal State
    /// @param _currentTime The time at which the active state is being queried.
    /// @return The active state hash.
    function activeStateHash(VersionManagerState storage _v, uint256 _currentTime) internal view returns (bytes32) {
        if (_v.pendingHashActivationTime == 0) {
            return _v.slot1;
        }

        if (_currentTime < _v.pendingHashActivationTime) {
            return _v.slot1;
        }

        return _v.slot2;
    }

    /// @dev Returns the latest state hash.
    /// @param _v Version Manager Internal State
    /// @return The latest state hash.
    function latestStateHash(VersionManagerState storage _v) internal view returns (bytes32) {
        return _v.slot2 == bytes32(0) ? _v.slot1 : _v.slot2;
    }

    /// @dev Returns true if the given hash matches the active state hash else false.
    /// @param _v Version Manager Internal State
    /// @param _hash The hash to check against the active state.
    /// @param _currentTime The time at which the active state is being queried.
    /// @return True if the given hash matches the active state hash else false.
    function verifyHashAgainstActiveState(VersionManagerState storage _v, bytes32 _hash, uint256 _currentTime)
        internal
        view
        returns (bool)
    {
        return _hash == activeStateHash(_v, _currentTime);
    }

    /// @dev Returns true if the given hash matches the latest state hash else false.
    /// @param _v Version Manager Internal State
    /// @param _hash The hash to check against the latest state.
    /// @return True if the given hash matches the latest state hash else false.
    function verifyHashAgainstLatestState(VersionManagerState storage _v, bytes32 _hash) internal view returns (bool) {
        return _hash == latestStateHash(_v);
    }

    /// @dev Sets the latest state hash, but does not activate it immediately
    /// @param _v Version Manager Internal State
    /// @param _hash The hash to set as the latest state
    /// @param _currentTime The time at which the latest state is being set
    function setLatestState(VersionManagerState storage _v, bytes32 _hash, uint256 _currentTime) internal {
        // If the active state is in slot2, then move it to slot1
        if (_v.pendingHashActivationTime != 0 && _currentTime >= _v.pendingHashActivationTime) {
            _v.slot1 = _v.slot2;
        }

        // Set the latest state in slot2 (assuming slot1 is the active state)
        _v.slot2 = _hash;

        // If pendingHashActivationTime = 0, activeState = slot1. Refer to implementation of activeStateHash()
        delete _v.pendingHashActivationTime;
    }

    /// @dev Schedule the latest state to be activated at a given time. If the latest state is already scheduled for activation, this function does nothing.
    /// @param _v Version Manager Internal State
    /// @param _activationTime The time at which the latest state will become the active state.
    function setLatestStateForActivation(VersionManagerState storage _v, uint256 _activationTime) internal {
        if (_v.pendingHashActivationTime != 0) {
            // Existing pending state is already scheduled for activation
            return;
        }

        _v.pendingHashActivationTime = _activationTime;
        emit VersionManagerLatestStateSetForActivation(_activationTime, latestStateHash(_v));
    }
}
