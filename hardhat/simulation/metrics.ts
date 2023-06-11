import { config } from './config';
import { table } from 'table';
import * as fs from 'fs';
import { formatEther, formatUnits, parseUnits } from 'ethers/lib/utils';
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
  private metricsId = uuid();
  private windowId = 0;

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
    this.windowId = Math.floor(currentBlock / windowLength);
  }

  public async generateMetricsHeader(): Promise<string> {
    const data: [string, any][] = [
      ['Transactions in mempool', this.transactionsInMempool],
      ['Current Window Index', this.windowId],
      ['Blocks until next window', this.blocksUntilNextWindow],
      [
        'Time till next epoch',
        `${
          (await config.transactionAllocator.epochEndTimestamp()).toNumber() -
          Math.floor(Date.now() / 1000)
        }s`,
      ],
      [
        'Protocol reward rate',
        `${formatEther(await config.transactionAllocator.protocolRewardRate())} BICO/s`,
      ],
    ];

    let header = '';
    for (const [key, value] of data) {
      header += `${key}: ${value}\n`;
    }
    return header;
  }

  public async generateRelayerInfoTable(): Promise<string> {
    if (this.relayers.length == 0) {
      return '';
    }

    const totalStake = await config.transactionAllocator.totalStake();

    const relayersData = await Promise.all(
      this.relayers.map(async (relayer) => {
        const relayerAddress = relayer.wallet.address;
        const data = await config.transactionAllocator.relayerInfo(relayerAddress);
        const stakePerc = data.stake.mul(100000).div(totalStake).toNumber() / 1000;
        const status = statusCodeToString[data.status as number];

        const claimedRewards = relayer.claimedRewards;
        const unclaimedRewards = await config.transactionAllocator.relayerClaimableProtocolRewards(
          relayerAddress
        );
        const totalRewards = claimedRewards.add(unclaimedRewards);

        return {
          address: relayerAddress,
          originalStake: formatEther(relayer.stake || 0),
          currentStake: formatEther(data.stake),
          delta: formatEther(data.stake.sub(relayer.stake)),
          stakePercentage: status === 'Jailed' ? '-' : `${stakePerc.toString()}%`,
          status,
          minExitTimestamp: data.minExitTimestamp.toString(),
          shares: data.rewardShares.toString(),
          claimedRewards: formatEther(claimedRewards),
          unclaimedRewards: formatEther(unclaimedRewards),
          totalRewards: formatEther(totalRewards),
        };
      })
    );
    const relayerKeys = Object.keys(relayersData[0]);
    const relayersTabularData = [relayerKeys, ...relayersData.map((r) => Object.values(r))];
    const tableStr = `\n\nRelayers State:\n${table(relayersTabularData as any)}\n`;

    return tableStr;
  }

  public async generateTransactionsTable(): Promise<string> {
    if (this.relayers.length == 0) {
      return '';
    }

    const totalTransactions = await config.transactionAllocator.totalTransactionsSubmitted();
    const z = await config.transactionAllocator.livenessZParameter();
    const totalStake = await config.transactionAllocator.totalStake();

    const header = [
      'Relayer',
      'Tx Count',
      'Percentage',
      'Min Expected Tx',
      'Windows Selected In',
      'Windows Selected In But No Transactions',
    ];

    const data = await Promise.all(
      this.relayers.map(async (relayer) => {
        const relayerAddress = relayer.wallet.address;
        const txns = await config.transactionAllocator.transactionsSubmittedByRelayer(
          relayerAddress
        );
        let perc = '';
        if (totalTransactions.gt(0)) {
          perc = ((txns.toNumber() * 100) / totalTransactions.toNumber()).toFixed(2);
        }
        const relayerStake = (await config.transactionAllocator.relayerInfo(relayerAddress)).stake;
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
    );

    const footer = ['Total', totalTransactions.toString(), '-', '-', '-', '-'];
    const tableData = [header, ...data, footer];
    const tableStr = `\n\nTransactions submitted by relayers:\n${table(tableData as any)}\n`;

    return tableStr;
  }

  public async generateTranasactionDistribution(): Promise<number[]> {
    return Promise.all(
      this.relayers.map(async (relayer) =>
        (
          await config.transactionAllocator.transactionsSubmittedByRelayer(relayer.wallet.address)
        ).toNumber()
      )
    );
  }

  public async generateMetrics(): Promise<string> {
    return `${await this.generateMetricsHeader()}\n${await this.generateRelayerInfoTable()}\n${await this.generateTransactionsTable()}`;
  }

  public async writeMetricsToFile() {
    const metrics = await this.generateMetrics();
    fs.mkdirSync(`metrics/${this.metricsId}`, { recursive: true });
    fs.writeFileSync(`metrics/${this.metricsId}/metrics.txt`, metrics);

    const txnDistribution = await this.generateTranasactionDistribution();
    if (txnDistribution.length > 0) {
      fs.appendFile(
        `metrics/${this.metricsId}/txns.txt`,
        `${txnDistribution.join(',')}\n`,
        () => {}
      );
    }
  }
}

export const metrics = new Metrics();
