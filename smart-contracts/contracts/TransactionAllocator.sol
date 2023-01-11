// SPDX-License-Identifier: UNLICENSED

import "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "hardhat/console.sol";

pragma solidity ^0.8.9;

// POC for a forwarder contract that determines asignations of a time windows to relayers
// preventing gas wars to submit user transactions ahead of the other relayers
contract BicoForwarder is EIP712, Ownable {
    using ECDSA for bytes32;

    event VerificationGasConsumed(uint256);

    /// typehash
    bytes32 private constant _TYPEHASH =
        keccak256(
            "ForwardRequest(address from,address to,uint256 value,uint256 gas,uint256 nonce,bytes data)"
        );

    // Forward request structure
    struct ForwardRequest {
        address from;
        address to;
        uint256 value;
        uint256 gas;
        uint256 nonce;
        bytes data;
    }

    // relayer information
    struct RelayerInfo {
        uint256 stake;
        mapping(address => bool) isAccount;
        string endpoint;
        uint256 index;
        uint256 relayerStakePrefixArrayIndex;
    }

    // relayer information
    struct WithdrawalInfo {
        uint256 amount;
        uint256 time;
    }

    /// Maps relayer main address to info
    mapping(address => RelayerInfo) relayerInfo;

    /// Maps relayer address to pending withdrawals
    mapping(address => WithdrawalInfo) withdrawalInfo;

    /// list of nodes
    address[] public relayers;
    uint256 public relayerCount;

    /// blocks per node
    uint256 public blocksWindow;

    // unbounding period
    uint256 public withdrawDelay;

    // random number of realyers selected per window
    uint256 public relayersPerWindow;

    // minimum amount stake required by the replayer
    uint256 MINIMUM_STAKE_AMOUNT = 1e17;

    /// tx nonces
    mapping(address => uint256) private _nonces;

    /// relayer stake prefix sum, used as probability distribution
    uint256[] public relayerStakePrefixSum;
    mapping(uint256 => address) public relayerStakePrefixSumIndexToRelayer;

    // Emitted when a new relayer is registered
    event RelayerRegistered(
        address indexed relayer,
        string endpoint,
        address[] accounts,
        uint256 stake,
        uint256 relayerStakePrefixArrayIndex
    );

    // Emitted when a relayer is unregistered
    event RelayerUnRegistered(address indexed relayer);

    // Emitted on valid withdrawal
    event Withdraw(address indexed relayer, uint256 amount);

    constructor(
        uint256 blocksPerNode_,
        uint256 withdrawDelay_,
        uint256 relayersPerWindow_
    ) EIP712("BicoForwarder", "0.0.1") Ownable() {
        blocksWindow = blocksPerNode_;
        withdrawDelay = withdrawDelay_;
        relayersPerWindow = relayersPerWindow_;
        relayerStakePrefixSum.push(0);
    }

    /// @notice register a relayer
    /// @param stake amount to be staked
    /// @param accounts list of accounts that the relayer will use for forwarding tx
    /// @param endpoint that can be used by any app to send transactions to this relayer
    function register(
        uint256 stake,
        address[] calldata accounts,
        string memory endpoint
    ) external {
        require(accounts.length > 0, "No accounts");
        require(stake >= MINIMUM_STAKE_AMOUNT);
        RelayerInfo storage node = relayerInfo[msg.sender];
        node.stake += stake;
        node.endpoint = endpoint;
        node.index = relayers.length;
        for (uint256 i = 0; i < accounts.length; i++) {
            node.isAccount[accounts[i]] = true;
        }

        // Update the prefix sum array for stake
        uint256 length = relayerStakePrefixSum.length;
        if (node.relayerStakePrefixArrayIndex == 0) {
            node.relayerStakePrefixArrayIndex = length;
            relayerStakePrefixSumIndexToRelayer[length] = msg.sender;
        }
        for (uint256 i = node.relayerStakePrefixArrayIndex; i <= length; ) {
            if (i == length) {
                relayerStakePrefixSum.push(relayerStakePrefixSum[i - 1]);
            }
            relayerStakePrefixSum[i] += stake;
            unchecked {
                ++i;
            }
        }
        relayers.push(msg.sender);

        ++relayerCount;

        // todo: trasnfer stake amount to be stored in a vault.
        emit RelayerRegistered(
            msg.sender,
            endpoint,
            accounts,
            stake,
            node.relayerStakePrefixArrayIndex
        );
    }

    /// @notice a relayer vn unregister, which removes it from the relayer list and a delay for withdrawal is imposed on funds
    function unRegister() external {
        RelayerInfo storage node = relayerInfo[msg.sender];
        require(relayers[node.index] == msg.sender, "Invalid user");
        uint256 n = relayers.length - 1;
        uint256 stake = node.stake;
        if (node.index != n) relayers[node.index] = relayers[n];
        relayers.pop();
        --relayerCount;

        // Update the prefix sum array for stake
        for (
            uint256 i = node.relayerStakePrefixArrayIndex;
            i < relayerStakePrefixSum.length;

        ) {
            relayerStakePrefixSum[i] -= stake;
            unchecked {
                ++i;
            }
        }

        withdrawalInfo[msg.sender] = WithdrawalInfo(
            stake,
            block.timestamp + withdrawDelay
        );
        emit RelayerUnRegistered(msg.sender);
    }

    function withdraw(address relayer) external {
        WithdrawalInfo memory w = withdrawalInfo[relayer];
        require(w.amount > 0 && w.time < block.timestamp, "invalid withdrawal");
        withdrawalInfo[relayer] = WithdrawalInfo(0, 0);

        // todo: send w.amount to relayer

        emit Withdraw(relayer, w.amount);
    }

    /// @notice returns true if the current sender is allowed to relay transaction in this block
    function _verifyTransactionAllocation(
        uint256 _relayerStakePrefixSumIndex,
        uint256 _relayerGenerationIteration,
        bytes calldata _calldata
    ) internal view returns (bool) {
        // Verify Iteration
        if (_relayerGenerationIteration >= relayersPerWindow) {
            return false;
        }

        // Verify if correct stake prefix sum index has been provided
        uint256 randomRelayerStake = _randomRelayerStake(
            block.number,
            _relayerGenerationIteration
        );
        if (
            !((_relayerStakePrefixSumIndex == 0 ||
                relayerStakePrefixSum[_relayerStakePrefixSumIndex - 1] <
                randomRelayerStake) &&
                randomRelayerStake <=
                relayerStakePrefixSum[_relayerStakePrefixSumIndex])
        ) {
            // The supplied index does not point to the correct interval
            return false;
        }

        // Verify if the relayer selected is msg.sender
        address relayerAddress = relayerStakePrefixSumIndexToRelayer[
            _relayerStakePrefixSumIndex
        ];
        RelayerInfo storage node = relayerInfo[relayerAddress];
        if (!node.isAccount[msg.sender]) {
            return false;
        }

        // Verify if the transaction was alloted to the relayer
        return _relayerGenerationIteration == _assignRelayer(_calldata);
    }

    /// @notice returns the nonce for a particular client
    /// @param from client address
    function getNonce(address from) public view returns (uint256) {
        return _nonces[from];
    }

    /// @notice verify signed data passed by relayers
    /// @param req requested tx to be forwarded
    /// @param signature client signature
    /// @return true if the tx parameters are correct
    function verify(
        ForwardRequest calldata req,
        bytes calldata signature
    ) public view returns (bool) {
        address signer = _hashTypedDataV4(
            keccak256(
                abi.encode(
                    _TYPEHASH,
                    req.from,
                    req.to,
                    req.value,
                    req.gas,
                    req.nonce,
                    keccak256(req.data)
                )
            )
        ).recover(signature);
        return _nonces[req.from] == req.nonce && signer == req.from;
    }

    /// @notice allows relayer to execute a tx on behalf of a client
    /// @param _req requested tx to be forwarded
    /// @param _signature signature of the client
    /// @param _relayerGenerationIteration index at which relayer was selected
    /// @param _relayerStakePrefixSumIndex index of relayer in prefix sum array
    function execute(
        ForwardRequest calldata _req,
        bytes calldata _signature,
        uint256 _relayerGenerationIteration,
        uint256 _relayerStakePrefixSumIndex
    ) public payable returns (bool, bytes memory) {
        uint256 gasLeft = gasleft();
        require(
            _verifyTransactionAllocation(
                _relayerStakePrefixSumIndex,
                _relayerGenerationIteration,
                _req.data
            ),
            "invalid relayer window"
        );
        emit VerificationGasConsumed(gasLeft - gasleft());
        // require(verify(req, _signature), "signature does not match request");

        _nonces[_req.from] = _req.nonce + 1;

        (bool success, bytes memory returndata) = _req.to.call{
            gas: _req.gas,
            value: _req.value
        }(abi.encodePacked(_req.data, _req.from));

        // Validate that the relayer has sent enough gas for the call.
        if (gasleft() <= _req.gas / 63) {
            assembly {
                invalid()
            }
        }

        return (success, returndata);
    }

    function _randomRelayerStake(
        uint256 _blockNumber,
        uint256 _iter
    ) internal view returns (uint256 index) {
        // The seed for jth iteration is a function of the base seed and j
        uint256 relayerStakeSum = relayerStakePrefixSum[
            relayerStakePrefixSum.length - 1
        ];
        uint256 baseSeed = uint256(
            keccak256(abi.encodePacked(_blockNumber / blocksWindow))
        );
        uint256 seed = uint256(keccak256(abi.encodePacked(baseSeed, _iter)));
        return (seed % relayerStakeSum) + 1;
    }

    function _assignRelayer(
        bytes calldata _calldata
    ) internal view returns (uint256 relayerIndex) {
        relayerIndex =
            uint256(keccak256(abi.encodePacked(_calldata))) %
            relayersPerWindow;
    }

    // note: binary search becomes more efficient than linear search only after a certain length threshold,
    // in future a crossover point may be found and implemented for better performance
    function _lowerBound(
        uint256[] storage arr,
        uint256 target
    ) internal view returns (uint256) {
        uint256 low = 0;
        uint256 high = arr.length;
        unchecked {
            while (low < high) {
                uint256 mid = (low + high) / 2;
                if (arr[mid] < target) {
                    low = mid + 1;
                } else {
                    high = mid;
                }
            }
        }
        return low;
    }

    /// @notice Given a block number, the function generates a list of pseudo-random relayers
    ///         for the window of which the block in a part of. The generated list of relayers
    ///         is pseudo-random but deterministic
    /// @param _blockNumber block number for which the relayers are to be generated
    /// @return selectedRelayers list of relayers selected of length relayersPerWindow, but
    ///                          there can be duplicates
    /// @return relayerStakePrefixSumIndex list of indices of the selected relayers in the
    ///                                    relayerStakePrefixSum array, used for verification
    function allocateRelayers(
        uint256 _blockNumber
    ) public view returns (address[] memory, uint256[] memory) {
        require(
            relayers.length >= relayersPerWindow,
            "Insufficient relayers registered"
        );
        if (_blockNumber == 0) {
            _blockNumber = block.number;
        }

        // Generate `relayersPerWindow` pseudo-random distinct relayers
        address[] memory selectedRelayers = new address[](relayersPerWindow);
        uint256[] memory relayerStakePrefixSumIndex = new uint256[](
            relayersPerWindow
        );

        uint256 relayerStakeSum = relayerStakePrefixSum[
            relayerStakePrefixSum.length - 1
        ];
        require(relayerStakeSum > 0, "No relayers registered");

        for (uint256 i = 0; i < relayersPerWindow; ) {
            relayerStakePrefixSumIndex[i] = _lowerBound(
                relayerStakePrefixSum,
                _randomRelayerStake(_blockNumber, i)
            );
            RelayerInfo storage relayer = relayerInfo[
                relayerStakePrefixSumIndexToRelayer[
                    relayerStakePrefixSumIndex[i]
                ]
            ];
            uint256 relayerIndex = relayer.index;
            address relayerAddress = relayers[relayerIndex];
            selectedRelayers[i] = relayerAddress;

            unchecked {
                ++i;
            }
        }
        return (selectedRelayers, relayerStakePrefixSumIndex);
    }

    /// @notice determine what transactions can be relayed by the sender
    /// @param _relayer Address of the relayer to allocate transactions for
    /// @param _blockNumber block number for which the relayers are to be generated
    /// @param _txnCalldata list with all transactions calldata to be filtered
    /// @return txnAllocated list of transactions that can be relayed by the relayer
    /// @return selectedRelayerStakePrefixSumIndex list of indices of the selected
    ///                                            relayers in the relayerStakePrefixSum array
    /// @return relayerGenerationIteration list of iterations of the relayer generation corresponding
    ///                                    to the selected transactions
    function allocateTransaction(
        address _relayer,
        uint256 _blockNumber,
        bytes[] calldata _txnCalldata
    ) public view returns (bytes[] memory, uint256[] memory, uint256[] memory) {
        if (_blockNumber == 0) {
            _blockNumber = block.number;
        }

        (
            address[] memory relayersAllocated,
            uint256[] memory relayerStakePrefixSumIndex
        ) = allocateRelayers(_blockNumber);
        require(relayersAllocated.length == relayersPerWindow, "AT101");

        // Filter the transactions
        bytes[] memory txnAllocated = new bytes[](_txnCalldata.length);
        uint256[] memory selectedRelayerStakePrefixSumIndex = new uint256[](
            _txnCalldata.length
        );
        uint256[] memory relayerGenerationIteration = new uint256[](
            _txnCalldata.length
        );
        uint256 j;

        // Filter the transactions
        for (uint256 i = 0; i < _txnCalldata.length; ) {
            uint256 relayerIndex = _assignRelayer(_txnCalldata[i]);
            address relayerAddress = relayersAllocated[relayerIndex];
            RelayerInfo storage node = relayerInfo[relayerAddress];

            // If the transaction can be processed by this relayer, store it's info
            if (node.isAccount[_relayer] || relayerAddress == _relayer) {
                relayerGenerationIteration[j] = relayerIndex;
                txnAllocated[j] = _txnCalldata[i];
                selectedRelayerStakePrefixSumIndex[
                    j
                ] = relayerStakePrefixSumIndex[relayerIndex];
                unchecked {
                    ++j;
                }
            }

            unchecked {
                ++i;
            }
        }

        // Reduce the array sizes if needed
        uint256 extraLength = _txnCalldata.length - j;
        assembly {
            mstore(txnAllocated, sub(mload(txnAllocated), extraLength))
            mstore(
                selectedRelayerStakePrefixSumIndex,
                sub(mload(selectedRelayerStakePrefixSumIndex), extraLength)
            )
            mstore(
                relayerGenerationIteration,
                sub(mload(relayerGenerationIteration), extraLength)
            )
        }

        return (
            txnAllocated,
            selectedRelayerStakePrefixSumIndex,
            relayerGenerationIteration
        );
    }

    function setRelayersPerWindow(
        uint256 _newRelayersPerWindow
    ) external onlyOwner {
        relayersPerWindow = _newRelayersPerWindow;
    }
}
