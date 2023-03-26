// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import "./base/TATestBase.t.sol";
import "src/mocks/ApplicationMock.sol";
import "src/mocks/interfaces/IApplicationMockEventsErrors.sol";
import "src/transaction-allocator/common/TAConstants.sol";
import "src/transaction-allocator/modules/transaction-allocation/interfaces/ITATransactionAllocationEventsErrors.sol";
import "src/transaction-allocator/common/interfaces/ITAHelpers.sol";

contract TATransactionAllocationTest is
    TATestBase,
    ITATransactionAllocationEventsErrors,
    ITAHelpers,
    IApplicationMockEventsErrors
{
    uint256 constant initialApplicationFunds = 10 ether;

    uint256 private _postRegistrationSnapshotId;
    uint256 private constant _initialStakeAmount = MINIMUM_STAKE_AMOUNT;
    ApplicationMock private tm;
    Transaction[] private txns;

    function setUp() public override {
        if (_postRegistrationSnapshotId != 0) {
            return;
        }

        if (tx.gasprice == 0) {
            fail("Gas Price is 0. Please set it to 1 gwei or more.");
        }

        super.setUp();

        // Register all Relayers
        for (uint256 i = 0; i < relayerCount; i++) {
            uint256 stake = _initialStakeAmount;
            string memory endpoint = "test";
            uint256 delegatorPoolPremiumShare = 100;
            RelayerAddress relayerAddress = relayerMainAddress[i];

            _startPrankRA(relayerAddress);
            bico.approve(address(ta), stake);
            ta.register(
                ta.getStakeArray(),
                ta.getDelegationArray(),
                stake,
                relayerAccountAddresses[relayerAddress],
                endpoint,
                delegatorPoolPremiumShare
            );
            vm.stopPrank();
        }

        tm = new ApplicationMock();
        vm.deal(address(tm), initialApplicationFunds);
        vm.label(address(tm), "ApplicationMock");

        for (uint256 i = 0; i < 10; i++) {
            txns.push(
                Transaction({
                    to: tm,
                    data: abi.encodeWithSelector(tm.incrementA.selector, i + 1),
                    fixedGas: 21000,
                    prePaymentGasLimit: 10000,
                    gasLimit: 10 ** 6,
                    refundGasLimit: 10 ** 5
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

    function _getRelayerAssignedToTx(Transaction memory _tx, uint16[] memory _cdf, uint256 _currentCdfLogIndex)
        internal
        returns (RelayerAddress, uint256[] memory, uint256)
    {
        Transaction[] memory txns_ = new Transaction[](1);
        txns_[0] = _tx;

        for (uint256 i = 0; i < relayerMainAddress.length; i++) {
            RelayerAddress relayerAddress = relayerMainAddress[i];
            (
                Transaction[] memory allotedTransactions,
                uint256[] memory relayerGenerationIteration,
                uint256 selectedRelayerCdfIndex
            ) = ta.allocateTransaction(
                AllocateTransactionParams({
                    relayerAddress: relayerAddress,
                    requests: txns_,
                    cdf: _cdf,
                    currentCdfLogIndex: _currentCdfLogIndex
                })
            );

            if (allotedTransactions.length == 1) {
                return (relayerAddress, relayerGenerationIteration, selectedRelayerCdfIndex);
            }
        }

        fail("No relayer found");
        return (RelayerAddress.wrap(address(0)), new uint256[](0), 0);
    }

    function testTransactionExecution() external atSnapshot {
        vm.roll(block.number + RELAYER_CONFIGURATION_UPDATE_DELAY_IN_WINDOWS * deployParams.blocksPerWindow);
        console2.log("gasprice", tx.gasprice);

        uint256 executionCount = 0;
        uint16[] memory cdf = ta.getCdfArray();
        for (uint256 i = 0; i < relayerMainAddress.length; i++) {
            RelayerAddress relayerAddress = relayerMainAddress[i];
            (
                Transaction[] memory allotedTransactions,
                uint256[] memory relayerGenerationIteration,
                uint256 selectedRelayerCdfIndex
            ) = ta.allocateTransaction(
                AllocateTransactionParams({
                    relayerAddress: relayerAddress,
                    requests: txns,
                    cdf: cdf,
                    currentCdfLogIndex: 1
                })
            );

            if (allotedTransactions.length == 0) {
                continue;
            }

            _startPrankRAA(relayerAccountAddresses[relayerMainAddress[i]][0]);
            (bool[] memory successes, bytes[] memory returndatas) = ta.execute(
                allotedTransactions, cdf, _deDuplicate(relayerGenerationIteration), selectedRelayerCdfIndex, 1, 0
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
        assertEq(tm.getA(), 55);
    }

    function testCannotExecuteTransactionWithInvalidCdf() external atSnapshot {
        vm.roll(block.number + RELAYER_CONFIGURATION_UPDATE_DELAY_IN_WINDOWS * deployParams.blocksPerWindow);

        uint16[] memory cdf = ta.getCdfArray();
        uint16[] memory cdf2 = ta.getCdfArray();
        // Corrupt the CDF
        cdf2[0] += 1;

        for (uint256 i = 0; i < relayerMainAddress.length; i++) {
            RelayerAddress relayerAddress = relayerMainAddress[i];
            (
                Transaction[] memory allotedTransactions,
                uint256[] memory relayerGenerationIteration,
                uint256 selectedRelayerCdfIndex
            ) = ta.allocateTransaction(
                AllocateTransactionParams({
                    relayerAddress: relayerAddress,
                    requests: txns,
                    cdf: cdf,
                    currentCdfLogIndex: 1
                })
            );

            if (allotedTransactions.length == 0) {
                continue;
            }

            _startPrankRAA(relayerAccountAddresses[relayerMainAddress[i]][0]);
            vm.expectRevert(InvalidCdfArrayHash.selector);
            ta.execute(
                allotedTransactions, cdf2, _deDuplicate(relayerGenerationIteration), selectedRelayerCdfIndex + 1, 1, 0
            );
            assertEq(ta.attendance(block.number / ta.blocksPerWindow(), relayerAddress), false);
            vm.stopPrank();
        }
    }

    function testCannotExecuteTransactionFromUnselectedRelayer() external atSnapshot {
        vm.roll(block.number + RELAYER_CONFIGURATION_UPDATE_DELAY_IN_WINDOWS * deployParams.blocksPerWindow);
        uint16[] memory cdf = ta.getCdfArray();

        for (uint256 i = 0; i < relayerMainAddress.length; i++) {
            RelayerAddress relayerAddress = relayerMainAddress[i];
            (
                Transaction[] memory allotedTransactions,
                uint256[] memory relayerGenerationIteration,
                uint256 selectedRelayerCdfIndex
            ) = ta.allocateTransaction(
                AllocateTransactionParams({
                    relayerAddress: relayerAddress,
                    requests: txns,
                    cdf: cdf,
                    currentCdfLogIndex: 1
                })
            );

            if (allotedTransactions.length == 0) {
                continue;
            }

            _startPrankRAA(relayerAccountAddresses[relayerMainAddress[(i + 1) % relayerMainAddress.length]][0]);
            vm.expectRevert(RelayerIndexDoesNotPointToSelectedCdfInterval.selector);
            ta.execute(
                allotedTransactions, cdf, _deDuplicate(relayerGenerationIteration), selectedRelayerCdfIndex + 1, 1, 0
            );
            assertEq(ta.attendance(block.number / ta.blocksPerWindow(), relayerAddress), false);
            vm.stopPrank();
        }
    }

    function testCannotExecuteTransactionFromSelectedButNonAllotedRelayer() external atSnapshot {
        vm.roll(block.number + RELAYER_CONFIGURATION_UPDATE_DELAY_IN_WINDOWS * deployParams.blocksPerWindow);

        uint16[] memory cdf = ta.getCdfArray();
        (RelayerAddress[] memory selectedRelayers,) = ta.allocateRelayers(cdf, 1);
        bool testRun = false;

        for (uint256 i = 0; i < relayerMainAddress.length; i++) {
            RelayerAddress relayerAddress = relayerMainAddress[i];
            (
                Transaction[] memory allotedTransactions,
                uint256[] memory relayerGenerationIteration,
                uint256 selectedRelayerCdfIndex
            ) = ta.allocateTransaction(
                AllocateTransactionParams({
                    relayerAddress: relayerAddress,
                    requests: txns,
                    cdf: cdf,
                    currentCdfLogIndex: 1
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
            vm.expectRevert(RelayerIndexDoesNotPointToSelectedCdfInterval.selector);
            ta.execute(
                allotedTransactions, cdf, _deDuplicate(relayerGenerationIteration), selectedRelayerCdfIndex + 1, 1, 0
            );
            vm.stopPrank();
        }

        assertEq(testRun, true);
    }
}
