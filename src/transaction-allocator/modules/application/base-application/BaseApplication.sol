// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import "./interfaces/IBaseApplication.sol";

contract BaseApplication is IBaseApplication {
    modifier onlySelf() {
        if (msg.sender != address(this)) revert ExternalCallsNotAllowed();
        _;
    }

    function _getCalldataParams()
        internal
        pure
        virtual
        returns (uint256 relayerGenerationIterationBitmap, uint256 relayerCount)
    {
        /*
         * Calldata Map
         * |-------?? bytes--------|------32 bytes-------|---------32 bytes -------|
         * |---Original Calldata---|------RGI Bitmap-----|------Relayer Count------|
         */
        assembly {
            relayerGenerationIterationBitmap := calldataload(sub(calldatasize(), 64))
            relayerCount := calldataload(sub(calldatasize(), 32))
        }
    }
}
