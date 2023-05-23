// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import "openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import "openzeppelin-contracts/contracts/utils/cryptography/ECDSA.sol";
import "forge-std/Test.sol";

import "src/library/FixedPointArithmetic.sol";
import "src/transaction-allocator/common/TAStructs.sol";
import "../modules/ITransactionAllocatorDebug.sol";
import "script/TA.Deployment.s.sol";

abstract contract TATestBase is Test {
    using FixedPointTypeHelper for FixedPointType;
    using ECDSA for bytes32;

    string constant mnemonic = "test test test test test test test test test test test junk";
    uint256 constant relayerCount = 10;
    uint256 constant relayerAccountsPerRelayer = 10;
    uint256 constant delegatorCount = 10;
    uint256 constant userCount = 10;
    uint256 constant initialMainAccountFunds = MINIMUM_STAKE_AMOUNT + 10 ether;
    uint256 constant initialRelayerAccountFunds = 1 ether;
    uint256 constant initialDelegatorFunds = 1 ether;
    uint256 constant initialUserAccountFunds = 1 ether;

    TokenAddress[] internal supportedTokens;
    InitalizerParams deployParams = InitalizerParams({
        blocksPerWindow: 10,
        relayersPerWindow: 10,
        epochLengthInSec: 1000,
        bondTokenAddress: TokenAddress.wrap(address(0)),
        supportedTokens: supportedTokens
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

    RelayerAddress[] internal activeRelayers;

    ERC20 bico;

    uint256 private _postDeploymentSnapshotId = type(uint256).max;

    function setUp() public virtual {
        if (_postDeploymentSnapshotId != type(uint256).max) {
            return;
        }

        // Deploy the bico token
        bico = new ERC20("BICO", "BICO");
        vm.label(address(bico), "ERC20(BICO)");
        supportedTokens.push(TokenAddress.wrap(address(bico)));
        supportedTokens.push(NATIVE_TOKEN);
        deployParams.bondTokenAddress = TokenAddress.wrap(address(bico));
        deployParams.supportedTokens = supportedTokens;

        uint32 keyIndex = 0;

        // Deploy TA, requires --ffi
        TADeploymentScript script = new TADeploymentScript();
        uint256 deployerPrivateKey = vm.deriveKey(mnemonic, ++keyIndex);
        ta = script.deployTest(deployerPrivateKey, deployParams, false);

        // Generate Relayer Addresses
        for (uint256 i = 0; i < relayerCount; i++) {
            // Generate Main Relayer Addresses
            relayerMainKey.push(vm.deriveKey(mnemonic, ++keyIndex));
            relayerMainAddress.push(RelayerAddress.wrap(vm.addr(relayerMainKey[i])));
            deal(RelayerAddress.unwrap(relayerMainAddress[i]), initialMainAccountFunds);
            deal(address(bico), RelayerAddress.unwrap(relayerMainAddress[i]), initialMainAccountFunds);
            vm.label(RelayerAddress.unwrap(relayerMainAddress[i]), _stringConcat2("relayer", vm.toString(i)));

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
                    _stringConcat4("relayer", vm.toString(i), "account", vm.toString(j))
                );
            }
        }

        // Generate Delegator Addresses
        for (uint256 i = 0; i < delegatorCount; i++) {
            delegatorKeys.push(vm.deriveKey(mnemonic, ++keyIndex));
            delegatorAddresses.push(DelegatorAddress.wrap(vm.addr(delegatorKeys[i])));
            deal(DelegatorAddress.unwrap(delegatorAddresses[i]), initialDelegatorFunds);
            deal(address(bico), DelegatorAddress.unwrap(delegatorAddresses[i]), initialDelegatorFunds);
            vm.label(DelegatorAddress.unwrap(delegatorAddresses[i]), _stringConcat2("delegator", vm.toString(i)));
        }

        // Generate User Addresses
        for (uint256 i = 0; i < userCount; i++) {
            uint256 key = vm.deriveKey(mnemonic, ++keyIndex);
            userAddresses.push(vm.addr(key));
            userKeys[userAddresses[i]] = key;
            deal(userAddresses[i], initialUserAccountFunds);
            vm.label(userAddresses[i], _stringConcat2("user", vm.toString(i)));
        }

        _postDeploymentSnapshotId = vm.snapshot();
    }

    modifier atSnapshot() {
        bool revertStatus = vm.revertTo(_preTestSnapshotId());
        if (!revertStatus) {
            fail("Failed to revert to post deployment snapshot");
        }
        _;
    }

    // Relayer Registration Helpers
    function _register(
        RelayerAddress _relayerAddress,
        uint32[] memory _stakeArray,
        uint32[] memory _delegationArray,
        uint256 _stake,
        RelayerAccountAddress[] memory _accountAddresses,
        string memory endpoint,
        uint256 delegatorPoolPremiumShare
    ) internal {
        _startPrankRA(_relayerAddress);
        ta.register(
            _stakeArray,
            _delegationArray,
            activeRelayers,
            _stake,
            _accountAddresses,
            endpoint,
            delegatorPoolPremiumShare
        );
        vm.stopPrank();
        activeRelayers.push(_relayerAddress);
    }

    function _unregister(RelayerAddress _relayerAddress, uint32[] memory _stakeArray, uint32[] memory _delegationArray)
        internal
    {
        _startPrankRA(_relayerAddress);

        uint256 relayerIndex = _findRelayerIndex(_relayerAddress);

        ta.unRegister(_stakeArray, _delegationArray, activeRelayers, relayerIndex);
        vm.stopPrank();

        // Update Active Relayers
        activeRelayers[relayerIndex] = activeRelayers[activeRelayers.length - 1];
        activeRelayers.pop();
    }

    function _findRelayerIndex(RelayerAddress _relayer) internal view returns (uint256) {
        for (uint256 i = 0; i < activeRelayers.length; i++) {
            if (activeRelayers[i] == _relayer) {
                return i;
            }
        }
        return activeRelayers.length;
    }

    // Utils

    function _stringConcat2(string memory a, string memory b) internal pure returns (string memory) {
        return string(abi.encodePacked(a, b));
    }

    function _stringConcat3(string memory a, string memory b, string memory c) internal pure returns (string memory) {
        return string(abi.encodePacked(a, b, c));
    }

    function _stringConcat4(string memory a, string memory b, string memory c, string memory d)
        internal
        pure
        returns (string memory)
    {
        return string(abi.encodePacked(a, b, c, d));
    }

    function _preTestSnapshotId() internal view virtual returns (uint256) {
        return _postDeploymentSnapshotId;
    }

    function _startPrankRA(RelayerAddress _relayer) internal {
        vm.startPrank(RelayerAddress.unwrap(_relayer));
    }

    function _startPrankRAA(RelayerAccountAddress _account) internal {
        vm.startPrank(RelayerAccountAddress.unwrap(_account));
    }

    function _prankDa(DelegatorAddress _da) internal {
        vm.prank(DelegatorAddress.unwrap(_da));
    }

    function _assertEqFp(FixedPointType _a, FixedPointType _b) internal {
        assertEq(_a.u256(), _b.u256());
    }

    function _assertEqRa(RelayerAddress _a, RelayerAddress _b) internal {
        assertEq(RelayerAddress.unwrap(_a), RelayerAddress.unwrap(_b));
    }

    // add this to be excluded from coverage report
    function test() public {}
}
