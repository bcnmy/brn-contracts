import { loadFixture } from '@nomicfoundation/hardhat-network-helpers';
import { expect } from 'chai';
import { AbiCoder } from 'ethers/lib/utils';
import { ethers } from 'hardhat';

describe('BRN', function () {
  const blocksWindow = 10;
  const withdrawDelay = 1;
  const relayersPerWindow = 2;

  async function deployTxnAllocator() {
    const [
      deployer,
      relayer1,
      relayer1Acc1,
      relayer1Acc2,
      relayer2,
      relayer2Acc1,
      relayer2Acc2,
      relayer3,
      relayer3Acc1,
      relayer3Acc2,
    ] = await ethers.getSigners();

    const TxnAllocator = await ethers.getContractFactory('TransactionAllocator');
    const txnAllocator = await TxnAllocator.deploy(blocksWindow, withdrawDelay, relayersPerWindow);

    const TransactionMock = await ethers.getContractFactory('TransactionMock');
    const transactionMock = await TransactionMock.deploy();

    return {
      relayer1,
      relayer1Acc1,
      relayer1Acc2,
      relayer2,
      relayer2Acc1,
      relayer2Acc2,
      relayer3,
      relayer3Acc1,
      relayer3Acc2,
      blocksWindow,
      withdrawDelay,
      relayersPerWindow,
      TxnAllocator,
      txnAllocator,
      TransactionMock,
      transactionMock,
    };
  }

  describe('Deployment', function () {
    it('Should set the right blocksWindow', async function () {
      const { blocksWindow, txnAllocator } = await loadFixture(deployTxnAllocator);

      expect(await txnAllocator.blocksWindow()).to.equal(blocksWindow);
    });

    it('Should set the right withdrawDelay', async function () {
      const { withdrawDelay, txnAllocator } = await loadFixture(deployTxnAllocator);

      expect(await txnAllocator.withdrawDelay()).to.equal(withdrawDelay);
    });

    it('Should set the right realyersPerWindow', async function () {
      const { relayersPerWindow, txnAllocator } = await loadFixture(deployTxnAllocator);

      expect(await txnAllocator.relayersPerWindow()).to.equal(relayersPerWindow);
    });
  });

  describe('Registration', function () {
    it('Should register a relayer', async function () {
      const {
        relayer1,
        relayer1Acc1,
        relayer1Acc2,
        TransactionMock,
        txnAllocator,
        transactionMock,
      } = await loadFixture(deployTxnAllocator);
      const txn = await txnAllocator
        .connect(relayer1)
        .register(
          [],
          ethers.utils.parseEther('1'),
          [relayer1Acc1.address, relayer1Acc2.address],
          'endpoint'
        );
      const rc = await txn.wait();
      const filter = txnAllocator.filters.RelayerRegistered();
      //@ts-ignore
      const fromBlock = await ethers.provider.getBlock();
      const events = await txnAllocator.queryFilter(filter, fromBlock.number);

      expect(events[0].args.stake).to.be.equal(ethers.utils.parseEther('1'));
      expect(events[0].args.accounts[0]).to.be.equal(relayer1Acc1.address);
      expect(events[0].args.accounts[1]).to.be.equal(relayer1Acc2.address);
      expect(events[0].args.endpoint).to.be.equal('endpoint');
    });
  });

  describe('Relayer Selection', function () {
    it('Should select random relayers', async function () {
      const {
        relayer1,
        relayer1Acc1,
        relayer1Acc2,
        relayer2,
        relayer2Acc1,
        relayer2Acc2,
        relayer3,
        relayer3Acc1,
        relayer3Acc2,
        relayersPerWindow,
        txnAllocator,
      } = await loadFixture(deployTxnAllocator);
      await txnAllocator
        .connect(relayer1)
        .register(
          [],
          ethers.utils.parseEther('1'),
          [relayer1Acc1.address, relayer1Acc2.address],
          'endpoint'
        );
      await txnAllocator
        .connect(relayer2)
        .register(
          [100],
          ethers.utils.parseEther('2'),
          [relayer2Acc1.address, relayer2Acc2.address],
          'endpoint'
        );
      await txnAllocator
        .connect(relayer3)
        .register(
          [33, 66],
          ethers.utils.parseEther('2'),
          [relayer3Acc1.address, relayer3Acc2.address],
          'endpoint'
        );
      //TODO: should add set to particular block
      const [selectedRelayers] = await txnAllocator.allocateRelayers(123, [19, 39, 40]);
      expect(selectedRelayers.length).to.be.equal(relayersPerWindow);
      expect(selectedRelayers[0]).to.be.equal(relayer1.address);
      expect(selectedRelayers[1]).to.be.equal(relayer3.address);
    });

    it('Should select random relayers deterministically', async function () {
      const {
        relayer1,
        relayer1Acc1,
        relayer1Acc2,
        relayer2,
        relayer2Acc1,
        relayer2Acc2,
        relayer3,
        relayer3Acc1,
        relayer3Acc2,
        relayersPerWindow,
        txnAllocator,
      } = await loadFixture(deployTxnAllocator);
      await txnAllocator
        .connect(relayer1)
        .register(
          [],
          ethers.utils.parseEther('1'),
          [relayer1Acc1.address, relayer1Acc2.address],
          'endpoint'
        );
      await txnAllocator
        .connect(relayer2)
        .register(
          [100],
          ethers.utils.parseEther('2'),
          [relayer2Acc1.address, relayer2Acc2.address],
          'endpoint'
        );
      await txnAllocator
        .connect(relayer3)
        .register(
          [33, 66],
          ethers.utils.parseEther('2'),
          [relayer3Acc1.address, relayer3Acc2.address],
          'endpoint'
        );
      for (let i = 0; i < 10; i++) {
        const [selectedRelayers] = await txnAllocator.allocateRelayers(123, [19, 39, 40]);
        expect(selectedRelayers.length).to.be.equal(relayersPerWindow);
        expect(selectedRelayers[0]).to.be.equal(relayer1.address);
        expect(selectedRelayers[1]).to.be.equal(relayer3.address);
      }
    });

    it('Should return the same set of relayers for the same window', async function () {
      const {
        relayer1,
        relayer1Acc1,
        relayer1Acc2,
        relayer2,
        relayer2Acc1,
        relayer2Acc2,
        relayer3,
        relayer3Acc1,
        relayer3Acc2,
        relayersPerWindow,
        txnAllocator,
      } = await loadFixture(deployTxnAllocator);
      await txnAllocator
        .connect(relayer1)
        .register(
          [],
          ethers.utils.parseEther('1'),
          [relayer1Acc1.address, relayer1Acc2.address],
          'endpoint'
        );
      await txnAllocator
        .connect(relayer2)
        .register(
          [100],
          ethers.utils.parseEther('2'),
          [relayer2Acc1.address, relayer2Acc2.address],
          'endpoint'
        );
      await txnAllocator
        .connect(relayer3)
        .register(
          [33, 66],
          ethers.utils.parseEther('2'),
          [relayer3Acc1.address, relayer3Acc2.address],
          'endpoint'
        );
      const block = 123;
      const start = block - (block % relayersPerWindow);
      const end = start + relayersPerWindow - 1;

      for (let i = start; i <= end; i++) {
        const [selectedRelayers] = await txnAllocator.allocateRelayers(i, [19, 39, 40]);
        expect(selectedRelayers.length).to.be.equal(relayersPerWindow);
        expect(selectedRelayers[0]).to.be.equal(relayer1.address);
        expect(selectedRelayers[1]).to.be.equal(relayer3.address);
      }
    });

    it('Should return correct pdf index for selected relayers', async function () {
      const {
        relayer1,
        relayer1Acc1,
        relayer1Acc2,
        relayer2,
        relayer2Acc1,
        relayer2Acc2,
        relayer3,
        relayer3Acc1,
        relayer3Acc2,
        relayersPerWindow,
        txnAllocator,
      } = await loadFixture(deployTxnAllocator);
      await txnAllocator
        .connect(relayer1)
        .register(
          [],
          ethers.utils.parseEther('1'),
          [relayer1Acc1.address, relayer1Acc2.address],
          'endpoint'
        );
      await txnAllocator
        .connect(relayer2)
        .register(
          [100],
          ethers.utils.parseEther('2'),
          [relayer2Acc1.address, relayer2Acc2.address],
          'endpoint'
        );
      await txnAllocator
        .connect(relayer3)
        .register(
          [33, 66],
          ethers.utils.parseEther('2'),
          [relayer3Acc1.address, relayer3Acc2.address],
          'endpoint'
        );

      const block = 123;
      const [, pdfIndex] = await txnAllocator.allocateRelayers(block, [19, 39, 40]);
      expect(pdfIndex.length).equal(relayersPerWindow);
      expect(pdfIndex[0]).equal(0);
      expect(pdfIndex[1]).equal(2);
    });
  });

  describe('Transaction Allocation', function () {
    it('Should allocate transaction', async function () {
      const {
        relayer1,
        relayer1Acc1,
        relayer1Acc2,
        TransactionMock,
        relayer2,
        relayer2Acc1,
        relayer2Acc2,
        relayer3,
        relayer3Acc1,
        relayer3Acc2,
        txnAllocator,
        transactionMock,
      } = await loadFixture(deployTxnAllocator);
      await txnAllocator
        .connect(relayer1)
        .register(
          [],
          ethers.utils.parseEther('1'),
          [relayer1Acc1.address, relayer1Acc2.address],
          'endpoint'
        );
      await txnAllocator
        .connect(relayer2)
        .register(
          [100],
          ethers.utils.parseEther('2'),
          [relayer2Acc1.address, relayer2Acc2.address],
          'endpoint'
        );
      await txnAllocator
        .connect(relayer3)
        .register(
          [33, 66],
          ethers.utils.parseEther('2'),
          [relayer3Acc1.address, relayer3Acc2.address],
          'endpoint'
        );

      const calldataAdd = TransactionMock.interface.encodeFunctionData('mockAdd', ['1', '2']);
      const calldataSub = TransactionMock.interface.encodeFunctionData('mockSubtract', ['12', '2']);
      const calldataUpd = TransactionMock.interface.encodeFunctionData('mockUpdate', ['12']);

      const blockNumber = 123;
      const [txnAllocated1] = await txnAllocator.allocateTransaction(
        relayer1Acc1.address,
        blockNumber,
        [calldataAdd, calldataSub, calldataUpd],
        [19, 39, 40]
      );
      const [txnAllocated2] = await txnAllocator.allocateTransaction(
        relayer2Acc1.address,
        blockNumber,
        [calldataAdd, calldataSub, calldataUpd],
        [19, 39, 40]
      );
      const [txnAllocated3] = await txnAllocator.allocateTransaction(
        relayer3Acc1.address,
        blockNumber,
        [calldataAdd, calldataSub, calldataUpd],
        [19, 39, 40]
      );

      expect(txnAllocated1.length).to.be.equal(1);
      expect(txnAllocated2.length).to.be.equal(0);
      expect(txnAllocated3.length).to.be.equal(2);
    });

    it('Should return correct relayer stake prefix sum with alloted transaction', async function () {
      const {
        relayer1,
        relayer1Acc1,
        relayer1Acc2,
        TransactionMock,
        relayer2,
        relayer2Acc1,
        relayer2Acc2,
        relayer3,
        relayer3Acc1,
        relayer3Acc2,
        txnAllocator,
        transactionMock,
      } = await loadFixture(deployTxnAllocator);
      await txnAllocator
        .connect(relayer1)
        .register(
          [],
          ethers.utils.parseEther('1'),
          [relayer1Acc1.address, relayer1Acc2.address],
          'endpoint'
        );
      await txnAllocator
        .connect(relayer2)
        .register(
          [100],
          ethers.utils.parseEther('2'),
          [relayer2Acc1.address, relayer2Acc2.address],
          'endpoint'
        );
      await txnAllocator
        .connect(relayer3)
        .register(
          [33, 66],
          ethers.utils.parseEther('2'),
          [relayer3Acc1.address, relayer3Acc2.address],
          'endpoint'
        );

      const calldataAdd = TransactionMock.interface.encodeFunctionData('mockAdd', ['1', '2']);
      const calldataSub = TransactionMock.interface.encodeFunctionData('mockSubtract', ['12', '2']);
      const calldataUpd = TransactionMock.interface.encodeFunctionData('mockUpdate', ['12']);

      const blockNumber = 123;
      const [, stakePrefixSumIndex1] = await txnAllocator.allocateTransaction(
        relayer1Acc1.address,
        blockNumber,
        [calldataAdd, calldataSub, calldataUpd],
        [19, 39, 40]
      );
      const [, stakePrefixSumIndex2] = await txnAllocator.allocateTransaction(
        relayer2Acc1.address,
        blockNumber,
        [calldataAdd, calldataSub, calldataUpd],
        [19, 39, 40]
      );
      const [, stakePrefixSumIndex3] = await txnAllocator.allocateTransaction(
        relayer3Acc1.address,
        blockNumber,
        [calldataAdd, calldataSub, calldataUpd],
        [19, 39, 40]
      );

      expect(stakePrefixSumIndex1.length).to.be.equal(1);
      expect(stakePrefixSumIndex2.length).to.be.equal(0);
      expect(stakePrefixSumIndex3.length).to.be.equal(2);
    });

    it('Should return correct relayer generation iteration with allotted transaction', async function () {
      const {
        relayer1,
        relayer1Acc1,
        relayer1Acc2,
        TransactionMock,
        relayer2,
        relayer2Acc1,
        relayer2Acc2,
        relayer3,
        relayer3Acc1,
        relayer3Acc2,
        txnAllocator,
        transactionMock,
      } = await loadFixture(deployTxnAllocator);
      await txnAllocator
        .connect(relayer1)
        .register(
          [],
          ethers.utils.parseEther('1'),
          [relayer1Acc1.address, relayer1Acc2.address],
          'endpoint'
        );
      await txnAllocator
        .connect(relayer2)
        .register(
          [100],
          ethers.utils.parseEther('2'),
          [relayer2Acc1.address, relayer2Acc2.address],
          'endpoint'
        );
      await txnAllocator
        .connect(relayer3)
        .register(
          [33, 66],
          ethers.utils.parseEther('2'),
          [relayer3Acc1.address, relayer3Acc2.address],
          'endpoint'
        );

      const calldataAdd = TransactionMock.interface.encodeFunctionData('mockAdd', ['1', '2']);
      const calldataSub = TransactionMock.interface.encodeFunctionData('mockSubtract', ['12', '2']);
      const calldataUpd = TransactionMock.interface.encodeFunctionData('mockUpdate', ['12']);

      const blockNumber = 123;

      const [, , relayerGenerationIter1] = await txnAllocator.allocateTransaction(
        relayer1Acc1.address,
        blockNumber,
        [calldataAdd, calldataSub, calldataUpd],
        [19, 39, 40]
      );
      const [, , relayerGenerationIter2] = await txnAllocator.allocateTransaction(
        relayer2Acc1.address,
        blockNumber,
        [calldataAdd, calldataSub, calldataUpd],
        [19, 39, 40]
      );
      const [, , relayerGenerationIter3] = await txnAllocator.allocateTransaction(
        relayer3Acc1.address,
        blockNumber,
        [calldataAdd, calldataSub, calldataUpd],
        [19, 39, 40]
      );

      expect(relayerGenerationIter1.length).to.be.equal(1);
      expect(relayerGenerationIter2.length).to.be.equal(0);
      expect(relayerGenerationIter3.length).to.be.equal(2);
    });
  });

  describe('Transaction Verification', async function () {
    it('Should allow relayer 1 to execute transaction', async function () {
      const {
        relayer1,
        relayer1Acc1,
        relayer1Acc2,
        TransactionMock,
        relayer2,
        relayer2Acc1,
        relayer2Acc2,
        relayer3,
        relayer3Acc1,
        relayer3Acc2,
        txnAllocator,
        transactionMock,
      } = await loadFixture(deployTxnAllocator);
      await txnAllocator
        .connect(relayer1)
        .register(
          [],
          ethers.utils.parseEther('2'),
          [relayer1Acc1.address, relayer1Acc2.address],
          'endpoint'
        );
      await txnAllocator
        .connect(relayer2)
        .register(
          [100],
          ethers.utils.parseEther('2'),
          [relayer2Acc1.address, relayer2Acc2.address],
          'endpoint'
        );
      await txnAllocator
        .connect(relayer3)
        .register(
          [50, 50],
          ethers.utils.parseEther('2'),
          [relayer3Acc1.address, relayer3Acc2.address],
          'endpoint'
        );

      const calldataArray = new Array(10)
        .fill(1)
        .map((_, n) => TransactionMock.interface.encodeFunctionData('mockUpdate', [n]));
      const blockNumber = 0;

      const [txnAllocated, selectedpdfIndex, relayerGenerationIteration] =
        await txnAllocator.allocateTransaction(
          relayer2Acc1.address,
          blockNumber,
          calldataArray,
          [33, 33, 33]
        );

      expect(txnAllocated.length).to.be.greaterThan(0);

      for (let i = 0; i < txnAllocated.length; i++) {
        await expect(
          txnAllocator.connect(relayer2Acc1).execute(
            {
              from: relayer2Acc1.address,
              to: transactionMock.address,
              value: 0,
              gas: 100000,
              nonce: 0,
              data: txnAllocated[i],
            },
            new AbiCoder().encode(['uint256'], [0]),
            [33, 33, 33],
            relayerGenerationIteration[i],
            selectedpdfIndex[i]
          )
        ).to.not.be.reverted;
      }
    });

    it('Should revert if non-selected relayer tries to submit transaction', async function () {
      const {
        relayer1,
        relayer1Acc1,
        relayer1Acc2,
        TransactionMock,
        relayer2,
        relayer2Acc1,
        relayer2Acc2,
        relayer3,
        relayer3Acc1,
        relayer3Acc2,
        txnAllocator,
        transactionMock,
      } = await loadFixture(deployTxnAllocator);
      await txnAllocator
        .connect(relayer1)
        .register(
          [],
          ethers.utils.parseEther('2'),
          [relayer1Acc1.address, relayer1Acc2.address],
          'endpoint'
        );
      await txnAllocator
        .connect(relayer2)
        .register(
          [100],
          ethers.utils.parseEther('2'),
          [relayer2Acc1.address, relayer2Acc2.address],
          'endpoint'
        );
      await txnAllocator
        .connect(relayer3)
        .register(
          [50, 50],
          ethers.utils.parseEther('2'),
          [relayer3Acc1.address, relayer3Acc2.address],
          'endpoint'
        );

      const calldataArray = new Array(10)
        .fill(1)
        .map((_, n) => TransactionMock.interface.encodeFunctionData('mockUpdate', [n]));
      const blockNumber = 0;

      const [txnAllocated, selectedpdfIndex, relayerGenerationIteration] =
        await txnAllocator.allocateTransaction(
          relayer2Acc1.address,
          blockNumber,
          calldataArray,
          [33, 33, 33]
        );

      expect(txnAllocated.length).to.be.greaterThan(0);

      for (let i = 0; i < txnAllocated.length; i++) {
        await expect(
          txnAllocator.connect(relayer1Acc1).execute(
            {
              from: relayer2Acc1.address,
              to: transactionMock.address,
              value: 0,
              gas: 100000,
              nonce: 0,
              data: txnAllocated[i],
            },
            new AbiCoder().encode(['uint256'], [0]),
            [33, 33, 33],
            relayerGenerationIteration[i],
            selectedpdfIndex[i]
          )
        ).to.be.revertedWith('invalid relayer window');
      }
    });
  });
});
