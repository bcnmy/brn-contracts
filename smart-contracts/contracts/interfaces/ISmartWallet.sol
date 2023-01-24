// SPDX-License-Identifier: MIT

pragma solidity 0.8.17;

import "../structs/WalletStructs.sol";

interface ISmartWallet {
    error InvalidSignature();

    event WalletExecution(
        bool indexed success,
        bytes indexed returnData,
        uint256 indexed gasUsed
    );

    function initialize(address _owner) external;

    function verify(ForwardRequest calldata _req) external view returns (bool);

    function execute(
        ForwardRequest calldata _req
    ) external returns (bool, bytes memory);
}
