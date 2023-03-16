import { BigNumber, BigNumberish, ContractReceipt, Wallet } from 'ethers';
import { hexValue, parseEther } from 'ethers/lib/utils';
import { ethers, network } from 'hardhat';
import { ITransactionAllocator, ApplicationMock } from '../typechain-types';
import { deploy } from './deploy';
import { createObjectCsvWriter } from 'csv-writer';
import { resolve } from 'path';
import { mkdirSync, existsSync } from 'fs';
import { ForwardRequestStruct } from '../typechain-types/src/transaction-allocator/interfaces/ITransactionAllocator';

const totalTransactions = 50;
const totalRelayers = 15;

const blocksPerWindow = 1000000;
const relayersPerWindow = 10;
const penaltyDelayBlocks = 10;
const withdrawDelay = 10;

let stakeArray: BigNumberish[] = [];
let cdfArray: BigNumberish[] = [];

const getGenericGasConsumption = (
  txnAllocator: ITransactionAllocator,
  transactionReceipt: ContractReceipt
): Record<string, string> => {
  const logs = transactionReceipt.logs
    .map((log) => {
      try {
        return txnAllocator.interface.parseLog(log);
      } catch (e) {}
    })
    .filter((log) => log);
  const gasLogs = logs.filter((log) => log!.name === 'GenericGasConsumed');
  if (gasLogs.length == 0) throw new Error(`Gas Log array not found in logs:${logs}`);
  return Object.fromEntries(
    gasLogs.map((log) => [log!.args.label, log!.args.gasConsumed.toString()])
  );
};

const setupRelayers = async (txnAllocator: ITransactionAllocator, count: number) => {
  console.log('Setting up relayers...');
  const amount = ethers.utils.parseEther('10');
  const wallets = [];
  const gasConsumed = [];
  for (let i = 0; i < count; i++) {
    try {
      const multiplier = Math.floor(Math.random() * 10) + 1;
      const randomWallet = new Wallet(ethers.Wallet.createRandom().privateKey, ethers.provider);
      await network.provider.send('hardhat_setBalance', [
        randomWallet.address,
        hexValue(parseEther('100')),
      ]);
      const { wait } = await txnAllocator
        .connect(randomWallet)
        .register(stakeArray, amount.mul(multiplier), [randomWallet.address], 'test');
      const receipt = await wait();
      stakeArray = await txnAllocator.getStakeArray();
      cdfArray = await txnAllocator.getCdf();
      console.log(`Relayer ${i} registered successfully with ${multiplier} ETH`);
      console.log(`Stake array: ${stakeArray}`);
      console.log(`CDF array: ${cdfArray}`);

      gasConsumed.push({
        totalGas: receipt.gasUsed.toString(),
      });
      wallets.push(randomWallet);
    } catch (e) {
      console.log(e);
    }
  }
  return { wallets, gasConsumed };
};

const getGasConsumption = (
  txnAllocator: ITransactionAllocator,
  transactionReceipt: ContractReceipt
): Record<string, BigNumberish> => {
  const totalGas = transactionReceipt.gasUsed;
  const logs = transactionReceipt.logs
    .map((log) => {
      try {
        return txnAllocator.interface.parseLog(log);
      } catch (e) {}
    })
    .filter((log) => log);
  const genericGasConsumedData = getGenericGasConsumption(txnAllocator, transactionReceipt);
  return {
    ...genericGasConsumedData,
    totalGas,
  };
};

const generateTransactions = async (
  txnAllocator: ITransactionAllocator,
  txMock: ApplicationMock,
  count: number
) => {
  const chainId = await ethers.provider.getNetwork().then((n) => n.chainId);
  return Promise.all(
    new Array(count).fill(0).map(async (_, i) => {
      const randomWallet = new Wallet(ethers.Wallet.createRandom().privateKey, ethers.provider);
      await network.provider.send('hardhat_setBalance', [
        randomWallet.address,
        hexValue(parseEther('10')),
      ]);
      const tx: ForwardRequestStruct = {
        to: txMock.address,
        data: txMock.interface.encodeFunctionData('mockUpdate', [i]),
        gasLimit: 1000000,
      };
      return tx;
    })
  );
};

(async () => {
  const allocationCsvData: any[] = [];
  const absenceProofCsvData: any[] = [];

  const today: string = new Date().toLocaleDateString('en-GB').split('/').reverse().join('-');
  existsSync(resolve(__dirname, today)) || mkdirSync(resolve(__dirname, today));

  const { txnAllocator, txMock } = await deploy({
    blocksPerWindow,
    relayersPerWindow,
    penaltyDelayBlocks,
    withdrawDelay,
  });
  console.log('Generating transactions...');
  const txns = await generateTransactions(txnAllocator, txMock, totalTransactions);
  console.log('Transactions generated');
  const { wallets: relayers, gasConsumed: registrationGasConsumed } = await setupRelayers(
    txnAllocator,
    totalRelayers
  );

  const gasConsumedCsvData = registrationGasConsumed.map((gas, index) => ({
    index,
    relayerCount: index + 1,
    ...gas,
  }));

  await createObjectCsvWriter({
    path: resolve(__dirname, today, `registration-stats-${totalRelayers}.csv`),
    header: Object.keys(gasConsumedCsvData[0]).map((key) => ({ id: key, title: key })),
  }).writeRecords(gasConsumedCsvData);

  console.log('Executing transactions...');
  for (let i = 0; i < relayers.length; i++) {
    const relayer = relayers[i];
    const blockNumber = await ethers.provider.getBlockNumber();
    const [txnAllocated, relayerGenerationIteration, selectedRelayerCdfIndex] =
      await txnAllocator.allocateTransaction({
        relayer: relayer.address,
        requests: txns,
        cdf: cdfArray,
      });

    console.log(`Alloted ${txnAllocated.length} transactions to ${i}th relayer ${relayer.address}`);

    if (txnAllocated.length === 0) {
      continue;
    }

    const relayerGenerationIterationDeduplicated = relayerGenerationIteration
      .map((x) => x.toNumber())
      .filter((value, index, self) => self.indexOf(value) === index);

    console.log(
      `Relayer generation iteration for ${i}th relayer: ${relayerGenerationIterationDeduplicated}`
    );

    console.log(`Transaction batch of length ${txnAllocated.length} for ${i}th relayer`);

    const { wait, hash } = await txnAllocator
      .connect(relayer)
      .execute(
        txnAllocated,
        cdfArray,
        relayerGenerationIterationDeduplicated,
        selectedRelayerCdfIndex
      );
    const receipt = await wait();
    if (receipt.status === 0) throw new Error(`Transaction failed: ${receipt}`);
    const { totalGas, VerificationGas, ExecutionGas, OtherOverhead } = getGasConsumption(
      txnAllocator,
      receipt
    );
    console.log(
      `Verification Gas used for transaction batch of length ${
        txnAllocated.length
      } for ${i}th relayer: ${VerificationGas.toString()}. Tx Hash: ${hash}`
    );

    allocationCsvData.push({
      relayerCount: totalRelayers,
      generationIterationCount: relayerGenerationIterationDeduplicated.length,
      txCount: txnAllocated.length,
      totalGas: totalGas.toString(),
      executionGas: ExecutionGas.toString(),
      verificationGas: VerificationGas.toString(),
      verificationGasPerTx: BigNumber.from(VerificationGas).div(txnAllocated.length).toString(),
      otherOverhead: OtherOverhead.toString(),
      totalOverhead: BigNumber.from(VerificationGas).add(OtherOverhead).toString(),
      totalOverheadPerTx: BigNumber.from(VerificationGas)
        .add(OtherOverhead)
        .div(txnAllocated.length)
        .toString(),
    });
  }
  await createObjectCsvWriter({
    path: resolve(__dirname, today, `allocation-stats-${totalRelayers}.csv`),
    header: Object.keys(allocationCsvData[0]).map((key) => ({ id: key, title: key })),
  }).writeRecords(allocationCsvData);
})();
