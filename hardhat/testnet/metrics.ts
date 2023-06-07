import { config } from './config';
import { table } from 'table';
import * as fs from 'fs';
import { formatEther } from 'ethers/lib/utils';
import { uuid } from 'uuidv4';
import { BigNumber } from 'ethers';
import { Relayer } from './relayer';

const statusCodeToString: Record<number, string> = {
  0: 'Inactive',
  1: 'Active',
  2: 'Exiting',
  3: 'Jailed',
};

export class Metrics {
  private transactionsInMempool = 0;
  private relayers: Relayer[] = [];
  private blocksUntilNextWindow = 0;
  private nextWriteTimeMs = 0;
  private metricsId = uuid();

  constructor() {
    console.log(`Metrics ID: ${this.metricsId}`);
    fs.mkdirSync(`metrics`, { recursive: true });
    fs.writeFileSync('metrics/metrics-id.txt', this.metricsId);
  }

  public init() {
    setInterval(() => {
      this.writeMetricsToFile();
    }, config.metricsUpdateIntervalSec * 1000);
  }

  public setRelayers(relayers: Relayer[]) {
    this.relayers = relayers;
  }

  public setTransactionsInMempool(count: number) {
    this.transactionsInMempool = count;
  }

  public setBlocksUntilNextWindow(currentBlock: number, windowLength: number) {
    this.blocksUntilNextWindow = windowLength - (currentBlock % windowLength);
  }

  public async generateMetrics(): Promise<[string, number[]]> {
    try {
      if (this.relayers.length === 0) {
        return ['', []];
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
          const relayerAddress = relayer.wallet.address;
          const data: Record<string, any> = await config.transactionAllocator.relayerInfo(
            relayerAddress
          );
          const stakePerc = data.stake.mul(100000).div(totalStake).toNumber() / 1000;
          const status = statusCodeToString[data.status as number];

          return {
            address: relayerAddress,
            originalStake: formatEther(relayer.stake || 0),
            currentStake: formatEther(data.stake),
            delta: formatEther(data.stake.sub(relayer.stake)),
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
      const z = await config.transactionAllocator.livenessZParameter();
      const transactionsSubmittedByRelayersTabularData = [
        [
          'Relayer',
          'Tx Count',
          'Percentage',
          'Min Expected Tx',
          'Windows Selected In',
          'Windows Selected In But No Transactions',
        ],
        ...(await Promise.all(
          this.relayers.map(async (relayer) => {
            const relayerAddress = relayer.wallet.address;
            const txns = await config.transactionAllocator.transactionsSubmittedByRelayer(
              relayerAddress
            );
            let perc = '';
            if (totalTransactions.gt(0)) {
              perc = ((txns.toNumber() * 100) / totalTransactions.toNumber()).toFixed(2);
            }
            const relayerStake = (await config.transactionAllocator.relayerInfo(relayerAddress))
              .stake;
            const minExpectedTxns = (
              await config.transactionAllocator.calculateMinimumTranasctionsForLiveness(
                relayerStake,
                totalStake,
                totalTransactions.mul(BigNumber.from(10).pow(24)),
                z
              )
            ).div(BigNumber.from(10).pow(24));
            return [
              relayerAddress,
              txns.toString(),
              `${perc.toString()}%`,
              minExpectedTxns.toString(),
              relayer.windowsSelectedIn.size.toString(),
              relayer.windowsSelectedInButNoTransactions.size.toString(),
            ];
          })
        )),
        ['Total', totalTransactions.toString(), '-', '-', '-', '-'],
      ];
      result += `\n\nTransactions submitted by relayers:\n${table(
        transactionsSubmittedByRelayersTabularData as any
      )}\n`;

      const txnsDistribution = await Promise.all(
        this.relayers.map(async (relayer) =>
          (
            await config.transactionAllocator.transactionsSubmittedByRelayer(relayer.wallet.address)
          ).toNumber()
        )
      );

      return [result, txnsDistribution];
    } catch (e) {
      console.log(e);
      return ['', []];
    }
  }

  public async writeMetricsToFile() {
    const [metrics, txns] = await this.generateMetrics();
    fs.mkdirSync(`metrics/${this.metricsId}`, { recursive: true });
    fs.writeFileSync(`metrics/${this.metricsId}/metrics.txt`, metrics);
    if (txns.length > 0) {
      fs.appendFile(`metrics/${this.metricsId}/txns.txt`, `${txns.join(',')}\n`, () => {});
    }

    const now = Date.now();
    if (now > this.nextWriteTimeMs) {
      fs.mkdirSync(`metrics/${this.metricsId}`, { recursive: true });
      fs.writeFileSync(`metrics/${this.metricsId}/metrics-${now}.txt`, metrics);
      this.nextWriteTimeMs = now + config.writeLogIntervalSec * 1000;
    }
  }
}

export const metrics = new Metrics();