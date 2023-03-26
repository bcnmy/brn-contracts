import { BigNumber, BigNumberish, ContractReceipt, Wallet } from 'ethers';
import { formatUnits, hexValue, parseEther } from 'ethers/lib/utils';
import { ethers, network } from 'hardhat';
import { ITransactionAllocator, ApplicationMock, MockERC20 } from '../typechain-types';
import { deploy } from './deploy';
import { createObjectCsvWriter } from 'csv-writer';
import { resolve } from 'path';
import { mkdirSync, existsSync } from 'fs';
import { TransactionStruct } from '../typechain-types/src/interfaces/IApplication';
import { mine } from '@nomicfoundation/hardhat-network-helpers';

const totalTransactions = 100;
const totalRelayers = 20;

const blocksPerWindow = 1000000;
const relayersPerWindow = 10;
const penaltyDelayBlocks = 10;
const delegatorSharePercent = 1 * 100; // 1%
const supportedTokens = ['0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE'];

let stakeArray: BigNumberish[] = [];
let delegationArray: BigNumberish[] = [];
let cdfArray: BigNumberish[] = [];

const getGenericGasConsumption = (
  txnAllocator: ITransactionAllocator,
  transactionReceipt: ContractReceipt
): [string, BigNumber][] => {
  const logs = transactionReceipt.logs
    .map((log) => {
      try {
        return txnAllocator.interface.parseLog(log);
      } catch (e) {}
    })
    .filter((log) => log);
  const gasLogs = logs.filter((log) => log!.name === 'GenericGasConsumed');
  if (gasLogs.length == 0) throw new Error(`Gas Log array not found in logs:${logs}`);
  // return Object.fromEntries(
  //   gasLogs.map((log) => [log!.args.label, log!.args.gasConsumed.toString()])
  // );
  const uniqueLabels = [...new Set(gasLogs.map((log) => log!.args.label))];
  return uniqueLabels.map((label) => {
    const gas = gasLogs
      .filter((log) => log!.args.label === label)
      .reduce((acc, log) => acc.add(log!.args.gasConsumed), BigNumber.from(0));
    return [label, gas];
  });
};

const setupRelayers = async (
  txnAllocator: ITransactionAllocator,
  bondToken: MockERC20,
  count: number
) => {
  console.log('Setting up relayers...');
  const amount = ethers.utils.parseEther('10000');
  const wallets = [];
  const gasConsumed = [];
  for (let i = 0; i < count; i++) {
    try {
      const multiplier = Math.floor(Math.random() * 10) + 1;
      const stake = amount.mul(multiplier);
      const randomWallet = new Wallet(ethers.Wallet.createRandom().privateKey, ethers.provider);
      await network.provider.send('hardhat_setBalance', [
        randomWallet.address,
        hexValue(parseEther('100')),
      ]);
      await bondToken.mint(randomWallet.address, stake);
      await bondToken.connect(randomWallet).approve(txnAllocator.address, stake);
      const { wait } = await txnAllocator
        .connect(randomWallet)
        .register(
          stakeArray,
          delegationArray,
          amount.mul(multiplier),
          [randomWallet.address],
          'test',
          delegatorSharePercent
        );
      const receipt = await wait();
      stakeArray = await txnAllocator.getStakeArray();
      cdfArray = await txnAllocator.getCdfArray();
      delegationArray = await txnAllocator.getDelegationArray();
      console.log(
        `Relayer ${i} registered successfully with ${formatUnits(
          stake,
          await bondToken.decimals()
        )} BICO`
      );
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
  await mine(10 * blocksPerWindow);
  return { wallets, gasConsumed };
};

const getGasConsumption = (
  txnAllocator: ITransactionAllocator,
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
  const genericGasConsumedData = getGenericGasConsumption(txnAllocator, transactionReceipt);
  return {
    totalGas,
    genericGasConsumedData,
  };
};

const getInternalTxResult = (
  txnAllocator: ITransactionAllocator,
  transactionReceipt: ContractReceipt
) => {
  const logs = transactionReceipt.logs
    .map((log) => {
      try {
        return txnAllocator.interface.parseLog(log);
      } catch (e) {}
    })
    .filter((log) => log)
    .filter((log) => log?.name === 'TransactionStatus');

  if (logs.length === 0) {
    throw new Error(`TransactionStatus log not found`);
  }

  return logs.map((log) => ({
    index: log?.args[0],
    success: log?.args[1],
    refundSuccess: log?.args[2],
    returndata: log?.args[3],
    totalGasConsumed: log?.args[4],
    relayerRefund: log?.args[5],
    premiumsGenerated: log?.args[6],
  }));
};

const generateTransactions = async (
  txnAllocator: ITransactionAllocator,
  txMock: ApplicationMock,
  count: number
) => {
  return Promise.all(
    new Array(count).fill(0).map(async (_, i) => {
      const randomWallet = new Wallet(ethers.Wallet.createRandom().privateKey, ethers.provider);
      await network.provider.send('hardhat_setBalance', [
        randomWallet.address,
        hexValue(parseEther('10')),
      ]);
      const tx: TransactionStruct = {
        to: txMock.address,
        data: txMock.interface.encodeFunctionData('mockUpdate', [i]),
        gasLimit: 1000000,
        fixedGas: 21000,
        prePaymentGasLimit: 10000,
        refundGasLimit: 10000,
      };
      return tx;
    })
  );
};

(async () => {
  const allocationCsvData: any[] = [];
  const today: string = new Date().toLocaleDateString('en-GB').split('/').reverse().join('-');
  existsSync(resolve(__dirname, today)) || mkdirSync(resolve(__dirname, today));

  const { txnAllocator, txMock, token } = await deploy({
    blocksPerWindow,
    relayersPerWindow,
    penaltyDelayBlocks,
    bondTokenAddress: ethers.constants.AddressZero,
    supportedTokens,
  });
  await network.provider.send('hardhat_setBalance', [txMock.address, hexValue(parseEther('100'))]);

  console.log('Generating transactions...');
  const txns = await generateTransactions(txnAllocator, txMock, totalTransactions);
  console.log('Transactions generated');
  const { wallets: relayers, gasConsumed: registrationGasConsumed } = await setupRelayers(
    txnAllocator,
    token,
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
    const [txnAllocated, relayerGenerationIteration, selectedRelayerCdfIndex] =
      await txnAllocator.allocateTransaction({
        relayerAddress: relayer.address,
        requests: txns,
        cdf: cdfArray,
        currentCdfLogIndex: 1,
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

    const { wait } = await txnAllocator
      .connect(relayer)
      .execute(
        txnAllocated,
        cdfArray,
        relayerGenerationIterationDeduplicated,
        selectedRelayerCdfIndex,
        1,
        0
      );
    const receipt = await wait();
    if (receipt.status === 0) throw new Error(`Transaction failed: ${receipt}`);

    const internalTxResults = getInternalTxResult(txnAllocator, receipt);

    if (internalTxResults.length !== txnAllocated.length) {
      throw new Error(
        `Internal tx count mismatch: ${internalTxResults.length} vs ${txnAllocated.length}`
      );
    }
    for (const tx of internalTxResults) {
      if (!tx.success) throw new Error(`Transaction failed: ${JSON.stringify(tx, null, 2)}`);
    }

    console.log(`Transaction batch of length ${txnAllocated.length} for ${i}th relayer executed`);

    const { totalGas, genericGasConsumedData } = getGasConsumption(txnAllocator, receipt);
    const genericGasConsumed = genericGasConsumedData.map(([label, gas]) => [
      label,
      gas.toString(),
    ]);
    const genericGasConsumedPerTx = genericGasConsumedData.map(([label, gas]) => [
      `${label}PerTx`,
      gas.div(txnAllocated.length).toString(),
    ]);

    allocationCsvData.push({
      relayerCount: totalRelayers,
      generationIterationCount: relayerGenerationIterationDeduplicated.length,
      txCount: txnAllocated.length,
      totalGas: totalGas.toString(),
      ...Object.fromEntries(genericGasConsumed),
      ...Object.fromEntries(genericGasConsumedPerTx),
    });
  }
  await createObjectCsvWriter({
    path: resolve(__dirname, today, `allocation-stats-${totalRelayers}.csv`),
    header: Object.keys(allocationCsvData[0]).map((key) => ({ id: key, title: key })),
  }).writeRecords(allocationCsvData);
})();
