import * as dotenv from 'dotenv';
import { ethers } from 'ethers';
import { ERC20FreeMint__factory, ITransactionAllocator__factory } from '../../typechain-types';
import { parseEther } from 'ethers/lib/utils';

dotenv.config();

const BOND_TOKEN_ADDRESS = '0x5FbDB2315678afecb367f032d93F642f64180aa3';
const TA_ADDRESS = '0x0165878A594ca255338adfa4d48449f69242Eb8F';

const httpProvider = new ethers.providers.JsonRpcBatchProvider(process.env.RPC_URL!);
const wsProvider = new ethers.providers.WebSocketProvider(process.env.WS_URL!);
const httpWallet = new ethers.Wallet(process.env.PRIVATE_KEY!, httpProvider);
const wsWallet = new ethers.Wallet(process.env.PRIVATE_KEY!, wsProvider);

const config = {
  httpProvider,
  wsProvider,
  deployer: httpWallet,
  transactionAllocator: ITransactionAllocator__factory.connect(TA_ADDRESS, httpWallet),
  transactionAllocatorWs: ITransactionAllocator__factory.connect(TA_ADDRESS, wsWallet),
  bondToken: ERC20FreeMint__factory.connect(BOND_TOKEN_ADDRESS, httpWallet),
  transactionsPerSecond: 55,
  relayerCount: 10,
  fundingAmount: parseEther('1'),
  writeLogIntervalSec: 10,
  metricsUpdateIntervalSec: 5,
};

export { config };
