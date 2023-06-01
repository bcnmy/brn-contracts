import { solidityKeccak256 } from 'ethers/lib/utils';
import { IMinimalApplication__factory } from '../../typechain-types';
import { metrics } from './metrics';
import { config } from './config';

export class Mempool {
  // lock = new AsyncLock();
  // lockName = 'MEMPOOL';

  pool: Set<string> = new Set();

  public init() {
    // Generate Transactions
    setInterval(() => {
      const txs: string[] = new Array(config.transactionsPerSecond).fill(0).map(() => {
        const currentTransactionInput = Math.floor(Math.random() * 10000000000);
        console.log(
          `Tx Generator: Generating new transaction with argument: ${currentTransactionInput}`
        );
        return IMinimalApplication__factory.createInterface().encodeFunctionData(
          'executeMinimalApplication',
          [solidityKeccak256(['uint256'], [currentTransactionInput])]
        );
      });

      // this.lock.acquire(this.lockName, async () => {
      txs.forEach((t) => {
        this.pool.add(t);
      });
      metrics.setTransactionsInMempool(this.pool.size);
      // });
    }, 1000);
  }

  public async getTransactions(): Promise<Set<string>> {
    // return this.lock.acquire(this.lockName, () => {
    const transactions = new Set(this.pool);
    return transactions;
    // });
  }

  public async removeTransactions(tx: string[]) {
    // return this.lock.acquire(this.lockName, async () => {
    tx.forEach((t) => {
      this.pool.delete(t);
    });
    metrics.setTransactionsInMempool(this.pool.size);
    // });
  }
}
