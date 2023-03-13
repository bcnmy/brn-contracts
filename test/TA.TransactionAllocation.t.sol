// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import "./base/TATestBase.t.sol";
import "src/mocks/TransactionMock.sol";
import "src/mocks/interfaces/ITransactionMockEventsErrors.sol";
import "src/transaction-allocator/common/TAConstants.sol";
import "src/transaction-allocator/modules/transaction-allocation/interfaces/ITATransactionAllocationEventsErrors.sol";
import "src/transaction-allocator/common/interfaces/ITAHelpers.sol";

// TODO: Add tests related to delayed CDF Updation

contract TATransactionAllocationTest is
    TATestBase,
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
            RelayerAddress relayerAddress = relayerMainAddress[i];

            _startPrankRA(relayerAddress);
            bico.approve(address(ta), stake);
            ta.register(
                ta.getStakeArray(), ta.getDelegationArray(), stake, relayerAccountAddresses[relayerAddress], endpoint
            );
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
        vm.roll(block.number + CDF_UPDATE_DELAY_IN_WINDOWS * deployParams.blocksPerWindow);

        uint256 executionCount = 0;
        uint16[] memory cdf = ta.getCdfArray();
        for (uint256 i = 0; i < relayerMainAddress.length; i++) {
            RelayerAddress relayerAddress = relayerMainAddress[i];
            (
                ForwardRequest[] memory allotedTransactions,
                uint256[] memory relayerGenerationIteration,
                uint256 selectedRelayerCdfIndex
            ) = ta.allocateTransaction(
                AllocateTransactionParams({
                    relayerAddress: relayerAddress,
                    requests: txns,
                    cdf: cdf,
                    currentCdfLogIndex: 0
                })
            );

            if (allotedTransactions.length == 0) {
                continue;
            }

            _startPrankRAA(relayerAccountAddresses[relayerMainAddress[i]][0]);
            (bool[] memory successes, bytes[] memory returndatas) = ta.execute(
                allotedTransactions, cdf, _deDuplicate(relayerGenerationIteration), selectedRelayerCdfIndex, 0
            );
            vm.stopPrank();

            executionCount += allotedTransactions.length;

            assertEq(ta.attendance(block.number / ta.blocksPerWindow(), relayerAddress), true);
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
        vm.roll(block.number + CDF_UPDATE_DELAY_IN_WINDOWS * deployParams.blocksPerWindow);

        uint16[] memory cdf = ta.getCdfArray();
        uint16[] memory cdf2 = ta.getCdfArray();
        // Corrupt the CDF
        cdf2[0] += 1;

        for (uint256 i = 0; i < relayerMainAddress.length; i++) {
            RelayerAddress relayerAddress = relayerMainAddress[i];
            (
                ForwardRequest[] memory allotedTransactions,
                uint256[] memory relayerGenerationIteration,
                uint256 selectedRelayerCdfIndex
            ) = ta.allocateTransaction(
                AllocateTransactionParams({
                    relayerAddress: relayerAddress,
                    requests: txns,
                    cdf: cdf,
                    currentCdfLogIndex: 0
                })
            );

            if (allotedTransactions.length == 0) {
                continue;
            }

            _startPrankRAA(relayerAccountAddresses[relayerMainAddress[i]][0]);
            vm.expectRevert(InvalidCdfArrayHash.selector);
            ta.execute(
                allotedTransactions, cdf2, _deDuplicate(relayerGenerationIteration), selectedRelayerCdfIndex + 1, 0
            );
            assertEq(ta.attendance(block.number / ta.blocksPerWindow(), relayerAddress), false);
            vm.stopPrank();
        }
    }

    function testCannotExecuteTransactionFromUnselectedRelayer() external atSnapshot {
        vm.roll(block.number + CDF_UPDATE_DELAY_IN_WINDOWS * deployParams.blocksPerWindow);
        uint16[] memory cdf = ta.getCdfArray();

        for (uint256 i = 0; i < relayerMainAddress.length; i++) {
            RelayerAddress relayerAddress = relayerMainAddress[i];
            (
                ForwardRequest[] memory allotedTransactions,
                uint256[] memory relayerGenerationIteration,
                uint256 selectedRelayerCdfIndex
            ) = ta.allocateTransaction(
                AllocateTransactionParams({
                    relayerAddress: relayerAddress,
                    requests: txns,
                    cdf: cdf,
                    currentCdfLogIndex: 0
                })
            );

            if (allotedTransactions.length == 0) {
                continue;
            }

            _startPrankRAA(relayerAccountAddresses[relayerMainAddress[(i + 1) % relayerMainAddress.length]][0]);
            vm.expectRevert(InvalidRelayerWindow.selector);
            ta.execute(
                allotedTransactions, cdf, _deDuplicate(relayerGenerationIteration), selectedRelayerCdfIndex + 1, 0
            );
            assertEq(ta.attendance(block.number / ta.blocksPerWindow(), relayerAddress), false);
            vm.stopPrank();
        }
    }

    function testCannotExecuteTransactionFromSelectedButNonAllotedRelayer() external atSnapshot {
        vm.roll(block.number + CDF_UPDATE_DELAY_IN_WINDOWS * deployParams.blocksPerWindow);

        uint16[] memory cdf = ta.getCdfArray();
        (RelayerAddress[] memory selectedRelayers,) = ta.allocateRelayers(cdf, 0);
        bool testRun = false;

        for (uint256 i = 0; i < relayerMainAddress.length; i++) {
            RelayerAddress relayerAddress = relayerMainAddress[i];
            (
                ForwardRequest[] memory allotedTransactions,
                uint256[] memory relayerGenerationIteration,
                uint256 selectedRelayerCdfIndex
            ) = ta.allocateTransaction(
                AllocateTransactionParams({
                    relayerAddress: relayerAddress,
                    requests: txns,
                    cdf: cdf,
                    currentCdfLogIndex: 0
                })
            );

            if (allotedTransactions.length == 0) {
                continue;
            }

            if (selectedRelayers[0] == relayerAddress) {
                continue;
            }

            testRun = true;

            _startPrankRAA(relayerAccountAddresses[selectedRelayers[0]][0]);
            vm.expectRevert(InvalidRelayerWindow.selector);
            ta.execute(
                allotedTransactions, cdf, _deDuplicate(relayerGenerationIteration), selectedRelayerCdfIndex + 1, 0
            );
            vm.stopPrank();
        }

        assertEq(testRun, true);
    }
}
