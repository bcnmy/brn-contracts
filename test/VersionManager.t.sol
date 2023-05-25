// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import "forge-std/Test.sol";

import "src/library/VersionManager.sol";

contract VersionManagerTest is Test {
    using VersionManager for VersionManager.VersionManagerState;

    VersionManager.VersionManagerState state;
    uint256 versionsLength = 10;
    bytes32[] versions;

    function setUp() external {
        for (uint256 i = 0; i < versionsLength; i++) {
            versions.push(keccak256(abi.encodePacked(i)));
        }

        state.initialize(versions[0]);
    }

    function testVersionManager() external {
        uint256 currentTime = 10;
        assertEq(state.verifyHashAgainstActiveState(versions[0], currentTime), true);
        assertEq(state.verifyHashAgainstLatestState(versions[0]), true);

        state.setPendingState(versions[1], currentTime);
        assertEq(state.verifyHashAgainstActiveState(versions[0], currentTime), true);
        assertEq(state.verifyHashAgainstLatestState(versions[1]), true);

        state.setPendingStateForActivation(currentTime + 1);
        assertEq(state.verifyHashAgainstActiveState(versions[0], currentTime), true);
        assertEq(state.verifyHashAgainstLatestState(versions[1]), true);

        currentTime += 1;
        assertEq(state.verifyHashAgainstActiveState(versions[1], currentTime), true);
        assertEq(state.verifyHashAgainstLatestState(versions[1]), true);

        currentTime += 20;
        assertEq(state.verifyHashAgainstActiveState(versions[1], currentTime), true);
        assertEq(state.verifyHashAgainstLatestState(versions[1]), true);

        state.setPendingState(versions[2], currentTime);
        assertEq(state.verifyHashAgainstActiveState(versions[1], currentTime), true);
        assertEq(state.verifyHashAgainstLatestState(versions[2]), true);

        state.setPendingState(versions[3], currentTime);
        assertEq(state.verifyHashAgainstActiveState(versions[1], currentTime), true);
        assertEq(state.verifyHashAgainstLatestState(versions[3]), true);

        currentTime += 10;
        assertEq(state.verifyHashAgainstActiveState(versions[1], currentTime), true);
        assertEq(state.verifyHashAgainstLatestState(versions[3]), true);

        state.setPendingState(versions[4], currentTime);
        assertEq(state.verifyHashAgainstActiveState(versions[1], currentTime), true);
        assertEq(state.verifyHashAgainstLatestState(versions[4]), true);

        state.setPendingStateForActivation(currentTime + 5);
        currentTime += 3;
        assertEq(state.verifyHashAgainstActiveState(versions[1], currentTime), true);
        assertEq(state.verifyHashAgainstLatestState(versions[4]), true);

        currentTime += 1;
        assertEq(state.verifyHashAgainstActiveState(versions[1], currentTime), true);
        assertEq(state.verifyHashAgainstLatestState(versions[4]), true);

        currentTime += 1;
        assertEq(state.verifyHashAgainstActiveState(versions[4], currentTime), true);
        assertEq(state.verifyHashAgainstLatestState(versions[4]), true);
    }
}
