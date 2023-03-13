// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import "forge-std/Test.sol";
import "../modules/ITransactionAllocatorDebug.sol";
import "src/library/FixedPointArithmetic.sol";
import "script/TA.Deployment.s.sol";
import "src/transaction-allocator/common/TAStructs.sol";
import "openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";

abstract contract TATestBase is Test {
    using FixedPointTypeHelper for FixedPointType;

    string constant mnemonic = "test test test test test test test test test test test junk";
    uint256 constant relayerCount = 10;
    uint256 constant relayerAccountsPerRelayer = 10;
    uint256 constant delegatorCount = 10;
    uint256 constant initialMainAccountFunds = 10 ether;
    uint256 constant initialRelayerAccountFunds = 1 ether;
    uint256 constant initialDelegatorFunds = 1 ether;

    InitalizerParams deployParams = InitalizerParams({
        blocksPerWindow: 10,
        relayersPerWindow: 10,
        penaltyDelayBlocks: 10,
        bondTokenAddress: TokenAddress.wrap(address(0))
    });

    ITransactionAllocatorDebug internal ta;

    uint256[] internal relayerMainKey;
    RelayerAddress[] internal relayerMainAddress;
    mapping(RelayerAddress => RelayerAccountAddress[]) internal relayerAccountAddresses;
    mapping(RelayerAddress => uint256[]) internal relayerAccountKeys;
    uint256[] internal delegatorKeys;
    DelegatorAddress[] internal delegatorAddresses;

    ERC20 bico;

    uint256 private _postDeploymentSnapshotId = type(uint256).max;

    function setUp() public virtual {
        if (_postDeploymentSnapshotId != type(uint256).max) {
            return;
        }

        // Deploy the bico token
        bico = new ERC20("BICO", "BICO");
        vm.label(address(bico), "ERC20(BICO)");
        deployParams.bondTokenAddress = TokenAddress.wrap(address(bico));

        uint32 keyIndex = 0;

        // Deploy TA, requires --ffi
        TADeploymentScript script = new TADeploymentScript();
        uint256 deployerPrivateKey = vm.deriveKey(mnemonic, ++keyIndex);
        ta = script.deployWithDebugModule(deployerPrivateKey, deployParams, false);

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

        _postDeploymentSnapshotId = vm.snapshot();
    }

    modifier atSnapshot() {
        bool revertStatus = vm.revertTo(_preTestSnapshotId());
        if (!revertStatus) {
            fail("Failed to revert to post deployment snapshot");
        }
        _;
    }

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
        assertEq(_a.toUint256(), _b.toUint256());
    }

    function _assertEqRa(RelayerAddress _a, RelayerAddress _b) internal {
        assertEq(RelayerAddress.unwrap(_a), RelayerAddress.unwrap(_b));
    }

    // add this to be excluded from coverage report
    function test() public {}
}
