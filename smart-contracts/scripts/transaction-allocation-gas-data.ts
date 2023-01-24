import { BigNumber, BigNumberish, ContractReceipt, Wallet } from 'ethers';
import { AbiCoder, hexValue, parseEther } from 'ethers/lib/utils';
import { ethers, network, tenderly } from 'hardhat';
import {
  SmartWallet__factory,
  TransactionAllocator,
  TransactionAllocator__factory,
  TransactionMock,
  TransactionMock__factory,
} from '../typechain-types';
import { createObjectCsvWriter } from 'csv-writer';
import { resolve } from 'path';
import { signTransaction } from './utils';

const totalTransactions = 100;
const windowLength = 1000000;
const totalRelayers = 100;
const relayersPerWindow = 10;

let stakeArray: BigNumberish[] = [];
let cdfArray: BigNumberish[] = [];

const deploy = async () => {
  console.log('Deploying contract...');
  const [deployer] = await ethers.getSigners();
  const scwImplementation = await new SmartWallet__factory(deployer).deploy();
  const txnAllocator = await new TransactionAllocator__factory(deployer).deploy(
    windowLength,
    windowLength,
    relayersPerWindow,
    0,
    scwImplementation.address
  );
  const txMock = await new TransactionMock__factory(deployer).deploy();
  // await tenderly.persistArtifacts(
  //   ...[
  //     {
  //       name: 'TransactionAllocator',
  //       address: txnAllocator.address,
  //     },
  //     {
  //       name: 'TransactionMock',
  //       address: txMock.address,
  //     },
  //   ]
  // );
  return { txnAllocator, txMock };
};

const getGenericGasConsumption = (
  txnAllocator: TransactionAllocator,
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

const setupRelayers = async (txnAllocator: TransactionAllocator, count: number) => {
  console.log('Setting up relayers...');
  const amount = ethers.utils.parseEther('1');
  const wallets = [];
  const gasConsumed = [];
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
      stakeArray = await txnAllocator.getStakeArray();
      cdfArray = await txnAllocator.getCdf();
      // const gasData = getGenericGasConsumption(txnAllocator, receipt);
      // const totalGasFromEvents = Object.values(gasData).reduce((a: string, b: string) =>
      //   BigNumber.from(a).add(b).toString()
      // );

      console.log(`Relayer ${i} registered successfully with ${multiplier} ETH`);
      console.log(`Stake array: ${stakeArray}`);
      console.log(`CDF array: ${cdfArray}`);

      gasConsumed.push({
        // ...gasData,
        totalGas: receipt.gasUsed.toString(),
        // calldataGas: receipt.gasUsed.sub(totalGasFromEvents).toString(),
      });
      wallets.push(randomWallet);
    } catch (e) {
      console.log(e);
    }
  }
  return { wallets, gasConsumed };
};

const getVerificationGasConsumed = (
  txnAllocator: TransactionAllocator,
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
  txnAllocator: TransactionAllocator,
  txMock: TransactionMock,
  count: number
) => {
  const chainId = await ethers.provider.getNetwork().then((n) => n.chainId);
  return Promise.all(
    new Array(count).fill(0).map(async (_, i) => {
      const randomWallet = new Wallet(ethers.Wallet.createRandom().privateKey, ethers.provider);
      await network.provider.send('hardhat_setBalance', [
        randomWallet.address,
        hexValue(parseEther('1')),
      ]);
      const tx = {
        from: randomWallet.address,
        to: txMock.address,
        value: 0,
        gas: 1000000,
        nonce: 0,
        data: txMock.interface.encodeFunctionData('mockUpdate', [i]),
        signature: '',
      };
      return signTransaction(tx, chainId, randomWallet, txnAllocator);
    })
  );
};

(async () => {
  const allocationCsvData: any[] = [];
  const absenceProofCsvData: any[] = [];

  const { txnAllocator, txMock } = await deploy();
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
    path: resolve(__dirname, `registration-stats-${totalRelayers}.csv`),
    header: Object.keys(gasConsumedCsvData[0]).map((key) => ({ id: key, title: key })),
  }).writeRecords(gasConsumedCsvData);

  console.log('Executing transactions...');
  for (let i = 0; i < relayers.length; i++) {
    const relayer = relayers[i];
    const blockNumber = await ethers.provider.getBlockNumber();
    const [txnAllocated, relayerGenerationIteration, selectedRelayerCdfIndex] =
      await txnAllocator.allocateTransaction(
        relayer.address,
        blockNumber,
        txns.map((tx) => tx.data),
        cdfArray
      );

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

    const txnRequests: any = txnAllocated.map((data) => txns.find((tx) => tx.data === data));
    console.log(`Transaction batch of length ${txnRequests.length} for ${i}th relayer`);

    const { wait, hash } = await txnAllocator
      .connect(relayer)
      .execute(
        txnRequests,
        cdfArray,
        relayerGenerationIterationDeduplicated,
        selectedRelayerCdfIndex
      );
    const receipt = await wait();
    if (receipt.status === 0) throw new Error(`Transaction failed: ${receipt}`);
    const { totalGas, VerificationGas, ExecutionGas, OtherOverhead } = getVerificationGasConsumed(
      txnAllocator,
      receipt
    );
    console.log(
      `Verification Gas used for transaction batch of length ${
        txnRequests.length
      } for ${i}th relayer: ${VerificationGas.toString()}. Tx Hash: ${hash}`
    );

    allocationCsvData.push({
      relayerCount: totalRelayers,
      generationIterationCount: relayerGenerationIterationDeduplicated.length,
      txCount: txnRequests.length,
      totalGas: totalGas.toString(),
      executionGas: ExecutionGas.toString(),
      verificationGas: VerificationGas.toString(),
      verificationGasPerTx: BigNumber.from(VerificationGas).div(txnRequests.length).toString(),
      otherOverhead: OtherOverhead.toString(),
      totalOverhead: BigNumber.from(VerificationGas).add(OtherOverhead).toString(),
      totalOverheadPerTx: BigNumber.from(VerificationGas)
        .add(OtherOverhead)
        .div(txnRequests.length)
        .toString(),
    });
  }
  await createObjectCsvWriter({
    path: resolve(__dirname, `allocation-stats-${totalRelayers}.csv`),
    header: Object.keys(allocationCsvData[0]).map((key) => ({ id: key, title: key })),
  }).writeRecords(allocationCsvData);
})();
