// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import "src/mock/minimal-application/MinimalApplication2.sol";
import "src/utils/Guards.sol";
import "test/base/TATestBase.sol";
import "ta-transaction-allocation/interfaces/ITATransactionAllocation.sol";

contract InternalInvocationTest is TATestBase, ITAHelpers, ITATransactionAllocationEventsErrors, Guards {
    bytes[] txns;
    mapping(bytes4 selector => bool) testExecuted;
    mapping(bytes4 selector => bool) selectorExcludedFromTests;

    function setUp() public override {
        if (tx.gasprice == 0) {
            fail("Gas Price is 0. Please set it to 1 gwei or more.");
        }

        super.setUp();

        RelayerStateManager.RelayerState memory currentState = latestRelayerState;
        _registerAllNonFoundationRelayers();
        _moveForwardToNextEpoch();
        _sendEmptyTransaction(currentState);
        _moveForwardByWindows(deployParams.relayerStateUpdateDelayInWindows);

        // Replace the bytecode for minimal application with MinimalApplication2 to change the hash function
        vm.etch(address(app), address(new MinimalApplication2()).code);
    }

    function _allocateTransactions(
        RelayerAddress _relayerAddress,
        bytes[] memory _txns,
        RelayerStateManager.RelayerState memory _relayerState
    ) internal view override returns (bytes[] memory, uint256, uint256) {
        return ta.allocateMinimalApplicationTransaction(_relayerAddress, _txns, _relayerState);
    }

    function _generateSelectors(string memory _contractName) internal returns (bytes4[] memory selectors) {
        string[] memory cmd = new string[](4);
        cmd[0] = "npx";
        cmd[1] = "ts-node";
        cmd[2] = "hardhat/scripts/generateSelectors.ts";
        cmd[3] = _contractName;
        bytes memory res = vm.ffi(cmd);
        selectors = abi.decode(res, (bytes4[]));
    }

    function _executeTxnTest(bytes calldata _tx) external {
        bytes[] memory transactions = new bytes[](1);
        transactions[0] = _tx;

        testExecuted[bytes4(_tx[:4])] = true;

        (RelayerAddress relayerAddress, uint256 relayerGenerationIterations, uint256 selectedRelayerCdfIndex) =
            _getRelayerAssignedToTx(transactions[0]);

        _prankRA(relayerAddress);
        vm.expectRevert(
            abi.encodeWithSelector(TransactionExecutionFailed.selector, 0, abi.encodeWithSelector(NoSelfCall.selector))
        );
        ta.execute(
            ITATransactionAllocation.ExecuteParams({
                reqs: transactions,
                forwardedNativeAmounts: new uint256[](1),
                relayerIndex: selectedRelayerCdfIndex,
                relayerGenerationIterationBitmap: relayerGenerationIterations,
                activeState: latestRelayerState,
                latestState: latestRelayerState
            })
        );
    }

    function testShouldPreventInvocationOfCoreFunctionsViaTransactionExecutionFlowInRelayerManagementModule()
        external
    {
        txns = [
            abi.encodeCall(
                ta.register,
                (
                    latestRelayerState,
                    initialRelayerStake[relayerMainAddress[0]],
                    relayerAccountAddresses[relayerMainAddress[0]],
                    endpoint,
                    delegatorPoolPremiumShare
                )
            ),
            abi.encodeCall(ta.unregister, (latestRelayerState, 0)),
            abi.encodeCall(ta.withdraw, (relayerAccountAddresses[relayerMainAddress[0]])),
            abi.encodeCall(ta.unjailAndReenter, (latestRelayerState, initialRelayerStake[relayerMainAddress[0]])),
            abi.encodeCall(
                ta.setRelayerAccountsStatus,
                (
                    relayerAccountAddresses[relayerMainAddress[0]],
                    new bool[](relayerAccountAddresses[relayerMainAddress[0]].length)
                )
            ),
            abi.encodeCall(ta.claimProtocolReward, ()),
            abi.encodeCall(ta.relayerClaimableProtocolRewards, (relayerMainAddress[0])),
            abi.encodeCall(ta.protocolRewardRate, ()),
            abi.encodeCall(ta.relayerCount, ()),
            abi.encodeCall(ta.totalStake, ()),
            abi.encodeCall(ta.relayerInfo, (relayerMainAddress[0])),
            abi.encodeCall(
                ta.relayerInfo_isAccount, (relayerMainAddress[0], relayerAccountAddresses[relayerMainAddress[0]][0])
            ),
            abi.encodeCall(ta.relayersPerWindow, ()),
            abi.encodeCall(ta.blocksPerWindow, ()),
            abi.encodeCall(ta.bondTokenAddress, ()),
            abi.encodeCall(ta.getLatestCdfArray, (latestRelayerState.relayers)),
            abi.encodeCall(ta.jailTimeInSec, ()),
            abi.encodeCall(ta.withdrawDelayInSec, ()),
            abi.encodeCall(ta.absencePenaltyPercentage, ()),
            abi.encodeCall(ta.minimumStakeAmount, ()),
            abi.encodeCall(ta.relayerStateUpdateDelayInWindows, ()),
            abi.encodeCall(ta.relayerStateHash, ()),
            abi.encodeCall(ta.totalUnpaidProtocolRewards, ()),
            abi.encodeCall(ta.lastUnpaidRewardUpdatedTimestamp, ()),
            abi.encodeCall(ta.totalProtocolRewardShares, ()),
            abi.encodeCall(ta.baseRewardRatePerMinimumStakePerSec, ())
        ];

        selectorExcludedFromTests[ta.registerFoundationRelayer.selector] = true;

        // Run the test for each defined transaction
        for (uint256 i = 0; i < txns.length; i++) {
            this._executeTxnTest(txns[i]);
        }

        // Generate the selectors for this module and verify that the test has been run for each
        bytes4[] memory selectors = _generateSelectors("TARelayerManagement");
        assertTrue(selectors.length > 0);
        for (uint256 i = 0; i < selectors.length; i++) {
            assertTrue(
                selectorExcludedFromTests[selectors[i]] || testExecuted[selectors[i]],
                string.concat("Test not executed for selector: ", vm.toString(selectors[i]))
            );
        }
    }

    function testShouldPreventInvocationOfCoreFunctionsViaTransactionExecutionFlowInTransactionAllocationModule()
        external
    {
        txns = [
            abi.encodeCall(
                ta.execute,
                (
                    ITATransactionAllocation.ExecuteParams({
                        reqs: new bytes[](1),
                        forwardedNativeAmounts: new uint256[](1),
                        relayerIndex: 0,
                        relayerGenerationIterationBitmap: 0,
                        activeState: latestRelayerState,
                        latestState: latestRelayerState
                    })
                )
            ),
            abi.encodeCall(ta.transactionsSubmittedByRelayer, (relayerMainAddress[0])),
            abi.encodeCall(ta.totalTransactionsSubmitted, (latestRelayerState)),
            abi.encodeCall(ta.epochLengthInSec, ()),
            abi.encodeCall(ta.epochEndTimestamp, ()),
            abi.encodeCall(ta.livenessZParameter, ()),
            abi.encodeCall(ta.stakeThresholdForJailing, ())
        ];

        selectorExcludedFromTests[ta.allocateRelayers.selector] = true;
        selectorExcludedFromTests[ta.calculateMinimumTranasctionsForLiveness.selector] = true;

        // Run the test for each defined transaction
        for (uint256 i = 0; i < txns.length; i++) {
            this._executeTxnTest(txns[i]);
        }

        // Generate the selectors for this module and verify that the test has been run for each
        bytes4[] memory selectors = _generateSelectors("TATransactionAllocation");
        assertTrue(selectors.length > 0);
        for (uint256 i = 0; i < selectors.length; i++) {
            assertTrue(
                selectorExcludedFromTests[selectors[i]] || testExecuted[selectors[i]],
                string.concat("Test not executed for selector: ", vm.toString(selectors[i]))
            );
        }
    }

    function testShouldPreventInvocationOfCoreFunctionsViaTransactionExecutionFlowInDelegationModule() external {
        txns = [
            abi.encodeCall(ta.delegate, (latestRelayerState, 0, 0)),
            abi.encodeCall(ta.undelegate, (latestRelayerState, relayerMainAddress[0], 0)),
            abi.encodeCall(ta.claimableDelegationRewards, (relayerMainAddress[0], NATIVE_TOKEN, delegatorAddresses[0])),
            abi.encodeCall(ta.addDelegationRewards, (relayerMainAddress[0], 0, 0)),
            abi.encodeCall(ta.totalDelegation, (relayerMainAddress[0])),
            abi.encodeCall(ta.delegation, (relayerMainAddress[0], delegatorAddresses[0])),
            abi.encodeCall(ta.shares, (relayerMainAddress[0], delegatorAddresses[0], NATIVE_TOKEN)),
            abi.encodeCall(ta.totalShares, (relayerMainAddress[0], NATIVE_TOKEN)),
            abi.encodeCall(ta.unclaimedDelegationRewards, (relayerMainAddress[0], NATIVE_TOKEN)),
            abi.encodeCall(ta.supportedPools, ()),
            abi.encodeCall(ta.minimumDelegationAmount, ()),
            abi.encodeCall(ta.delegationWithdrawal, (relayerMainAddress[0], delegatorAddresses[0])),
            abi.encodeCall(ta.withdrawDelegation, (relayerMainAddress[0])),
            abi.encodeCall(ta.delegationWithdrawDelayInSec, ())
        ];

        // Run the test for each defined transaction
        for (uint256 i = 0; i < txns.length; i++) {
            this._executeTxnTest(txns[i]);
        }

        // Generate the selectors for this module and verify that the test has been run for each
        bytes4[] memory selectors = _generateSelectors("TADelegation");
        assertTrue(selectors.length > 0);
        for (uint256 i = 0; i < selectors.length; i++) {
            assertTrue(
                selectorExcludedFromTests[selectors[i]] || testExecuted[selectors[i]],
                string.concat("Test not executed for selector: ", vm.toString(selectors[i]))
            );
        }
    }
}
