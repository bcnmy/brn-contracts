import { solidityKeccak256 } from 'ethers/lib/utils';
import AsyncLock from 'async-lock';
import { IMinimalApplication__factory } from '../../typechain-types';
import { config } from './config';

export interface ITransaction {
  data: string;
}

export class Mempool {
  lock = new AsyncLock();
  lockName = 'MEMPOOL';

  pool: Set<ITransaction> = new Set();

  constructor() {
    let currentTransactionInput: number = 0;

    // Generate Transactions
    setInterval(() => {
      console.log(
        `Tx Generator: Generating new transaction with argument: ${currentTransactionInput}`
      );
      const calldata = IMinimalApplication__factory.createInterface().encodeFunctionData(
        'executeMinimalApplication',
        [solidityKeccak256(['uint256'], [currentTransactionInput++])]
      );
      this.lock.acquire(this.lockName, () => {
        this.pool.add({ data: calldata });
      });
    }, config.transactionsGenerationIntervalMs);

    // Remove Processed Transactions
    config.transactionAllocatorWs.on(
      config.transactionAllocator.filters.TransactionStatus(null, null, null),

      (data) => {
        this.lock.acquire(this.lockName, () => {
          console.log('Mempool: Received TransactionStatus event', data);
        });
      }
    );
  }

  public async getTransactions(): Promise<Set<ITransaction>> {
    return this.lock.acquire(this.lockName, () => {
      const transactions = new Set(this.pool);
      return transactions;
    });
  }
}
