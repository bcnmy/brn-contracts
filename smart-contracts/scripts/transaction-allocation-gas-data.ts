import { BigNumber, BigNumberish, ContractReceipt, Wallet } from 'ethers';
import { AbiCoder, hexValue, parseEther } from 'ethers/lib/utils';
import { ethers, network } from 'hardhat';
import {
  TransactionAllocator,
  TransactionMock,
  TransactionMock__factory,
} from '../typechain-types';
import { createObjectCsvWriter } from 'csv-writer';
import { resolve } from 'path';

const windowLength = 1000000;
const totalTransactions = 20;
const totalRelayers = 100;
const relayersPerWindow = 5;

let stakeArray: BigNumberish[] = [];
let cdfArray: BigNumberish[] = [];

const deploy = async () => {
  console.log('Deploying contract...');
  const [deployer] = await ethers.getSigners();
  const TxnAllocator = await ethers.getContractFactory('TransactionAllocator');
  const txnAllocator = await TxnAllocator.deploy(windowLength, windowLength, relayersPerWindow);
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

// const getStakeArray = (txnAllocator: TransactionAllocator) => {
//   const logs = transactionReceipt.logs.map((log) => txnAllocator.interface.parseLog(log));
//   const stakeArrayLog = logs.find((log) => log.name === 'StakeArrayUpdated');
//   if (!stakeArrayLog) throw new Error(`Stake array not found in logs:${logs}`);
//   return stakeArrayLog.args.stakePercArray;
// };

// const getCdf = (txnAllocator: TransactionAllocator, transactionReceipt: ContractReceipt) => {
//   const logs = transactionReceipt.logs.map((log) => txnAllocator.interface.parseLog(log));
//   const cdfArrayLog = logs.find((log) => log.name === 'CdfArrayUpdated');
//   if (!cdfArrayLog) throw new Error(`CDF array not found in logs:${logs}`);
//   return cdfArrayLog.args.cdfArray;
// };

const getGenericGasConsumption = (
  txnAllocator: TransactionAllocator,
  transactionReceipt: ContractReceipt
): Record<string, string> => {
  const logs = transactionReceipt.logs.map((log) => txnAllocator.interface.parseLog(log));
  const gasLogs = logs.filter((log) => log.name === 'GenericGasConsumed');
  if (gasLogs.length == 0) throw new Error(`Gas Log array not found in logs:${logs}`);
  return Object.fromEntries(
    gasLogs.map((log) => [log.args.label, log.args.gasConsumed.toString()])
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
      const gasData = getGenericGasConsumption(txnAllocator, receipt);
      // const totalGasFromEvents = Object.values(gasData).reduce((a: string, b: string) =>
      //   BigNumber.from(a).add(b).toString()
      // );

      console.log(`Relayer ${i} registered successfully with ${multiplier} ETH`);
      console.log(`Stake array: ${stakeArray}`);
      console.log(`CDF array: ${cdfArray}`);

      gasConsumed.push({
        ...gasData,
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

const getVerificationGasConsumed = async (
  txnAllocator: TransactionAllocator,
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
  const verificationFunctionGasConsumedLog = logs.find(
    (log) => log!.name === 'VerificationFunctionGasConsumed'
  );
  if (!executionGasLog) throw new Error(`Execution gas log not found in logs:${logs}`);
  if (!verificationFunctionGasConsumedLog)
    throw new Error(`Verification function gas log not found in logs:${logs}`);
  const executionGas = executionGasLog.args.gasConsumed;
  const verificationFunctionGas = verificationFunctionGasConsumedLog.args.gasConsumed;
  const calldataGas = totalGas.sub(executionGas).sub(verificationFunctionGas).sub(21000);
  console.log(
    `Total Gas: ${totalGas.toString()}, Execution gas: ${executionGas.toString()}, Verification gas: ${verificationFunctionGas.toString()}`
  );
  return {
    calldataGas,
    verificationFunctionGas,
    executionGas,
    totalGas,
  };
};

const generateTransactions = async (txMock: TransactionMock, count: number) => {
  return new Array(count)
    .fill(0)
    .map((_, i) => txMock.interface.encodeFunctionData('mockUpdate', [i]));
};

(async () => {
  const allocationCsvData: any[] = [];

  const { txnAllocator, txMock } = await deploy();
  console.log('Generating transactions...');
  const txns = await generateTransactions(txMock, totalTransactions);
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
    const [txnAllocated, selectedRelayerPdfIndex, relayerGenerationIteration] =
      await txnAllocator.allocateTransaction(relayer.address, blockNumber, txns, cdfArray);
    console.log(`Alloted ${txnAllocated.length} transactions to ${i}th relayer ${relayer.address}`);
    for (let j = 0; j < txnAllocated.length; j++) {
      const data = txnAllocated[j];
      const { wait, hash } = await txnAllocator.connect(relayer).execute(
        {
          from: relayer.address,
          to: txMock.address,
          value: 0,
          gas: 1000000,
          nonce: 0,
          data,
        },
        new AbiCoder().encode(['uint256'], [0]),
        cdfArray,
        relayerGenerationIteration[j],
        selectedRelayerPdfIndex[j]
      );
      const receipt = await wait();
      if (receipt.status === 0) throw new Error(`Transaction failed: ${receipt}`);
      const { totalGas, executionGas, verificationFunctionGas, calldataGas } =
        await getVerificationGasConsumed(txnAllocator, receipt);
      console.log(
        `Verification Gas used for ${j}th transaction for ${i}th relayer: ${verificationFunctionGas
          .add(calldataGas)
          .toString()}. Tx Hash: ${hash}`
      );

      allocationCsvData.push({
        relayerCount: totalRelayers,
        totalGas: totalGas.toString(),
        executionGas: executionGas.toString(),
        verificationFunctionGasConsumed: verificationFunctionGas.toString(),
        calldataGas: calldataGas.toString(),
      });
    }
  }

  await createObjectCsvWriter({
    path: resolve(__dirname, `allocation-stats-${totalRelayers}.csv`),
    header: Object.keys(allocationCsvData[0]).map((key) => ({ id: key, title: key })),
  }).writeRecords(allocationCsvData);
})();
