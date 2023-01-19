// SPDX-License-Identifier: MIT

import "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/math/SafeCast.sol";
import "hardhat/console.sol";

pragma solidity 0.8.17;

// POC for a forwarder contract that determines asignations of a time windows to relayers
// preventing gas wars to submit user transactions ahead of the other relayers

contract TransactionAllocator is EIP712, Ownable {
    using ECDSA for bytes32;
    using SafeCast for uint256;

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

    struct CdfHashUpdateInfo {
        uint256 windowId;
        bytes32 cdfHash;
    }

    uint256 constant CDF_PRECISION_MULTIPLIER = 10 ** 4;
    uint256 constant STAKE_SCALING_FACTOR = 10 ** 18;
    // % * 100
    uint256 constant ABSENCE_PENATLY = 250;

    /// Maps relayer main address to info
    mapping(address => RelayerInfo) relayerInfo;

    /// Maps relayer address to pending withdrawals
    mapping(address => WithdrawalInfo) withdrawalInfo;

    uint256 public relayerCount;

    /// blocks per node
    uint256 public blocksWindow;

    // unbounding period
    uint256 public withdrawDelay;

    // random number of realyers selected per window
    uint256 public relayersPerWindow;

    // minimum amount stake required by the replayer
    uint256 MINIMUM_STAKE_AMOUNT = 1e17;

    // stake array hash
    bytes32 public stakeArrayHash;

    // cdf array hash
    CdfHashUpdateInfo[] public cdfHashUpdateLog;

    // Relayer Index to Relayer
    mapping(uint256 => address) public relayerIndexToRelayer;

    /// tx nonces
    mapping(address => uint256) private _nonces;

    // attendance: windowIndex -> relayer -> wasPresent?
    mapping(uint256 => mapping(address => bool)) public attendance;

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
    event StakeArrayUpdated(bytes32 indexed stakePercArrayHash);
    event CdfArrayUpdated(bytes32 indexed cdfArrayHash);

    event GenericGasConsumed(string label, uint256 gasConsumed);

    constructor(
        uint256 blocksPerNode_,
        uint256 withdrawDelay_,
        uint256 relayersPerWindow_
    ) EIP712("TransactionAllocator", "0.0.1") Ownable() {
        blocksWindow = blocksPerNode_;
        withdrawDelay = withdrawDelay_;
        relayersPerWindow = relayersPerWindow_;
        stakeArrayHash = keccak256(abi.encodePacked(new uint256[](0)));
    }

    function _verifyLatestCdfHash(
        uint16[] calldata _array
    ) internal view returns (bool) {
        return
            cdfHashUpdateLog[cdfHashUpdateLog.length - 1].cdfHash ==
            keccak256(abi.encodePacked(_array));
    }

    function _verifyPrevCdfHash(
        uint16[] calldata _array,
        uint256 _windowId,
        uint256 _cdfLogIndex
    ) internal view returns (bool) {
        // Validate _cdfLogIndex
        if (
            !(cdfHashUpdateLog[_cdfLogIndex].windowId <= _windowId &&
                (_cdfLogIndex == cdfHashUpdateLog.length - 1 ||
                    cdfHashUpdateLog[_cdfLogIndex + 1].windowId > _windowId))
        ) {
            return false;
        }

        return
            cdfHashUpdateLog[_cdfLogIndex].cdfHash ==
            keccak256(abi.encodePacked(_array));
    }

    function _verifyStakeArrayHash(
        uint32[] calldata _array
    ) internal view returns (bool) {
        return stakeArrayHash == keccak256(abi.encodePacked((_array)));
    }

    modifier verifyStakeArrayHash(uint32[] calldata _array) {
        require(_verifyStakeArrayHash(_array), "Invalid stake array hash");
        _;
    }

    modifier verifyCdfHash(uint16[] calldata _array) {
        require(_verifyLatestCdfHash(_array), "Invalid cdf array hash");
        _;
    }

    function _stakeArrayToCdf(
        uint32[] memory _stakeArray
    ) internal pure returns (uint16[] memory, bytes32 cdfHash) {
        uint16[] memory cdf = new uint16[](_stakeArray.length);
        uint256 totalStakeSum = 0;
        uint256 length = _stakeArray.length;

        for (uint256 i = 0; i < length; ) {
            totalStakeSum += _stakeArray[i];
            unchecked {
                ++i;
            }
        }

        // Scale the values to get the CDF
        uint256 sum = 0;
        for (uint256 i = 0; i < length; ) {
            sum += _stakeArray[i];
            cdf[i] = ((sum * CDF_PRECISION_MULTIPLIER) / totalStakeSum)
                .toUint16();
            unchecked {
                ++i;
            }
        }

        return (cdf, keccak256(abi.encodePacked(cdf)));
    }

    function _appendStake(
        uint32[] calldata _stakeArray,
        uint256 _stake
    ) internal pure returns (uint32[] memory) {
        uint256 stakeArrayLength = _stakeArray.length;
        uint32[] memory newStakeArray = new uint32[](stakeArrayLength + 1);

        // TODO: can this be optimized using calldatacopy?
        for (uint256 i = 0; i < stakeArrayLength; ) {
            newStakeArray[i] = _stakeArray[i];
            unchecked {
                ++i;
            }
        }
        newStakeArray[stakeArrayLength] = (_stake / STAKE_SCALING_FACTOR)
            .toUint32();

        return newStakeArray;
    }

    function _removeStake(
        uint32[] calldata _stakeArray,
        uint256 _index
    ) internal pure returns (uint32[] memory) {
        uint256 newStakeArrayLength = _stakeArray.length - 1;
        uint32[] memory newStakeArray = new uint32[](newStakeArrayLength);

        // TODO: can this be optimized using calldatacopy?
        for (uint256 i = 0; i < newStakeArrayLength; ) {
            if (i == _index) {
                // Remove the node's stake from the array by substituting it with the last element
                newStakeArray[i] = _stakeArray[newStakeArrayLength];
            } else {
                newStakeArray[i] = _stakeArray[i];
            }
            unchecked {
                ++i;
            }
        }

        return newStakeArray;
    }

    function _decreaseStake(
        uint32[] calldata _stakeArray,
        uint256 _index,
        uint32 _scaledAmount
    ) internal pure returns (uint32[] memory) {
        // TODO: Is this optimal?
        uint32[] memory newStakeArray = _stakeArray;
        newStakeArray[_index] = newStakeArray[_index] - _scaledAmount;
        return newStakeArray;
    }

    function _updateStakeAccounting(uint32[] memory _newStakeArray) internal {
        // Update Stake Array Hash
        stakeArrayHash = keccak256(abi.encodePacked(_newStakeArray));

        // Update cdf hash
        (, bytes32 cdfHash) = _stakeArrayToCdf(_newStakeArray);
        uint256 currentWindowId = _windowIdentifier(block.number);
        if (
            cdfHashUpdateLog.length == 0 ||
            cdfHashUpdateLog[cdfHashUpdateLog.length - 1].windowId !=
            currentWindowId
        ) {
            cdfHashUpdateLog.push(
                CdfHashUpdateInfo({
                    windowId: _windowIdentifier(block.number),
                    cdfHash: cdfHash
                })
            );
        } else {
            cdfHashUpdateLog[cdfHashUpdateLog.length - 1].cdfHash = cdfHash;
        }

        emit StakeArrayUpdated(stakeArrayHash);
        emit CdfArrayUpdated(cdfHash);
    }

    function getStakeArray() public view returns (uint32[] memory) {
        uint256 length = relayerCount;
        uint32[] memory stakeArray = new uint32[](length);
        for (uint256 i = 0; i < length; ) {
            stakeArray[i] = (relayerInfo[relayerIndexToRelayer[i]].stake /
                STAKE_SCALING_FACTOR).toUint32();
            unchecked {
                ++i;
            }
        }
        return stakeArray;
    }

    function getCdf() public view returns (uint16[] memory) {
        (uint16[] memory cdfArray, ) = _stakeArrayToCdf(getStakeArray());
        return cdfArray;
    }

    /// @notice register a relayer
    /// @param _previousStakeArray current stake array for verification
    /// @param _stake amount to be staked
    /// @param _accounts list of accounts that the relayer will use for forwarding tx
    /// @param _endpoint that can be used by any app to send transactions to this relayer
    function register(
        uint32[] calldata _previousStakeArray,
        uint256 _stake,
        address[] calldata _accounts,
        string memory _endpoint
    ) external verifyStakeArrayHash(_previousStakeArray) {
        require(_accounts.length > 0, "No accounts");
        require(_stake >= MINIMUM_STAKE_AMOUNT);

        RelayerInfo storage node = relayerInfo[msg.sender];
        node.stake += _stake;
        node.endpoint = _endpoint;
        node.index = relayerCount;
        for (uint256 i = 0; i < _accounts.length; i++) {
            node.isAccount[_accounts[i]] = true;
        }
        relayerIndexToRelayer[node.index] = msg.sender;
        ++relayerCount;

        // Update stake array and hash
        uint32[] memory newStakeArray = _appendStake(
            _previousStakeArray,
            _stake
        );
        _updateStakeAccounting(newStakeArray);

        // TODO: trasnfer stake amount to be stored in a vault.
        emit RelayerRegistered(msg.sender, _endpoint, _accounts, _stake);
    }

    /// @notice a relayer un unregister, which removes it from the relayer list and a delay for withdrawal is imposed on funds
    /// @param _previousStakeArray current stake array for verification
    function unRegister(
        uint32[] calldata _previousStakeArray
    ) external verifyStakeArrayHash(_previousStakeArray) {
        RelayerInfo storage node = relayerInfo[msg.sender];
        uint256 n = relayerCount - 1;
        uint256 stake = node.stake;
        uint256 nodeIndex = node.index;

        if (nodeIndex != n) {
            address lastRelayer = relayerIndexToRelayer[n];
            relayerIndexToRelayer[nodeIndex] = lastRelayer;
            relayerInfo[lastRelayer].index = nodeIndex;
            relayerIndexToRelayer[n] = address(0);
        }

        --relayerCount;

        withdrawalInfo[msg.sender] = WithdrawalInfo(
            stake,
            block.timestamp + withdrawDelay
        );

        // Update stake percentages array and hash
        uint32[] memory newStakeArray = _removeStake(
            _previousStakeArray,
            nodeIndex
        );
        _updateStakeAccounting(newStakeArray);
        emit RelayerUnRegistered(msg.sender);
    }

    function withdraw(address relayer) external {
        WithdrawalInfo memory w = withdrawalInfo[relayer];
        require(w.amount > 0 && w.time < block.timestamp, "invalid withdrawal");
        withdrawalInfo[relayer] = WithdrawalInfo(0, 0);

        // todo: send w.amount to relayer

        emit Withdraw(relayer, w.amount);
    }

    function _verifyRelayerSelection(
        uint16[] calldata _cdf,
        uint256 _cdfIndex,
        uint256[] calldata _relayerGenerationIterations,
        uint256 _blockNumber
    ) internal view returns (bool) {
        uint256 iterationCount = _relayerGenerationIterations.length;
        uint256 stakeSum = _cdf[_cdf.length - 1];

        // Verify Each Iteration against _cdfIndex in _cdf
        for (uint256 i = 0; i < iterationCount; ) {
            uint256 relayerGenerationIteration = _relayerGenerationIterations[
                i
            ];

            if (relayerGenerationIteration >= relayersPerWindow) {
                return false;
            }

            // Verify if correct stake prefix sum index has been provided
            uint256 randomRelayerStake = _randomCdfNumber(
                _blockNumber,
                relayerGenerationIteration,
                stakeSum
            );

            if (
                !((_cdfIndex == 0 ||
                    _cdf[_cdfIndex - 1] < randomRelayerStake) &&
                    randomRelayerStake <= _cdf[_cdfIndex])
            ) {
                // The supplied index does not point to the correct interval
                return false;
            }

            unchecked {
                ++i;
            }
        }

        // Verify if the relayer selected is msg.sender
        address relayerAddress = relayerIndexToRelayer[_cdfIndex];
        RelayerInfo storage node = relayerInfo[relayerAddress];
        if (!node.isAccount[msg.sender]) {
            return false;
        }

        return true;
    }

    /// @notice returns true if the current sender is allowed to relay transaction in this block
    function _verifyTransactionAllocation(
        uint16[] calldata _cdf,
        uint256 _cdfIndex,
        uint256[] calldata _relayerGenerationIteration,
        uint256 _blockNumber,
        ForwardRequest[] calldata _txs
    ) internal view returns (bool) {
        if (
            !_verifyRelayerSelection(
                _cdf,
                _cdfIndex,
                _relayerGenerationIteration,
                _blockNumber
            )
        ) {
            return false;
        }

        console.log("Relayer selected is correct");

        // Store all relayerGenerationIterations in a bitmap to efficiently check for existence in _relayerGenerationIteration
        // ASSUMPTION: Max no. of iterations required to generate 'relayersPerWindow' unique relayers <= 256
        uint256 bitmap = 0;
        uint256 length = _relayerGenerationIteration.length;
        for (uint256 i = 0; i < length; ) {
            bitmap |= (1 << _relayerGenerationIteration[i]);
            unchecked {
                ++i;
            }
        }

        // Verify if the transaction was alloted to the relayer
        length = _txs.length;
        for (uint256 i = 0; i < length; ) {
            uint256 relayerGenerationIteration = _assignRelayer(_txs[i].data);
            if ((bitmap & (1 << relayerGenerationIteration)) == 0) {
                return false;
            }
            unchecked {
                ++i;
            }
        }

        return true;
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
    /// @param _reqs requested txs to be forwarded
    /// @param _signature signature of the client
    /// @param _relayerGenerationIterations index at which relayer was selected
    /// @param _cdfIndex index of relayer in cdf
    // TODO: can we decrease calldata cost by using merkle proofs or square root decomposition?
    function execute(
        ForwardRequest[] calldata _reqs,
        bytes calldata _signature,
        uint16[] calldata _cdf,
        uint256[] calldata _relayerGenerationIterations,
        uint256 _cdfIndex
    )
        public
        payable
        returns (
            // verifyStakeArrayHash(_stakePercArray)
            bool[] memory,
            bytes[] memory
        )
    {
        uint256 gasLeft = gasleft();
        require(_verifyLatestCdfHash(_cdf), "Invalid cdf hash");
        require(
            _verifyTransactionAllocation(
                _cdf,
                _cdfIndex,
                _relayerGenerationIterations,
                block.number,
                _reqs
            ),
            "invalid relayer window"
        );
        // require(verify(req, _signature), "signature does not match request");
        // _nonces[_req.from] = _req.nonce + 1;
        emit GenericGasConsumed("VerificationGas", gasLeft - gasleft());

        gasLeft = gasleft();
        uint256 length = _reqs.length;
        uint256 totalGas = 0;
        bool[] memory successes = new bool[](length);
        bytes[] memory returndatas = new bytes[](length);

        for (uint256 i = 0; i < length; ) {
            ForwardRequest calldata _req = _reqs[i];

            // TODO: Check for success
            (bool success, bytes memory returndata) = _req.to.call{
                gas: _req.gas,
                value: _req.value
            }(abi.encodePacked(_req.data, _req.from));

            successes[i] = success;
            returndatas[i] = returndata;
            totalGas += _req.gas;

            unchecked {
                ++i;
            }
        }

        // Validate that the relayer has sent enough gas for the call.
        if (gasleft() <= totalGas / 63) {
            assembly {
                invalid()
            }
        }
        emit GenericGasConsumed("ExecutionGas", gasLeft - gasleft());

        gasLeft = gasleft();
        attendance[_windowIdentifier(block.number)][
            relayerIndexToRelayer[_cdfIndex]
        ] = true;
        emit GenericGasConsumed("OtherOverhead", gasLeft - gasleft());

        return (successes, returndatas);
    }

    function processAbsenceProof(
        // Reporter selection proof in current window
        uint16[] calldata _reporter_cdf,
        uint256[] calldata _reporter_relayerGenerationIterations,
        uint256 _reporter_cdfIndex,
        // Absentee selection proof in arbitrary past window
        uint256 _absentee_blockNumber,
        uint256 _absentee_latestStakeUpdationCdfLogIndex,
        uint16[] calldata _absentee_cdf,
        uint256[] calldata _absentee_relayerGenerationIterations,
        uint256 _absentee_cdfIndex,
        // Other stuff
        uint32[] calldata _currentStakeArray
    )
        public
        verifyCdfHash(_reporter_cdf)
        verifyStakeArrayHash(_currentStakeArray)
    {
        // Verify Reporter Selection in Current Window
        if (
            !_verifyRelayerSelection(
                _reporter_cdf,
                _reporter_cdfIndex,
                _reporter_relayerGenerationIterations,
                block.number
            )
        ) {
            revert("Reporter not selected");
        }

        // The Absentee block must not be in the current window
        uint256 currentWindowStartBlock = block.number -
            (block.number % blocksWindow);
        require(
            _absentee_blockNumber < currentWindowStartBlock,
            "Invalid Absentee Block Number"
        );

        // Verify CDF hash of the Absentee Window
        uint256 absentee_windowId = _windowIdentifier(_absentee_blockNumber);
        if (
            !_verifyPrevCdfHash(
                _absentee_cdf,
                absentee_windowId,
                _absentee_latestStakeUpdationCdfLogIndex
            )
        ) {
            revert("Invalid CDF hash");
        }

        // Verify Relayer Selection in Absentee Window
        if (
            !_verifyRelayerSelection(
                _absentee_cdf,
                _absentee_cdfIndex,
                _absentee_relayerGenerationIterations,
                _absentee_blockNumber
            )
        ) {
            revert("Absentee not selected");
        }

        // Verify Absence of the relayer
        address absentee_relayerAddress = relayerIndexToRelayer[
            _absentee_cdfIndex
        ];
        if (attendance[absentee_windowId][absentee_relayerAddress]) {
            revert("Absentee already present");
        }

        // Process penalty
        uint32 penalty = ((_currentStakeArray[_absentee_cdfIndex] *
            ABSENCE_PENATLY) / 10000).toUint32();
        uint32[] memory newStakeArray = _decreaseStake(
            _currentStakeArray,
            _absentee_cdfIndex,
            penalty
        );
        _updateStakeAccounting(newStakeArray);

        // TODO: Sent reporter the penalty as reward
    }

    function _windowIdentifier(
        uint256 _blockNumber
    ) internal view returns (uint256) {
        return _blockNumber / blocksWindow;
    }

    function _randomCdfNumber(
        uint256 _blockNumber,
        uint256 _iter,
        uint256 _max
    ) internal view returns (uint256 index) {
        // The seed for jth iteration is a function of the base seed and j
        uint256 baseSeed = uint256(
            keccak256(abi.encodePacked(_windowIdentifier(_blockNumber)))
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
        uint16[] calldata arr,
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
        uint16[] calldata _cdf
    )
        public
        view
        verifyCdfHash(_cdf)
        returns (address[] memory, uint256[] memory)
    {
        require(_cdf.length > 0, "No relayers registered");
        require(
            relayerCount >= relayersPerWindow,
            "Insufficient relayers registered"
        );
        if (_blockNumber == 0) {
            _blockNumber = block.number;
        }

        // Generate `relayersPerWindow` pseudo-random distinct relayers
        address[] memory selectedRelayers = new address[](relayersPerWindow);
        uint256[] memory cdfIndex = new uint256[](relayersPerWindow);

        uint256 cdfLength = _cdf.length;
        require(_cdf[cdfLength - 1] > 0, "No relayers registered");

        for (uint256 i = 0; i < relayersPerWindow; ) {
            uint256 randomCdfNumber = _randomCdfNumber(
                _blockNumber,
                i,
                _cdf[cdfLength - 1]
            );
            cdfIndex[i] = _lowerBound(_cdf, randomCdfNumber);
            RelayerInfo storage relayer = relayerInfo[
                relayerIndexToRelayer[cdfIndex[i]]
            ];
            uint256 relayerIndex = relayer.index;
            address relayerAddress = relayerIndexToRelayer[relayerIndex];
            selectedRelayers[i] = relayerAddress;

            unchecked {
                ++i;
            }
        }
        return (selectedRelayers, cdfIndex);
    }

    /// @notice determine what transactions can be relayed by the sender
    /// @param _relayer Address of the relayer to allocate transactions for
    /// @param _blockNumber block number for which the relayers are to be generated
    /// @param _txnCalldata list with all transactions calldata to be filtered
    /// @return txnAllocated list of transactions that can be relayed by the relayer
    /// @return relayerGenerationIteration list of iterations of the relayer generation corresponding
    ///                                    to the selected transactions
    /// @return selectedRelayersCdfIndex index of the selected relayer in the cdf
    function allocateTransaction(
        address _relayer,
        uint256 _blockNumber,
        bytes[] calldata _txnCalldata,
        uint16[] calldata _cdf
    )
        public
        view
        verifyCdfHash(_cdf)
        returns (bytes[] memory, uint256[] memory, uint256)
    {
        if (_blockNumber == 0) {
            _blockNumber = block.number;
        }

        (
            address[] memory relayersAllocated,
            uint256[] memory relayerStakePrefixSumIndex
        ) = allocateRelayers(_blockNumber, _cdf);
        require(relayersAllocated.length == relayersPerWindow, "AT101");

        // Filter the transactions
        uint256 selectedRelayerCdfIndex;
        bytes[] memory txnAllocated = new bytes[](_txnCalldata.length);
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
                selectedRelayerCdfIndex = relayerStakePrefixSumIndex[
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
                relayerGenerationIteration,
                sub(mload(relayerGenerationIteration), extraLength)
            )
        }

        return (
            txnAllocated,
            relayerGenerationIteration,
            selectedRelayerCdfIndex
        );
    }

    function setRelayersPerWindow(
        uint256 _newRelayersPerWindow
    ) external onlyOwner {
        relayersPerWindow = _newRelayersPerWindow;
    }
}
