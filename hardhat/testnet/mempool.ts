import { solidityKeccak256 } from 'ethers/lib/utils';
import AsyncLock from 'async-lock';
import { IMinimalApplication__factory } from '../../typechain-types';
import { metrics } from './metrics';
import { config } from './config';

export class Mempool {
  lock = new AsyncLock();
  lockName = 'MEMPOOL';

  pool: Set<string> = new Set();

  public init() {
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
      this.lock.acquire(this.lockName, async () => {
        this.pool.add(calldata);
        await metrics.setTransactionsInMempool(this.pool.size);
      });
    }, config.transactionsGenerationIntervalMs);
  }

  public async getTransactions(): Promise<Set<string>> {
    return this.lock.acquire(this.lockName, () => {
      const transactions = new Set(this.pool);
      return transactions;
    });
  }

  public async removeTransactions(tx: string[]) {
    return this.lock.acquire(this.lockName, async () => {
      tx.forEach((t) => {
        this.pool.delete(t);
      });
      await metrics.setTransactionsInMempool(this.pool.size);
    });
  }
}
