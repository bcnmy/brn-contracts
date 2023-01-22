import { loadFixture } from '@nomicfoundation/hardhat-network-helpers';
import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers';
import { expect } from 'chai';
import { BigNumber, BigNumberish } from 'ethers';
import { AbiCoder, keccak256, parseEther, solidityPack } from 'ethers/lib/utils';
import { ethers } from 'hardhat';
import { TransactionAllocator__factory, TransactionMock__factory } from '../typechain-types';

const IRelayer = {
  main: SignerWithAddress,
  relayers: Array<SignerWithAddress>,
};

describe('BRN', function () {
  const blocksWindow = 10;
  const withdrawDelay = 1;
  const relayersPerWindow = 2;

  async function deploy() {
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

    const txnAllocator = await new TransactionAllocator__factory(deployer).deploy(
      blocksWindow,
      withdrawDelay,
      relayersPerWindow
    );

    const transactionMock = await new TransactionMock__factory(deployer).deploy();

    return {
      relayers: [
        {
          main: relayer1,
          accounts: [relayer1Acc1, relayer1Acc2],
        },
        {
          main: relayer2,
          accounts: [relayer2Acc1, relayer2Acc2],
        },
        {
          main: relayer3,
          accounts: [relayer3Acc1, relayer3Acc2],
        },
      ],
      blocksWindow,
      withdrawDelay,
      relayersPerWindow,
      txnAllocator,
      transactionMock,
    };
  }

  async function deployAndConfigure(relayerStake: BigNumberish[]) {
    const deployData = await loadFixture(deploy);
    let i = 0;
    for (const relayer of deployData.relayers) {
      await deployData.txnAllocator.connect(relayer.main).register(
        await deployData.txnAllocator.getStakeArray(),
        relayerStake[i++],
        relayer.accounts.map((acc) => acc.address),
        'test-endpoint'
      );
    }
    return deployData;
  }

  describe('Deployment', function () {
    it('Should set the right blocksWindow', async function () {
      const { blocksWindow, txnAllocator } = await loadFixture(deploy);

      expect(await txnAllocator.blocksWindow()).to.equal(blocksWindow);
    });

    it('Should set the right withdrawDelay', async function () {
      const { withdrawDelay, txnAllocator } = await loadFixture(deploy);

      expect(await txnAllocator.withdrawDelay()).to.equal(withdrawDelay);
    });

    it('Should set the right realyersPerWindow', async function () {
      const { relayersPerWindow, txnAllocator } = await loadFixture(deploy);

      expect(await txnAllocator.relayersPerWindow()).to.equal(relayersPerWindow);
    });
  });

  describe('Registration', function () {
    it('Should register a relayer', async function () {
      const { relayers, txnAllocator } = await loadFixture(deploy);
      const relayerAccounts = relayers[0].accounts.map((acc) => acc.address);
      const txn = await txnAllocator
        .connect(relayers[0].main)
        .register([], ethers.utils.parseEther('1'), relayerAccounts, 'endpoint');
      const rc = await txn.wait();
      const filter = txnAllocator.filters.RelayerRegistered();
      //@ts-ignore
      const fromBlock = await ethers.provider.getBlock();
      const events = await txnAllocator.queryFilter(filter, fromBlock.number);

      expect(events[0].args.stake).to.be.equal(ethers.utils.parseEther('1'));
      expect(events[0].args.accounts[0]).to.be.equal(relayerAccounts[0]);
      expect(events[0].args.accounts[1]).to.be.equal(relayerAccounts[1]);
      expect(events[0].args.endpoint).to.be.equal('endpoint');
    });
  });

  describe('Relayer Selection', function () {
    it('Should select random relayers', async function () {
      const { relayers, relayersPerWindow, txnAllocator, transactionMock } =
        await deployAndConfigure([parseEther('1'), parseEther('2'), parseEther('2')]);
      const blockNumber = await ethers.provider.getBlockNumber();
      const [selectedRelayers] = await txnAllocator.allocateRelayers(
        blockNumber,
        await txnAllocator.getCdf()
      );
      expect(selectedRelayers.length).to.be.equal(relayersPerWindow);
      const relayerAddresses = relayers.map((r) => r.main.address);
      expect(relayerAddresses.includes(selectedRelayers[0])).to.be.true;
      expect(relayerAddresses.includes(selectedRelayers[1])).to.be.true;
    });

    it('Should select random relayers deterministically', async function () {
      const { relayers, relayersPerWindow, txnAllocator, transactionMock } =
        await deployAndConfigure([parseEther('1'), parseEther('2'), parseEther('2')]);
      const blockNumber = await ethers.provider.getBlockNumber();

      const [selectedRelayersMain] = await txnAllocator.allocateRelayers(
        blockNumber,
        await txnAllocator.getCdf()
      );

      for (let i = 0; i < 10; i++) {
        const [selectedRelayers] = await txnAllocator.allocateRelayers(
          blockNumber,
          await txnAllocator.getCdf()
        );
        expect(selectedRelayers).to.deep.equal(selectedRelayersMain);
      }
    });

    it('Should return the same set of relayers for the same window', async function () {
      const { relayers, relayersPerWindow, txnAllocator, transactionMock } =
        await deployAndConfigure([parseEther('1'), parseEther('2'), parseEther('2')]);
      const blockNumber = await ethers.provider.getBlockNumber();
      const start = blockNumber - (blockNumber % relayersPerWindow);
      const end = start + relayersPerWindow - 1;

      const [selectedRelayersMain] = await txnAllocator.allocateRelayers(
        blockNumber,
        await txnAllocator.getCdf()
      );

      for (let i = start; i <= end; i++) {
        const [selectedRelayers] = await txnAllocator.allocateRelayers(
          i,
          await txnAllocator.getCdf()
        );
        expect(selectedRelayers).to.deep.equal(selectedRelayersMain);
      }
    });

    it('Should return correct cdf index for selected relayers', async function () {
      const { relayersPerWindow, txnAllocator, blocksWindow } = await deployAndConfigure([
        parseEther('1'),
        parseEther('2'),
        parseEther('2'),
      ]);
      const blockNumber = await ethers.provider.getBlockNumber();
      const cdf = await txnAllocator.getCdf();
      const [, cdfIndex] = await txnAllocator.allocateRelayers(blockNumber, cdf);

      const isCdfIndexCorrect = (cdfIndex: number, iteration: number) => {
        const baseSeed = keccak256(
          solidityPack(['uint256'], [BigNumber.from(blockNumber).div(blocksWindow)])
        );
        const randomStake = BigNumber.from(
          keccak256(solidityPack(['bytes32', 'uint256'], [baseSeed, iteration]))
        ).mod(cdf[cdf.length - 1]);

        return (
          (cdfIndex === 0 || randomStake.gt(cdf[cdfIndex - 1])) && randomStake.lte(cdf[cdfIndex])
        );
      };

      expect(cdfIndex.length).equal(relayersPerWindow);
      expect(isCdfIndexCorrect(cdfIndex[0].toNumber(), 0)).to.be.true;
      expect(isCdfIndexCorrect(cdfIndex[1].toNumber(), 1)).to.be.true;
    });
  });

  describe('Transaction Allocation', function () {
    const inclusionCount = <T>(item: T, arrs: T[][]) =>
      arrs.filter((arr) => arr.includes(item)).length;

    it('Should allocate transaction', async function () {
      const { relayers, txnAllocator, transactionMock } = await deployAndConfigure([
        parseEther('1'),
        parseEther('2'),
        parseEther('2'),
      ]);

      const calldataAdd = transactionMock.interface.encodeFunctionData('mockAdd', ['1', '2']);
      const calldataSub = transactionMock.interface.encodeFunctionData('mockSubtract', ['12', '2']);
      const calldataUpd = transactionMock.interface.encodeFunctionData('mockUpdate', ['12']);

      const blockNumber = 123;
      const [txnAllocated1] = await txnAllocator.allocateTransaction(
        relayers[0].accounts[0].address,
        blockNumber,
        [calldataAdd, calldataSub, calldataUpd],
        await txnAllocator.getCdf()
      );
      const [txnAllocated2] = await txnAllocator.allocateTransaction(
        relayers[1].accounts[0].address,
        blockNumber,
        [calldataAdd, calldataSub, calldataUpd],
        await txnAllocator.getCdf()
      );
      const [txnAllocated3] = await txnAllocator.allocateTransaction(
        relayers[2].accounts[0].address,
        blockNumber,
        [calldataAdd, calldataSub, calldataUpd],
        await txnAllocator.getCdf()
      );

      expect(txnAllocated1.length + txnAllocated2.length + txnAllocated3.length).to.be.equal(3);
      expect(
        inclusionCount(calldataAdd, [txnAllocated1, txnAllocated2, txnAllocated3])
      ).to.be.equal(1);
      expect(
        inclusionCount(calldataSub, [txnAllocated1, txnAllocated2, txnAllocated3])
      ).to.be.equal(1);
      expect(
        inclusionCount(calldataUpd, [txnAllocated1, txnAllocated2, txnAllocated3])
      ).to.be.equal(1);
    });
  });

  describe('Transaction Verification', async function () {
    it('Should allow relayer 1 to execute transaction', async function () {
      const { relayers, txnAllocator, transactionMock } = await deployAndConfigure([
        parseEther('2'),
        parseEther('2'),
        parseEther('2'),
      ]);

      const calldataArray = new Array(10)
        .fill(1)
        .map((_, n) => transactionMock.interface.encodeFunctionData('mockUpdate', [n]));
      const blockNumber = 0;

      const [txnAllocated, relayerGenerationIteration, selectedCdfIndex] =
        await txnAllocator.allocateTransaction(
          relayers[1].accounts[0].address,
          blockNumber,
          calldataArray,
          await txnAllocator.getCdf()
        );

      expect(txnAllocated.length).to.be.greaterThan(0);

      for (let i = 0; i < txnAllocated.length; i++) {
        await expect(
          txnAllocator.connect(relayers[1].accounts[1]).execute(
            [
              {
                from: relayers[1].accounts[0].address,
                to: transactionMock.address,
                value: 0,
                gas: 100000,
                nonce: 0,
                data: txnAllocated[i],
              },
            ],
            new AbiCoder().encode(['uint256'], [0]),
            await txnAllocator.getCdf(),
            relayerGenerationIteration,
            selectedCdfIndex
          )
        ).to.not.be.reverted;
      }
    });

    it('Should revert if non-selected relayer tries to submit transaction', async function () {
      const { relayers, txnAllocator, transactionMock } = await deployAndConfigure([
        parseEther('2'),
        parseEther('2'),
        parseEther('2'),
      ]);

      const calldataArray = new Array(10)
        .fill(1)
        .map((_, n) => transactionMock.interface.encodeFunctionData('mockUpdate', [n]));
      const blockNumber = 0;

      const [txnAllocated, relayerGenerationIteration, selectedCdfIndex] =
        await txnAllocator.allocateTransaction(
          relayers[1].accounts[0].address,
          blockNumber,
          calldataArray,
          await txnAllocator.getCdf()
        );

      expect(txnAllocated.length).to.be.greaterThan(0);

      for (let i = 0; i < txnAllocated.length; i++) {
        await expect(
          txnAllocator.connect(relayers[0].accounts[0]).execute(
            [
              {
                from: relayers[1].accounts[0].address,
                to: transactionMock.address,
                value: 0,
                gas: 100000,
                nonce: 0,
                data: txnAllocated[i],
              },
            ],
            new AbiCoder().encode(['uint256'], [0]),
            await txnAllocator.getCdf(),
            relayerGenerationIteration,
            selectedCdfIndex
          )
        ).to.be.revertedWithCustomError(txnAllocator, 'InvalidRelayerWindow');
      }
    });
  });
});
