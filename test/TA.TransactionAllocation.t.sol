// SPDX-License-Identifier: MIT

pragma solidity 0.8.17;

import "./base/TATestBase.t.sol";
import "./mocks/TransactionMock.sol";
import "./mocks/interfaces/ITransactionMockEventsErrors.sol";
import "src/structs/TAStructs.sol";
import "src/transaction-allocator/common/TAConstants.sol";
import "src/transaction-allocator/modules/transaction-allocation/interfaces/ITATransactionAllocationEventsErrors.sol";
import "src/transaction-allocator/common/interfaces/ITAHelpers.sol";

contract TATransactionAllocationTest is
    TATestBase,
    TAConstants,
    ITATransactionAllocationEventsErrors,
    ITAHelpers,
    ITransactionMockEventsErrors
{
    uint256 private _postRegistrationSnapshotId;
    uint256 private constant _initialStakeAmount = MINIMUM_STAKE_AMOUNT;
    TransactionMock private tm;
    ForwardRequest[] private txns;

    function setUp() public override {
        if (_postRegistrationSnapshotId != 0) {
            return;
        }

        super.setUp();

        // Register all Relayers
        for (uint256 i = 0; i < relayerCount; i++) {
            uint256 stake = _initialStakeAmount;
            string memory endpoint = "test";
            address relayerAddress = relayerMainAddress[i];

            vm.startPrank(relayerAddress);
            ta.register(ta.getStakeArray(), stake, relayerAccountAddresses[relayerAddress], endpoint);
            vm.stopPrank();
        }

        tm = new TransactionMock();

        for (uint256 i = 0; i < 10; i++) {
            txns.push(
                ForwardRequest({
                    to: address(tm),
                    data: abi.encodeWithSelector(tm.mockUpdate.selector, i),
                    gasLimit: 10 ** 6
                })
            );
        }

        _postRegistrationSnapshotId = vm.snapshot();
    }

    function _preTestSnapshotId() internal view virtual override returns (uint256) {
        return _postRegistrationSnapshotId;
    }

    function _deDuplicate(uint256[] memory _arr) internal pure returns (uint256[] memory) {
        uint256[] memory _temp = new uint256[](_arr.length);
        uint256 _tempIndex = 0;
        for (uint256 i = 0; i < _arr.length; i++) {
            bool _found = false;
            for (uint256 j = 0; j < _tempIndex; j++) {
                if (_arr[i] == _temp[j]) {
                    _found = true;
                    break;
                }
            }
            if (!_found) {
                _temp[_tempIndex++] = _arr[i];
            }
        }
        uint256[] memory _result = new uint256[](_tempIndex);
        for (uint256 i = 0; i < _tempIndex; i++) {
            _result[i] = _temp[i];
        }
        return _result;
    }

    function testTransactionExecution() external atSnapshot {
        uint256 executionCount = 0;
        uint16[] memory cdf = ta.getCdf();
        for (uint256 i = 0; i < relayerMainAddress.length; i++) {
            (
                ForwardRequest[] memory allotedTransactions,
                uint256[] memory relayerGenerationIteration,
                uint256 selectedRelayerCdfIndex
            ) = ta.allocateTransaction(
                AllocateTransactionParams({relayer: relayerMainAddress[i], requests: txns, cdf: cdf})
            );

            if (allotedTransactions.length == 0) {
                continue;
            }

            vm.startPrank(relayerAccountAddresses[relayerMainAddress[i]][0]);
            (bool[] memory successes, bytes[] memory returndatas) =
                ta.execute(allotedTransactions, cdf, _deDuplicate(relayerGenerationIteration), selectedRelayerCdfIndex);
            vm.stopPrank();

            executionCount += allotedTransactions.length;

            assertEq(ta.attendance(block.number / ta.blocksPerWindow(), relayerMainAddress[i]), true);
            assertEq(successes.length, allotedTransactions.length);
            assertEq(returndatas.length, allotedTransactions.length);

            for (uint256 j = 0; j < allotedTransactions.length; j++) {
                assertEq(successes[j], true);
                assertEq(returndatas[j], abi.encode(true));
            }
        }

        assertEq(executionCount, txns.length);
    }

    function testCannotExecuteTransactionWithInvalidCdf() external atSnapshot {
        uint16[] memory cdf = ta.getCdf();
        uint16[] memory cdf2 = ta.getCdf();
        // Corrupt the CDF
        cdf2[0] += 1;

        for (uint256 i = 0; i < relayerMainAddress.length; i++) {
            (
                ForwardRequest[] memory allotedTransactions,
                uint256[] memory relayerGenerationIteration,
                uint256 selectedRelayerCdfIndex
            ) = ta.allocateTransaction(
                AllocateTransactionParams({relayer: relayerMainAddress[i], requests: txns, cdf: cdf})
            );

            if (allotedTransactions.length == 0) {
                continue;
            }

            vm.startPrank(relayerAccountAddresses[relayerMainAddress[i]][0]);
            vm.expectRevert(InvalidCdfArrayHash.selector);
            ta.execute(allotedTransactions, cdf2, _deDuplicate(relayerGenerationIteration), selectedRelayerCdfIndex + 1);
            assertEq(ta.attendance(block.number / ta.blocksPerWindow(), relayerMainAddress[i]), false);
            vm.stopPrank();
        }
    }

    function testCannotExecuteTransactionFromUnselectedRelayer() external atSnapshot {
        uint16[] memory cdf = ta.getCdf();

        for (uint256 i = 0; i < relayerMainAddress.length; i++) {
            (
                ForwardRequest[] memory allotedTransactions,
                uint256[] memory relayerGenerationIteration,
                uint256 selectedRelayerCdfIndex
            ) = ta.allocateTransaction(
                AllocateTransactionParams({relayer: relayerMainAddress[i], requests: txns, cdf: cdf})
            );

            if (allotedTransactions.length == 0) {
                continue;
            }

            vm.startPrank(relayerAccountAddresses[relayerMainAddress[(i + 1) % relayerMainAddress.length]][0]);
            vm.expectRevert(InvalidRelayerWindow.selector);
            ta.execute(allotedTransactions, cdf, _deDuplicate(relayerGenerationIteration), selectedRelayerCdfIndex + 1);
            assertEq(ta.attendance(block.number / ta.blocksPerWindow(), relayerMainAddress[i]), false);
            vm.stopPrank();
        }
    }

    function testCannotExecuteTransactionFromSelectedButNonAllotedRelayer() external atSnapshot {
        uint16[] memory cdf = ta.getCdf();
        (address[] memory selectedRelayers,) = ta.allocateRelayers(cdf);
        bool testRun = false;

        for (uint256 i = 0; i < relayerMainAddress.length; i++) {
            (
                ForwardRequest[] memory allotedTransactions,
                uint256[] memory relayerGenerationIteration,
                uint256 selectedRelayerCdfIndex
            ) = ta.allocateTransaction(
                AllocateTransactionParams({relayer: relayerMainAddress[i], requests: txns, cdf: cdf})
            );

            if (allotedTransactions.length == 0) {
                continue;
            }

            if (selectedRelayers[0] == relayerMainAddress[i]) {
                continue;
            }

            testRun = true;

            vm.startPrank(relayerAccountAddresses[selectedRelayers[0]][0]);
            vm.expectRevert(InvalidRelayerWindow.selector);
            ta.execute(allotedTransactions, cdf, _deDuplicate(relayerGenerationIteration), selectedRelayerCdfIndex + 1);
            vm.stopPrank();
        }

        assertEq(testRun, true);
    }
}