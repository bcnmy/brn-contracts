// SPDX-License-Identifier: MIT

pragma solidity 0.8.17;

import "openzeppelin-contracts/contracts/proxy/Clones.sol";

import "../interfaces/ISmartWallet.sol";

library SmartWalletFactory {
    event SmartContractWalletDeployed(address indexed owner, ISmartWallet indexed smartContractWallet);

    function deploySmartContractWallet(address _owner, address _implementation) internal returns (ISmartWallet) {
        ISmartWallet wallet = ISmartWallet(Clones.cloneDeterministic(_implementation, smartContractWalletSalt(_owner)));
        wallet.initialize(_owner);

        return wallet;
    }

    function getSmartContractWalletInstance(address _owner, address _implementation) internal returns (ISmartWallet) {
        address scw = predictSmartContractWalletAddress(_owner, _implementation);
        uint256 scwCodeSize;
        assembly {
            //TODO: Security concern?
            scwCodeSize := extcodesize(scw)
        }
        if (scwCodeSize == 0) {
            return deploySmartContractWallet(_owner, _implementation);
        }
        return ISmartWallet(scw);
    }

    function predictSmartContractWalletAddress(address _owner, address _implementation)
        internal
        view
        returns (address)
    {
        return Clones.predictDeterministicAddress(_implementation, smartContractWalletSalt(_owner));
    }

    function smartContractWalletSalt(address _owner) internal pure returns (bytes32) {
        return bytes32(uint256(uint160(_owner)) << 96);
    }
}
