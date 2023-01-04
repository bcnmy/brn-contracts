// SPDX-License-Identifier: UNLICENSED

import "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";

pragma solidity ^0.8.9;

// POC for a forwarder contract that determines asignations of a time windows to relayers
// preventing gas wars to submit user transactions ahead of the other relayers
contract BicoForwarder is EIP712 {
    using ECDSA for bytes32;

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
    ) EIP712("BicoForwarder", "0.0.1") {
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

    /// @notice returns true if the current sender is allowed to relay trasnaction in this block
    function verifyRelayerWindow() internal view returns (bool) {
        uint256 relayerIndex = (block.number / blocksWindow) % relayers.length;
        address relayerAddress = relayers[relayerIndex];
        RelayerInfo storage node = relayerInfo[relayerAddress];
        return node.isAccount[msg.sender];
    }

    /// @notice returns the nonce for a particular client
    /// @param from client address
    function getNonce(address from) public view returns (uint256) {
        return _nonces[from];
    }

    /// @notice verify signed data passed by relayers
    /// @param req requested tx to be forwarded
    /// @param signature clien signature
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
    /// @param req requested tx to be forwarded
    /// @param signature clien signature
    function execute(
        ForwardRequest calldata req,
        bytes calldata signature
    ) public payable returns (bool, bytes memory) {
        require(verifyRelayerWindow(), "invalid relayer window");
        require(verify(req, signature), "signature does not match request");
        _nonces[req.from] = req.nonce + 1;

        (bool success, bytes memory returndata) = req.to.call{
            gas: req.gas,
            value: req.value
        }(abi.encodePacked(req.data, req.from));

        // Validate that the relayer has sent enough gas for the call.
        if (gasleft() <= req.gas / 63) {
            assembly {
                invalid()
            }
        }

        return (success, returndata);
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

    function allocateRelayers(
        uint256 blockNumber
    ) public view returns (address[] memory) {
        require(
            relayers.length >= relayersPerWindow,
            "Insufficient relayers registered"
        );
        if (blockNumber == 0) {
            blockNumber = block.number;
        }
        // Calculate window period
        uint256 windowStartBlock = blockNumber - (blockNumber % blocksWindow);
        uint256 windowEndBlock = windowStartBlock + blocksWindow - 1;
        uint256 seed = uint256(
            keccak256(abi.encodePacked(windowStartBlock, windowEndBlock))
        );

        // Generate `relayersPerWindow` pseudo-random distinct relayers
        address[] memory selectedRelayers = new address[](relayersPerWindow);

        // bitmask representing if a relayer is selected, used as a substitute for an in memory mapping (not possible in solidity)
        // assumes that the number of relayers is less than 256
        uint256 relayerSelected;

        uint256 relayerStakeSum = relayerStakePrefixSum[
            relayerStakePrefixSum.length - 1
        ];
        require(relayerStakeSum > 0, "No relayers registered");
        for (uint256 i = 0; i < relayersPerWindow; ) {
            RelayerInfo storage relayer = relayerInfo[
                relayerStakePrefixSumIndexToRelayer[
                    _lowerBound(relayerStakePrefixSum, seed % relayerStakeSum)
                ]
            ];
            uint256 relayerIndex = relayer.index;
            address relayerAddress = relayers[relayerIndex];
            // // If relayer is not selected
            if ((relayerSelected & (1 << relayerIndex)) == 0) {
                selectedRelayers[i] = relayerAddress;
                // Select the relayer
                relayerSelected |= (1 << relayerIndex);
                unchecked {
                    ++i;
                }
            }
            seed = uint256(keccak256(abi.encodePacked(seed)));
        }
        return selectedRelayers;
    }

    /// @notice determine what transactions can be relayed by the sender
    /// @param txnCalldata list with all transactions calldata
    function allocateTransaction(
        bytes[] memory txnCalldata
    ) public view returns (bytes[] memory) {
        //check if msg.sender is a part of the selected realyersPerWindow
        RelayerInfo storage node = relayerInfo[msg.sender];
        // require(relayers[node.index] == msg.sender, "Invalid user");

        address[] memory relayersAllocated = allocateRelayers(block.number);
        require(relayersAllocated.length == relayersPerWindow, "AT101");

        uint256 txnNumber;
        for (uint256 i = 0; i < txnCalldata.length; ) {
            uint256 relayerIndex = uint256(
                keccak256(abi.encodePacked(txnCalldata[i]))
            ) % relayersPerWindow;
            address relayerAddress = relayersAllocated[relayerIndex];
            RelayerInfo storage node = relayerInfo[relayerAddress];
            if (node.isAccount[msg.sender]) {
                txnNumber++;
            }
            unchecked {
                i++;
            }
        }

        bytes[] memory txnAllocated = new bytes[](txnNumber);
        uint256 j;

        for (uint256 i = 0; i < txnCalldata.length; ) {
            uint256 relayerIndex = uint256(
                keccak256(abi.encodePacked(txnCalldata[i]))
            ) % relayersPerWindow;
            address relayerAddress = relayersAllocated[relayerIndex];
            RelayerInfo storage node = relayerInfo[relayerAddress];
            if (node.isAccount[msg.sender]) {
                txnAllocated[j] = txnCalldata[i];
                j++;
            }
            unchecked {
                i++;
            }
        }

        return txnAllocated;
    }
}
