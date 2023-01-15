import { BigNumber, ContractReceipt, Wallet } from 'ethers';
import { AbiCoder, hexValue, parseEther } from 'ethers/lib/utils';
import { ethers, network } from 'hardhat';
import { BicoForwarder, TransactionMock, TransactionMock__factory } from '../typechain-types';
import { createObjectCsvWriter } from 'csv-writer';
import { resolve } from 'path';

const windowLength = 1000000;
const totalTransactions = 50;
const totalRelayers = 50;
const relayersPerWindowStart = 5;
const relayersPerWindowEnd = Math.min(100, totalRelayers);

let stakeArray: BigNumber[] = [];

const deploy = async () => {
  console.log('Deploying contract...');
  const [deployer] = await ethers.getSigners();
  const TxnAllocator = await ethers.getContractFactory('BicoForwarder');
  const txnAllocator = await TxnAllocator.deploy(
    windowLength,
    windowLength,
    relayersPerWindowStart
  );
  const txMock = await new TransactionMock__factory(deployer).deploy();
  return { txnAllocator, txMock };
};

const getStakeArray = (txnAllocator: BicoForwarder, transactionReceipt: ContractReceipt) => {
  const logs = transactionReceipt.logs.map((log) => txnAllocator.interface.parseLog(log));
  const stakeArrayLog = logs.find((log) => log.name === 'StakePercArrayUpdated');
  if (!stakeArrayLog) throw new Error(`Stake array not found in logs:${logs}`);
  return stakeArrayLog.args.stakePercArray;
};

const setupRelayers = async (txnAllocator: BicoForwarder, count: number) => {
  console.log('Setting up relayers...');
  const amount = ethers.utils.parseEther('1');
  const wallets = [];
  for (let i = 0; i < count; i++) {
    try {
      const multiplier = Math.floor(Math.random() * 10) + 1;
      const randomWallet = new Wallet(ethers.Wallet.createRandom().privateKey, ethers.provider);
      await network.provider.send('hardhat_setBalance', [
        randomWallet.address,
        hexValue(parseEther('1')),
      ]);
      const { wait } = await txnAllocator
        .connect(randomWallet)
        .register(stakeArray, amount.mul(multiplier), [randomWallet.address], 'test');
      const receipt = await wait();
      stakeArray = getStakeArray(txnAllocator, receipt);
      console.log(`Relayer ${i} registered successfully with ${multiplier} ETH`);
      console.log(`Stake array: ${stakeArray}`);
      wallets.push(randomWallet);
    } catch (e) {
      console.log(e);
    }
  }
  return wallets;
};

const getVerificationGasConsumed = async (
  txnAllocator: BicoForwarder,
  transactionReceipt: ContractReceipt
) => {
  const totalGas = transactionReceipt.gasUsed;
  const logs = transactionReceipt.logs
    .map((log) => {
      try {
        return txnAllocator.interface.parseLog(log);
      } catch (e) {}
    })
    .filter((log) => log);
  const executionGasLog = logs.find((log) => log!.name === 'ExecutionGasConsumed');
  if (!executionGasLog) throw new Error(`Execution gas log not found in logs:${logs}`);
  const executionGas = executionGasLog.args.gasConsumed;
  console.log('Total Gas: ', totalGas.toString(), ', Execution gas:', executionGas);
  return totalGas.sub(executionGasLog.args.gasConsumed);
};

const generateTransactions = async (txMock: TransactionMock, count: number) => {
  return new Array(count)
    .fill(0)
    .map((_, i) => txMock.interface.encodeFunctionData('mockUpdate', [i]));
};

(async () => {
  const csvData: any[] = [];

  const { txnAllocator, txMock } = await deploy();
  console.log('Generating transactions...');
  const txns = await generateTransactions(txMock, totalTransactions);
  console.log('Transactions generated');
  const relayers = await setupRelayers(txnAllocator, totalRelayers);

  console.log('Executing transactions...');
  for (let i = 0; i < relayers.length; i++) {
    const relayer = relayers[i];
    const blockNumber = await ethers.provider.getBlockNumber();
    const [txnAllocated, selectedRelayerPdfIndex, relayerGenerationIteration] =
      await txnAllocator.allocateTransaction(relayer.address, blockNumber, txns, stakeArray);
    console.log(`Alloted ${txnAllocated.length} transactions to ${i}th relayer ${relayer.address}`);
    for (let j = 0; j < txnAllocated.length; j++) {
      const data = txnAllocated[j];
      const { wait } = await txnAllocator.connect(relayer).execute(
        {
          from: relayer.address,
          to: txMock.address,
          value: 0,
          gas: 1000000,
          nonce: 0,
          data,
        },
        new AbiCoder().encode(['uint256'], [0]),
        stakeArray,
        relayerGenerationIteration[j],
        selectedRelayerPdfIndex[j]
      );
      const receipt = await wait();
      if (receipt.status === 0) throw new Error(`Transaction failed: ${receipt}`);
      const gasUsed = await getVerificationGasConsumed(txnAllocator, receipt);
      console.log(`Verification Gas used for ${j}th transaction for ${i}th relayer: ${gasUsed}`);

      csvData.push({
        relayerCount: totalRelayers,
        gasUsed: gasUsed.toString(),
      });
    }
  }

  await createObjectCsvWriter({
    path: resolve(__dirname, `allocation-stats-${totalRelayers}.csv`),
    header: Object.keys(csvData[0]).map((key) => ({ id: key, title: key })),
  }).writeRecords(csvData);
})();
