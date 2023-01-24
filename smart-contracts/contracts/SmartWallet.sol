// SPDX-License-Identifier: MIT

pragma solidity 0.8.17;

import "@openzeppelin/contracts-upgradeable/utils/cryptography/EIP712Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/cryptography/ECDSAUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import "hardhat/console.sol";

import "./interfaces/ISmartWallet.sol";
import "./structs/WalletStructs.sol";
import "./constants/SmartWalletConstants.sol";

contract SmartWallet is
    Initializable,
    EIP712Upgradeable,
    ISmartWallet,
    OwnableUpgradeable,
    SmartWalletConstants
{
    using ECDSAUpgradeable for bytes32;

    // State
    uint256 public nextNonce;

    function initialize(address _owner) external initializer {
        __EIP712_init(EIP712_NAME, EIP712_VERSION);
        _transferOwnership(_owner);
    }

    /// @notice verify signed data passed by relayers
    /// @param _req requested tx to be forwarded
    /// @return true if the tx parameters are correct
    function verify(ForwardRequest calldata _req) public view returns (bool) {
        address signer = _hashTypedDataV4(
            keccak256(
                abi.encode(
                    TYPEHASH,
                    _req.from,
                    _req.to,
                    _req.value,
                    _req.gas,
                    _req.nonce,
                    keccak256(_req.data)
                )
            )
        ).recover(_req.signature);
        return
            nextNonce == _req.nonce && signer == _req.from && signer == owner();
    }

    function execute(
        ForwardRequest calldata _req
    ) external returns (bool, bytes memory) {
        uint256 gas = gasleft();

        if (!verify(_req)) {
            revert InvalidSignature();
        }

        nextNonce++;
        (bool success, bytes memory returndata) = _req.to.call{
            value: _req.value,
            gas: _req.gas
        }(_req.data);

        emit WalletExecution(success, returndata, gas - gasleft());

        return (success, returndata);
    }
}
