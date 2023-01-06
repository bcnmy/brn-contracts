import { Wallet } from 'ethers';
import { hexValue, parseEther } from 'ethers/lib/utils';
import { ethers, network } from 'hardhat';
import { BicoForwarder } from '../typechain-types';
import { createObjectCsvWriter } from 'csv-writer';
import { resolve } from 'path';

const windowLength = 10;

const totalRelayers = 500;
const blockNumber = 12313110;
const relayersPerWindowStart = 1;
const relayersPerWindowEnd = Math.min(100, totalRelayers);

const deploy = async () => {
  console.log('Deploying contract...');
  const TxnAllocator = await ethers.getContractFactory('BicoForwarder');
  const txnAllocator = await TxnAllocator.deploy(
    windowLength,
    windowLength,
    relayersPerWindowStart
  );
  return txnAllocator;
};

const setupRelayers = async (txnAllocator: BicoForwarder) => {
  console.log('Setting up relayers...');
  const amount = ethers.utils.parseEther('1');
  await Promise.all(
    new Array(totalRelayers).fill(0).map(async (_, i) => {
      try {
        const multiplier = Math.floor(Math.random() * 10) + 1;
        const randomWallet = new Wallet(ethers.Wallet.createRandom().privateKey, ethers.provider);
        await network.provider.send('hardhat_setBalance', [
          randomWallet.address,
          hexValue(parseEther('1')),
        ]);
        await txnAllocator
          .connect(randomWallet)
          .register(amount.mul(multiplier), [randomWallet.address], 'test');
      } catch (e) {
        console.log(e);
      }
    })
  );
};

const getGasConsumed = async (txnAllocator: BicoForwarder, relayerCount: number) => {
  await txnAllocator.setRelayersPerWindow(relayerCount);
  const gas = await txnAllocator.estimateGas.allocateRelayers(blockNumber);
  const [, iterations] = await txnAllocator.allocateRelayers(blockNumber);
  return [gas, iterations];
};

(async () => {
  const txnAllocator = await deploy();
  await setupRelayers(txnAllocator);
  const data = [];
  for (let i = relayersPerWindowStart; i <= relayersPerWindowEnd; i++) {
    const [gas, iterations] = await getGasConsumed(txnAllocator, i);
    data.push({
      gas,
      iterations,
      relayersPerWindow: i,
      totalRelayers,
    });
    console.log(`Relayers per window: ${i}, Gas consumed: ${gas}, Iterations: ${iterations}`);
  }
  await createObjectCsvWriter({
    path: resolve(__dirname, `allocation-stats-${totalRelayers}.csv`),
    header: Object.keys(data[0]).map((key) => ({ id: key, title: key })),
  }).writeRecords(data);
})();
