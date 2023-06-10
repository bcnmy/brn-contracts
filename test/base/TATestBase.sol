// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import "openzeppelin-contracts/token/ERC20/ERC20.sol";
import "openzeppelin-contracts/utils/cryptography/ECDSA.sol";
import "forge-std/Test.sol";

import "src/library/FixedPointArithmetic.sol";
import "../modules/ITransactionAllocatorDebug.sol";
import "script/TA.Deployment.s.sol";

abstract contract TATestBase is Test {
    using FixedPointTypeHelper for FixedPointType;
    using ECDSA for bytes32;

    uint256 constant CDF_ERROR_MARGIN = 0.005 ether; // 0.005%

    string constant mnemonic = "test test test test test test test test test test test junk";
    uint256 constant relayerCount = 10;
    uint256 constant relayerAccountsPerRelayer = 10;
    uint256 constant delegatorCount = 10;
    uint256 constant userCount = 10;
    uint256 constant initialMainAccountFunds = 1000000 ether;
    uint256 constant initialRelayerAccountFunds = 1 ether;
    uint256 constant initialDelegatorFunds = 1 ether;
    uint256 constant initialUserAccountFunds = 1 ether;

    TokenAddress[] internal supportedTokens;
    ITAProxy.InitializerParams deployParams = ITAProxy.InitializerParams({
        blocksPerWindow: 10,
        epochLengthInSec: 100,
        relayersPerWindow: 10,
        jailTimeInSec: 10000,
        withdrawDelayInSec: 50,
        absencePenaltyPercentage: 250,
        minimumStakeAmount: 10000 ether,
        stakeThresholdForJailing: 10000 ether,
        minimumDelegationAmount: 1 ether,
        baseRewardRatePerMinimumStakePerSec: 1003000000000,
        relayerStateUpdateDelayInWindows: 1,
        livenessZParameter: 3300000000000000000000000,
        bondTokenAddress: TokenAddress.wrap(address(this)),
        supportedTokens: supportedTokens,
        // Foundation Relayer Parameters
        foundationRelayerAddress: RelayerAddress.wrap(address(0)),
        foundationRelayerAccountAddresses: new RelayerAccountAddress[](0),
        foundationRelayerStake: 10000 ether,
        foundationRelayerEndpoint: "endpoint",
        foundationDelegatorPoolPremiumShare: 0
    });

    ITransactionAllocatorDebug internal ta;

    uint256[] internal relayerMainKey;
    RelayerAddress[] internal relayerMainAddress;
    mapping(RelayerAddress => RelayerAccountAddress[]) internal relayerAccountAddresses;
    mapping(RelayerAddress => uint256[]) internal relayerAccountKeys;
    uint256[] internal delegatorKeys;
    DelegatorAddress[] internal delegatorAddresses;
    address[] userAddresses;
    mapping(address => uint256) internal userKeys;
    mapping(RelayerAddress => uint256) internal initialRelayerStake;
    ERC20 bico;

    // Test State
    RelayerState internal latestRelayerState;

    // Relayer Deploy Params
    string endpoint = "test";
    uint256 delegatorPoolPremiumShare = 1000;

    function setUp() public virtual {
        // Deploy the bico token
        bico = new ERC20("BICO", "BICO");
        vm.label(address(bico), "ERC20(BICO)");

        uint32 keyIndex = 0;

        // Generate Relayer Addresses
        for (uint256 i = 0; i < relayerCount; i++) {
            // Generate Main Relayer Addresses
            relayerMainKey.push(vm.deriveKey(mnemonic, ++keyIndex));
            relayerMainAddress.push(RelayerAddress.wrap(vm.addr(relayerMainKey[i])));
            deal(RelayerAddress.unwrap(relayerMainAddress[i]), initialMainAccountFunds);
            deal(address(bico), RelayerAddress.unwrap(relayerMainAddress[i]), initialMainAccountFunds);
            vm.label(RelayerAddress.unwrap(relayerMainAddress[i]), string.concat("relayer", vm.toString(i)));

            // Generate Relayer Account Addresses
            for (uint256 j = 0; j < relayerAccountsPerRelayer; j++) {
                relayerAccountKeys[relayerMainAddress[i]].push(vm.deriveKey(mnemonic, ++keyIndex));
                relayerAccountAddresses[relayerMainAddress[i]].push(
                    RelayerAccountAddress.wrap(vm.addr(relayerAccountKeys[relayerMainAddress[i]][j]))
                );
                deal(
                    RelayerAccountAddress.unwrap(relayerAccountAddresses[relayerMainAddress[i]][j]),
                    initialRelayerAccountFunds
                );
                deal(
                    address(bico),
                    RelayerAccountAddress.unwrap(relayerAccountAddresses[relayerMainAddress[i]][j]),
                    initialRelayerAccountFunds
                );
                vm.label(
                    RelayerAccountAddress.unwrap(relayerAccountAddresses[relayerMainAddress[i]][j]),
                    string.concat("relayer", vm.toString(i), "account", vm.toString(j))
                );
            }
            initialRelayerStake[relayerMainAddress[i]] = 10000 ether * (i + 1);
        }

        // Generate Delegator Addresses
        for (uint256 i = 0; i < delegatorCount; i++) {
            delegatorKeys.push(vm.deriveKey(mnemonic, ++keyIndex));
            delegatorAddresses.push(DelegatorAddress.wrap(vm.addr(delegatorKeys[i])));
            deal(DelegatorAddress.unwrap(delegatorAddresses[i]), initialDelegatorFunds);
            deal(address(bico), DelegatorAddress.unwrap(delegatorAddresses[i]), initialDelegatorFunds);
            vm.label(DelegatorAddress.unwrap(delegatorAddresses[i]), string.concat("delegator", vm.toString(i)));
        }

        // Generate User Addresses
        for (uint256 i = 0; i < userCount; i++) {
            uint256 key = vm.deriveKey(mnemonic, ++keyIndex);
            userAddresses.push(vm.addr(key));
            userKeys[userAddresses[i]] = key;
            deal(userAddresses[i], initialUserAccountFunds);
            vm.label(userAddresses[i], string.concat("user", vm.toString(i)));
        }

        // Treat relayer 0 as foundation relayer
        deployParams.foundationRelayerAddress = relayerMainAddress[0];
        deployParams.foundationRelayerAccountAddresses = relayerAccountAddresses[relayerMainAddress[0]];

        // Update other deploy params
        supportedTokens.push(TokenAddress.wrap(address(bico)));
        supportedTokens.push(NATIVE_TOKEN);
        deployParams.bondTokenAddress = TokenAddress.wrap(address(bico));
        deployParams.supportedTokens = supportedTokens;

        // Approve tokens for foundation relayer registration
        uint256 deployerPrivateKey = vm.deriveKey(mnemonic, ++keyIndex);
        vm.broadcast(relayerMainKey[0]);
        bico.approve(computeCreateAddress(vm.addr(deployerPrivateKey), 6), 10000 ether);

        // Deploy TA, requires --ffi
        TADeploymentScript script = new TADeploymentScript();
        ta = script.deployInternalTestSetup(deployerPrivateKey, deployParams);

        _appendRelayerToLatestState(relayerMainAddress[0]);

        // Make sure windows start with 1
        _moveForwardByWindows(1);
    }

    // Used for triggering livness check, penalization, jailing and state updates
    function _sendEmptyTransaction(RelayerState memory _activeState) internal {
        // Find a relayer selected in the current window
        (RelayerAddress[] memory selectedRelayers, uint256[] memory selectedRelayerIndices) =
            ta.allocateRelayers(_activeState);
        _prankRA(selectedRelayers[0]);

        // Execute a transaction with no requests
        ta.execute(
            ITATransactionAllocation.ExecuteParams({
                reqs: new bytes[](0),
                forwardedNativeAmounts: new uint256[](0),
                relayerIndex: selectedRelayerIndices[0],
                relayerGenerationIterationBitmap: 0,
                activeState: _activeState,
                latestState: latestRelayerState,
                activeStateToPendingStateMap: _generateActiveStateToPendingStateMap(_activeState)
            })
        );
    }

    function _generateActiveStateToPendingStateMap(RelayerState memory _activeState)
        internal
        view
        returns (uint256[] memory map)
    {
        map = new uint256[](_activeState.relayers.length);

        // This is a test, idc about gas
        // wen in-memory mapping?
        for (uint256 i = 0; i < _activeState.relayers.length; i++) {
            map[i] = latestRelayerState.relayers.length;
            for (uint256 j = 0; j < latestRelayerState.relayers.length; j++) {
                if (_activeState.relayers[i] == latestRelayerState.relayers[j]) {
                    map[i] = j;
                    break;
                }
            }
        }
    }

    // Test Utils
    function _registerAllNonFoundationRelayers() internal {
        // Register all Relayers
        for (uint256 i = 1; i < relayerCount; i++) {
            RelayerAddress relayerAddress = relayerMainAddress[i];

            _prankRA(relayerAddress);
            bico.approve(address(ta), initialRelayerStake[relayerAddress]);

            _prankRA(relayerAddress);
            ta.register(
                latestRelayerState,
                initialRelayerStake[relayerAddress],
                relayerAccountAddresses[relayerAddress],
                endpoint,
                delegatorPoolPremiumShare
            );

            _appendRelayerToLatestState(relayerAddress);
        }
    }

    function _getRelayerAssignedToTx(bytes memory _tx) internal returns (RelayerAddress, uint256, uint256) {
        bytes[] memory txns_ = new bytes[](1);
        txns_[0] = _tx;

        for (uint256 i = 0; i < relayerMainAddress.length; i++) {
            RelayerAddress relayerAddress = relayerMainAddress[i];
            (bytes[] memory allotedTransactions, uint256 relayerGenerationIterations, uint256 selectedRelayerCdfIndex) =
                _allocateTransactions(relayerAddress, txns_, latestRelayerState);

            if (allotedTransactions.length == 1) {
                return (relayerAddress, relayerGenerationIterations, selectedRelayerCdfIndex);
            }
        }

        fail("No relayer found");
        return (RelayerAddress.wrap(address(0)), 0, 0);
    }

    function _allocateTransactions(RelayerAddress, bytes[] memory, RelayerState memory)
        internal
        virtual
        returns (bytes[] memory, uint256, uint256)
    {
        fail("Allocate Transactions Not Implemented");
        return (new bytes[](0), 0, 0);
    }

    function _calculatePenalty(uint256 _stake) internal view returns (uint256) {
        return (_stake * ta.absencePenaltyPercentage()) / (100 * PERCENTAGE_MULTIPLIER);
    }

    function _checkCdfInLatestState() internal {
        uint256 totalStake = ta.totalStake();
        uint16[] memory cdf = ta.getLatestCdfArray(latestRelayerState.relayers);

        for (uint256 i = 0; i < latestRelayerState.relayers.length; i++) {
            RelayerAddress relayerAddress = latestRelayerState.relayers[i];
            uint256 relativeStake = latestRelayerState.cdf[i] - (i == 0 ? 0 : latestRelayerState.cdf[i - 1]);
            assertApproxEqRel(
                relativeStake * totalStake,
                (ta.relayerInfo(relayerAddress).stake + ta.totalDelegation(relayerAddress)) * cdf[cdf.length - 1],
                CDF_ERROR_MARGIN,
                string.concat("CDF Verification - Relayer ", vm.toString(i))
            );
        }
    }

    // Relayer State Utils
    function _updateLatestStateCdf() internal {
        latestRelayerState.cdf = ta.getLatestCdfArray(latestRelayerState.relayers);
    }

    function _appendRelayerToLatestState(RelayerAddress _relayerAddress) internal {
        latestRelayerState.relayers.push(_relayerAddress);
        _updateLatestStateCdf();
    }

    function _removeRelayerFromLatestState(RelayerAddress _relayerAddress) internal {
        uint256 relayerIndex = _findRelayerIndex(_relayerAddress);
        if (relayerIndex == latestRelayerState.relayers.length) {
            return;
        }

        latestRelayerState.relayers[relayerIndex] = latestRelayerState.relayers[latestRelayerState.relayers.length - 1];
        latestRelayerState.relayers.pop();
        _updateLatestStateCdf();
    }

    function _findRelayerIndex(RelayerAddress _relayer) internal view returns (uint256) {
        for (uint256 i = 0; i < latestRelayerState.relayers.length; i++) {
            if (latestRelayerState.relayers[i] == _relayer) {
                return i;
            }
        }
        return latestRelayerState.relayers.length;
    }

    // Prank Utils
    function _startPrankRA(RelayerAddress _relayer) internal {
        vm.startPrank(RelayerAddress.unwrap(_relayer));
    }

    function _startPrankRAA(RelayerAccountAddress _account) internal {
        vm.startPrank(RelayerAccountAddress.unwrap(_account));
    }

    function _prankRA(RelayerAddress _relayer) internal {
        vm.prank(RelayerAddress.unwrap(_relayer));
    }

    function _prankDa(DelegatorAddress _da) internal {
        vm.prank(DelegatorAddress.unwrap(_da));
    }

    // Assert Utils
    function _assertEqFp(FixedPointType _a, FixedPointType _b) internal {
        assertEq(_a.u256(), _b.u256());
    }

    function _assertEqRa(RelayerAddress _a, RelayerAddress _b) internal {
        assertEq(RelayerAddress.unwrap(_a), RelayerAddress.unwrap(_b));
    }

    // Timing
    function _moveForwardByWindows(uint256 _windows) internal {
        vm.roll(block.number + _windows * ta.blocksPerWindow());
    }

    function _moveForwardToNextEpoch() internal {
        if (ta.epochEndTimestamp() < block.timestamp) {
            return;
        }
        vm.warp(ta.epochEndTimestamp());
    }

    function _countSetBits(uint256 _num) internal pure returns (uint256) {
        uint256 count = 0;
        while (_num > 0) {
            count += _num & 1;
            _num >>= 1;
        }
        return count;
    }

    // Add this to be excluded from coverage
    function test() external pure {}
}
