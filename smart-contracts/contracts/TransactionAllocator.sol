// SPDX-License-Identifier: UNLICENSED

import "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/math/SafeCast.sol";
import "hardhat/console.sol";

pragma solidity ^0.8.9;

// POC for a forwarder contract that determines asignations of a time windows to relayers
// preventing gas wars to submit user transactions ahead of the other relayers
contract BicoForwarder is EIP712, Ownable {
    using ECDSA for bytes32;
    using SafeCast for uint256;

    event ExecutionGasConsumed(uint256 gasConsumed);

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

    // totalStake
    uint256 public totalStake;

    // stake array hash
    bytes32 public stakeArrayHash;

    // Relayer Index to Relayer
    mapping(uint256 => address) public relayerIndexToRelayer;

    /// tx nonces
    mapping(address => uint256) private _nonces;

    // Emitted when a new relayer is registered
    event RelayerRegistered(
        address indexed relayer,
        string endpoint,
        address[] accounts,
        uint256 stake
    );

    // Emitted when a relayer is unregistered
    event RelayerUnRegistered(address indexed relayer);

    // Emitted on valid withdrawal
    event Withdraw(address indexed relayer, uint256 amount);

    // StakeArrayUpdated
    event StakePercArrayUpdated(
        uint8[] stakePercArray,
        bytes32 indexed stakePercArrayHash
    );

    constructor(
        uint256 blocksPerNode_,
        uint256 withdrawDelay_,
        uint256 relayersPerWindow_
    ) EIP712("BicoForwarder", "0.0.1") Ownable() {
        blocksWindow = blocksPerNode_;
        withdrawDelay = withdrawDelay_;
        relayersPerWindow = relayersPerWindow_;
        stakeArrayHash = keccak256(abi.encodePacked(new uint256[](0)));
    }

    function _calculateStakeArrayHashMemory(
        uint8[] memory _stakeArray
    ) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked(_stakeArray));
    }

    function _calculateStakeArrayHash(
        uint8[] calldata _stakeArray
    ) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked(_stakeArray));
    }

    function _verifyStakeArrayHash(
        uint8[] calldata _stakeArray
    ) internal view returns (bool) {
        return stakeArrayHash == _calculateStakeArrayHash(_stakeArray);
    }

    modifier verifyStakeArrayHash(uint8[] calldata _stakeArray) {
        require(_verifyStakeArrayHash(_stakeArray), "Invalid stake array hash");
        _;
    }

    function _stakeArrayToPdf(
        uint8[] calldata _stakeArray
    ) internal pure returns (uint256[] memory) {
        uint256[] memory pdf = new uint256[](_stakeArray.length);
        uint256 length = _stakeArray.length;
        uint256 sum = 0;
        for (uint256 i = 0; i < length; ) {
            sum += _stakeArray[i];
            pdf[i] = sum;
            unchecked {
                ++i;
            }
        }
        return pdf;
    }

    /// @notice register a relayer
    /// @param stake amount to be staked
    /// @param accounts list of accounts that the relayer will use for forwarding tx
    /// @param endpoint that can be used by any app to send transactions to this relayer
    function register(
        uint8[] calldata _previousStakePercArray,
        uint256 stake,
        address[] calldata accounts,
        string memory endpoint
    ) external verifyStakeArrayHash(_previousStakePercArray) {
        require(accounts.length > 0, "No accounts");
        require(stake >= MINIMUM_STAKE_AMOUNT);

        RelayerInfo storage node = relayerInfo[msg.sender];
        node.stake += stake;
        node.endpoint = endpoint;
        node.index = relayers.length;
        for (uint256 i = 0; i < accounts.length; i++) {
            node.isAccount[accounts[i]] = true;
        }
        relayers.push(msg.sender);
        relayerIndexToRelayer[node.index] = msg.sender;

        // Update stake percentages array and hash
        uint256 newStakePercArrayLength = _previousStakePercArray.length + 1;
        uint8[] memory newStakePercArray = new uint8[](newStakePercArrayLength);
        for (uint256 i = 0; i < newStakePercArrayLength - 1; ) {
            // Potential Issue: This will cause loss of precision and drift over time
            newStakePercArray[i] = ((_previousStakePercArray[i] * totalStake) /
                (totalStake + stake)).toUint8();
            unchecked {
                ++i;
            }
        }
        newStakePercArray[newStakePercArrayLength - 1] = uint8(
            (stake * 100) / (totalStake + stake)
        );
        stakeArrayHash = _calculateStakeArrayHashMemory(newStakePercArray);

        // Update total stake
        totalStake += stake;
        ++relayerCount;

        // todo: trasnfer stake amount to be stored in a vault.
        emit StakePercArrayUpdated(newStakePercArray, stakeArrayHash);
        emit RelayerRegistered(msg.sender, endpoint, accounts, stake);
    }

    /// @notice a relayer un unregister, which removes it from the relayer list and a delay for withdrawal is imposed on funds
    function unRegister(
        uint8[] calldata _previousStakePercArray
    ) external verifyStakeArrayHash(_previousStakePercArray) {
        RelayerInfo storage node = relayerInfo[msg.sender];
        require(relayers[node.index] == msg.sender, "Invalid user");

        uint256 n = relayers.length - 1;
        uint256 stake = node.stake;
        uint256 nodeIndex = node.index;

        if (nodeIndex != n) {
            relayers[nodeIndex] = relayers[n];
            relayerIndexToRelayer[nodeIndex] = relayerIndexToRelayer[n];
            relayerIndexToRelayer[n] = address(0);
        }

        relayers.pop();
        --relayerCount;

        withdrawalInfo[msg.sender] = WithdrawalInfo(
            stake,
            block.timestamp + withdrawDelay
        );

        // Update stake percentages array and hash
        uint8[] memory newStakePercArray = new uint8[](n);
        for (uint256 i = 0; i < n; ) {
            // Potential Issue: This will cause loss of precision and drift over time
            if (i == nodeIndex) {
                // Remove the node's stake from the array by substituting it with the last element
                newStakePercArray[i] = ((_previousStakePercArray[n] *
                    totalStake) / (totalStake - stake)).toUint8();
            } else {
                newStakePercArray[i] = ((_previousStakePercArray[i] *
                    totalStake) / (totalStake - stake)).toUint8();
            }
            unchecked {
                ++i;
            }
        }
        stakeArrayHash = _calculateStakeArrayHashMemory(newStakePercArray);
        emit StakePercArrayUpdated(newStakePercArray, stakeArrayHash);

        // Update total stake
        totalStake -= stake;

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
        uint256[] memory _pdf,
        uint256 _pdfIndex,
        uint256 _relayerGenerationIteration,
        bytes calldata _calldata
    ) internal view returns (bool) {
        // Verify Iteration
        if (_relayerGenerationIteration >= relayersPerWindow) {
            return false;
        }

        // Verify if correct stake prefix sum index has been provided
        uint256 randomRelayerStake = _randomPdfNumber(
            block.number,
            _relayerGenerationIteration,
            _pdf[_pdf.length - 1]
        );

        // console.log("Before pdf index verification");
        // console.log(_pdf.length, _pdfIndex);
        // if (_pdfIndex != 0) {
        //     console.log("pdf at index-1", _pdf[_pdfIndex - 1]);
        // }
        // console.log(
        //     "stake and pdf at index",
        //     randomRelayerStake,
        //     _pdf[_pdfIndex]
        // );
        if (
            !((_pdfIndex == 0 || _pdf[_pdfIndex - 1] < randomRelayerStake) &&
                randomRelayerStake <= _pdf[_pdfIndex])
        ) {
            // The supplied index does not point to the correct interval
            return false;
        }

        // console.log("Before relayer address verification");
        // Verify if the relayer selected is msg.sender
        address relayerAddress = relayerIndexToRelayer[_pdfIndex];
        RelayerInfo storage node = relayerInfo[relayerAddress];
        if (!node.isAccount[msg.sender]) {
            return false;
        }

        // console.log("Before transaction index verification");
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
    /// @param _pdfIndex index of relayer in pdf
    function execute(
        ForwardRequest calldata _req,
        bytes calldata _signature,
        uint8[] calldata _stakePercArray,
        uint256 _relayerGenerationIteration,
        uint256 _pdfIndex
    )
        public
        payable
        verifyStakeArrayHash(_stakePercArray)
        returns (bool, bytes memory)
    {
        require(
            _verifyTransactionAllocation(
                _stakeArrayToPdf(_stakePercArray),
                _pdfIndex,
                _relayerGenerationIteration,
                _req.data
            ),
            "invalid relayer window"
        );
        // require(verify(req, _signature), "signature does not match request");
        // _nonces[_req.from] = _req.nonce + 1;

        uint256 gasLeft = gasleft();
        (bool success, bytes memory returndata) = _req.to.call{
            gas: _req.gas,
            value: _req.value
        }(abi.encodePacked(_req.data, _req.from));
        emit ExecutionGasConsumed(gasLeft - gasleft());

        // Validate that the relayer has sent enough gas for the call.
        if (gasleft() <= _req.gas / 63) {
            assembly {
                invalid()
            }
        }

        return (success, returndata);
    }

    function _randomPdfNumber(
        uint256 _blockNumber,
        uint256 _iter,
        uint256 _max
    ) internal view returns (uint256 index) {
        // The seed for jth iteration is a function of the base seed and j
        uint256 baseSeed = uint256(
            keccak256(abi.encodePacked(_blockNumber / blocksWindow))
        );
        uint256 seed = uint256(keccak256(abi.encodePacked(baseSeed, _iter)));
        return (seed % _max);
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
        uint256[] memory arr,
        uint256 target
    ) internal pure returns (uint256) {
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
        uint256 _blockNumber,
        uint8[] calldata _stakePercArray
    )
        public
        view
        verifyStakeArrayHash(_stakePercArray)
        returns (address[] memory, uint256[] memory)
    {
        require(
            relayers.length >= relayersPerWindow,
            "Insufficient relayers registered"
        );
        if (_blockNumber == 0) {
            _blockNumber = block.number;
        }

        // Generate `relayersPerWindow` pseudo-random distinct relayers
        address[] memory selectedRelayers = new address[](relayersPerWindow);
        uint256[] memory pdfIndex = new uint256[](relayersPerWindow);

        require(totalStake > 0, "No relayers registered");

        for (uint256 i = 0; i < relayersPerWindow; ) {
            uint256[] memory pdf = _stakeArrayToPdf(_stakePercArray);
            uint256 randomPdfNumber = _randomPdfNumber(
                _blockNumber,
                i,
                pdf[pdf.length - 1]
            );
            pdfIndex[i] = _lowerBound(pdf, randomPdfNumber);
            RelayerInfo storage relayer = relayerInfo[
                relayerIndexToRelayer[pdfIndex[i]]
            ];
            uint256 relayerIndex = relayer.index;
            address relayerAddress = relayers[relayerIndex];
            selectedRelayers[i] = relayerAddress;

            unchecked {
                ++i;
            }
        }
        return (selectedRelayers, pdfIndex);
    }

    /// @notice determine what transactions can be relayed by the sender
    /// @param _relayer Address of the relayer to allocate transactions for
    /// @param _blockNumber block number for which the relayers are to be generated
    /// @param _txnCalldata list with all transactions calldata to be filtered
    /// @return txnAllocated list of transactions that can be relayed by the relayer
    /// @return selectedRelayersPdfIndex list of indices of the selected relayers in the pdf
    /// @return relayerGenerationIteration list of iterations of the relayer generation corresponding
    ///                                    to the selected transactions
    function allocateTransaction(
        address _relayer,
        uint256 _blockNumber,
        bytes[] calldata _txnCalldata,
        uint8[] calldata _stakePercArray
    )
        public
        view
        verifyStakeArrayHash(_stakePercArray)
        returns (bytes[] memory, uint256[] memory, uint256[] memory)
    {
        if (_blockNumber == 0) {
            _blockNumber = block.number;
        }

        (
            address[] memory relayersAllocated,
            uint256[] memory relayerStakePrefixSumIndex
        ) = allocateRelayers(_blockNumber, _stakePercArray);
        require(relayersAllocated.length == relayersPerWindow, "AT101");

        // Filter the transactions
        bytes[] memory txnAllocated = new bytes[](_txnCalldata.length);
        uint256[] memory selectedRelayerPdfIndex = new uint256[](
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
                selectedRelayerPdfIndex[j] = relayerStakePrefixSumIndex[
                    relayerIndex
                ];
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
                selectedRelayerPdfIndex,
                sub(mload(selectedRelayerPdfIndex), extraLength)
            )
            mstore(
                relayerGenerationIteration,
                sub(mload(relayerGenerationIteration), extraLength)
            )
        }

        return (
            txnAllocated,
            selectedRelayerPdfIndex,
            relayerGenerationIteration
        );
    }

    function setRelayersPerWindow(
        uint256 _newRelayersPerWindow
    ) external onlyOwner {
        relayersPerWindow = _newRelayersPerWindow;
    }
}
