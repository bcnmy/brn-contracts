import { config } from './config';
import { table } from 'table';
import AsyncLock from 'async-lock';
import * as fs from 'fs';
import { formatEther } from 'ethers/lib/utils';
import { uuid } from 'uuidv4';
import { BigNumber } from 'ethers';

export class Metrics {
  private lock = new AsyncLock();
  private lockName = 'METRICS';
  private transactionsInMempool = 0;
  private relayers: string[] = [];
  private blocksUntilNextWindow = 0;
  public originalStake: { [key: string]: BigNumber } = {};
  private nextWriteTimeMs = 0;
  private metricsId = uuid();

  constructor() {
    console.log(`Metrics ID: ${this.metricsId}`);
  }

  public async setRelayers(relayers: string[], stake: BigNumber[]) {
    this.lock.acquire(this.lockName, () => {
      this.relayers = relayers;
      this.relayers.map((relayer, index) => {
        this.originalStake[relayer] = stake[index];
      });
    });
    await this.writeMetricsToFile();
  }

  public async setTransactionsInMempool(count: number) {
    this.lock.acquire(this.lockName, () => {
      this.transactionsInMempool = count;
    });
    await this.writeMetricsToFile();
  }

  public async setBlocksUntilNextWindow(currentBlock: number, windowLength: number) {
    this.lock.acquire(this.lockName, () => {
      this.blocksUntilNextWindow = windowLength - (currentBlock % windowLength);
    });
    await this.writeMetricsToFile();
  }

  public async generateMetrics(): Promise<string> {
    try {
      if (this.relayers.length === 0) {
        return '';
      }

      let result: string = '';

      result += `Transactions in mempool: ${this.transactionsInMempool}\n`;
      result += `Blocks until next window: ${this.blocksUntilNextWindow}\n`;
      result += `Time till next epoch: ${
        (await config.transactionAllocator.epochEndTimestamp()).toNumber() -
        Math.floor(Date.now() / 1000)
      }s`;

      const totalStake = await config.transactionAllocator.totalStake();
      const relayersData = await Promise.all(
        this.relayers.map(async (relayer) => {
          const data: Record<string, any> = await config.transactionAllocator.relayerInfo(relayer);
          const stakePerc = data.stake.mul(100000).div(totalStake).toNumber() / 1000;
          const status = {
            0: 'Inactive',
            1: 'Active',
            2: 'Exiting',
            3: 'Jailed',
          }[data.status as number];

          return {
            address: relayer,
            originalStake: formatEther(this.originalStake[relayer] || 0),
            currentStake: formatEther(data.stake),
            delta: formatEther(data.stake.sub(this.originalStake[relayer])),
            stakePercentage: status === 'Jailed' ? '-' : `${stakePerc.toString()}%`,
            status,
            minExitTimestamp: data.minExitTimestamp.toString(),
            jailedUntilTimestamp: data.jailedUntilTimestamp.toString(),
          };
        })
      );
      const relayerKeys = Object.keys(relayersData[0]);
      const relayersTabularData = [relayerKeys, ...relayersData.map((r) => Object.values(r))];
      result += `\n\nRelayers:\n${table(relayersTabularData as any)}\n`;

      const totalTransactions = await config.transactionAllocator.totalTransactionsSubmitted();
      const transactionsSubmittedByRelayersTabularData = [
        ['Relayer', 'Total', 'Percentage'],
        ...(await Promise.all(
          this.relayers.map(async (relayer) => {
            const txns = await config.transactionAllocator.transactionsSubmittedByRelayer(relayer);
            let perc = '';
            if (totalTransactions.gt(0)) {
              perc = ((txns.toNumber() * 100) / totalTransactions.toNumber()).toFixed(2);
            }
            return [relayer, txns.toString(), `${perc.toString()}%`];
          })
        )),
        ['Total', totalTransactions.toString(), '-'],
      ];
      result += `\n\nTransactions submitted by relayers:\n${table(
        transactionsSubmittedByRelayersTabularData as any
      )}\n`;

      return result;
    } catch (e) {
      console.log(e);
      return '';
    }
  }

  public async writeMetricsToFile() {
    const metrics = await this.generateMetrics();
    fs.mkdirSync(`metrics/${this.metricsId}`, { recursive: true });
    fs.writeFileSync(`metrics/${this.metricsId}/metrics.txt`, metrics);

    const now = Date.now();
    if (now > this.nextWriteTimeMs) {
      fs.mkdirSync(`metrics/${this.metricsId}`, { recursive: true });
      fs.writeFileSync(`metrics/${this.metricsId}/metrics-${now}.txt`, metrics);
      this.nextWriteTimeMs = now + config.writeLogIntervalSec * 1000;
    }
  }
}

export const metrics = new Metrics();
