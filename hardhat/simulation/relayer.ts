import { BigNumber, Wallet } from 'ethers';
import { config } from './config';
import { hashToRelayerState } from './state-tracker';
import { Mempool } from './mempool';
import { logTransaction } from './utils';
import { IMinimalApplication, IMinimalApplication__factory } from '../../typechain-types';
import { RelayerStateStruct } from '../../typechain-types/src/mock/minimal-application/MinimalApplication';

export class Relayer {
  wallet: Wallet;
  windowLength = 0;
  application: IMinimalApplication;
  windowsSelectedIn = new Set<number>();
  windowsSelectedInButNoTransactions = new Set<number>();
  claimedRewards = BigNumber.from(0);

  static stateHashCache: Map<number, [string, string]> = new Map();
  static allotedRelayersCache: Map<number, string[]> = new Map();

  constructor(
    privateKey: string,
    public readonly stake: BigNumber,
    private readonly mempool: Mempool
  ) {
    this.wallet = new Wallet(privateKey, config.httpProvider);
    this.application = IMinimalApplication__factory.connect(
      config.transactionAllocator.address,
      this.wallet
    );
    console.log("Relayer's address: ", this.wallet.address);
  }

  public async init() {
    this.windowLength = (await config.transactionAllocator.blocksPerWindow()).toNumber();

    // Fund Relayer
    const relayerBalance = await this.wallet.getBalance();
    if (relayerBalance.lt(config.fundingAmount)) {
      console.log(`Relayer ${this.wallet.address}: Funding..`);
      await logTransaction(
        config.deployer.sendTransaction({
          to: this.wallet.address,
          value: config.fundingAmount.mul(2),
        }),
        `Relayer ${this.wallet.address}: Funding Tx`
      );
    }

    if ((await config.transactionAllocator.relayerInfo(this.wallet.address)).stake.gt(0)) {
      console.log(`Relayer ${this.wallet.address}: Relayer already registered`);
      return;
    }

    console.log(`Relayer ${this.wallet.address}: Registering..`);

    // Mint Token
    console.log(`Relayer ${this.wallet.address}: Minting tokens..`);
    await logTransaction(
      config.bondToken.connect(this.wallet).mint(this.wallet.address, this.stake),
      `Relayer ${this.wallet.address}: Tokens mint`
    );

    // Approve Tokens
    console.log(`Relayer ${this.wallet.address}: Approving tokens..`);
    await logTransaction(
      config.bondToken
        .connect(this.wallet)
        .approve(config.transactionAllocator.address, this.stake),
      `Relayer ${this.wallet.address}: Tokens Approval`
    );

    const [, latestHash] = await config.transactionAllocator.relayerStateHash();
    const relayerState = hashToRelayerState[latestHash];
    if (!relayerState) {
      throw new Error(
        `Relayer ${this.wallet.address}: Relayer state not found for hash ${latestHash}`
      );
    }

    // Register
    console.log(`Relayer ${this.wallet.address}: Registering..`);
    await logTransaction(
      config.transactionAllocator
        .connect(this.wallet)
        .register(relayerState, this.stake, [this.wallet.address], 'endpoint', 0),
      `Relayer ${this.wallet.address}: Registered`
    );
  }

  private getActiveStateToPendingStateMap(
    activeState: RelayerStateStruct,
    latestState: RelayerStateStruct
  ): number[] {
    const state = new Array(activeState.relayers.length).fill(activeState.relayers.length);
    for (let i = 0; i < activeState.relayers.length; i++) {
      for (let j = 0; j < latestState.relayers.length; j++) {
        if (activeState.relayers[i] === latestState.relayers[j]) {
          state[i] = j;
          break;
        }
      }
    }
    return state;
  }

  private async getRelayerStateHashes(window: number): Promise<[string, string]> {
    if (Relayer.stateHashCache.has(window)) {
      return Relayer.stateHashCache.get(window)!;
    }

    const [currentStateHash, latestHash] = await config.transactionAllocator.relayerStateHash();
    Relayer.stateHashCache.set(window, [currentStateHash, latestHash]);
    return [currentStateHash, latestHash];
  }

  private async getAllotedRelayers(window: number): Promise<string[]> {
    if (Relayer.allotedRelayersCache.has(window)) {
      return Relayer.allotedRelayersCache.get(window)!;
    }

    const { currentState } = await this.getState();

    const [allotedRelayers] = await config.transactionAllocator.allocateRelayers(currentState);
    Relayer.allotedRelayersCache.set(window, allotedRelayers);
    return allotedRelayers;
  }

  public async claimRewards() {
    const relayerStatus = (await config.transactionAllocator.relayerInfo(this.wallet.address))
      .status;
    if (relayerStatus === 3) {
      console.log(`Relayer ${this.wallet.address}: Relayer is jailed. Not claiming rewards`);
      return;
    }

    console.log(`Relayer ${this.wallet.address}: Claiming rewards`);
    const balanceBefore = await config.bondToken.balanceOf(this.wallet.address);
    await logTransaction(
      config.transactionAllocator.connect(this.wallet).claimProtocolReward(),
      `Relayer ${this.wallet.address}: Claimed rewards`
    );
    const balanceAfter = await config.bondToken.balanceOf(this.wallet.address);
    this.claimedRewards = this.claimedRewards.add(balanceAfter.sub(balanceBefore));
  }

  private async isRelayerSelected(windowIndex: number): Promise<boolean> {
    const allotedRelayers = await this.getAllotedRelayers(windowIndex);
    return allotedRelayers.includes(this.wallet.address);
  }

  private async getState() {
    const [currentStateHash, latestStateHash] =
      await config.transactionAllocator.relayerStateHash();
    const currentState = hashToRelayerState[currentStateHash];
    if (!currentState) {
      throw new Error(
        `Relayer ${this.wallet.address}: Current state not found for hash ${currentStateHash}`
      );
    }
    const latestState = hashToRelayerState[latestStateHash];
    if (!latestState) {
      throw new Error(
        `Relayer ${this.wallet.address}: Latest state not found for hash ${latestStateHash}`
      );
    }

    return { currentState, latestState };
  }

  private async submitTransactions(
    blockNumber: number,
    txnAllocated: string[],
    relayerIndex: number,
    relayerGenerationIterations: number,
    currentState: RelayerStateStruct,
    latestState: RelayerStateStruct
  ) {
    // Submit transactions
    console.log(`Relayer ${this.wallet.address}: Submitting transactions at block ${blockNumber}`);
    try {
      await logTransaction(
        config.transactionAllocator.connect(this.wallet).execute(
          {
            reqs: txnAllocated,
            forwardedNativeAmounts: new Array(txnAllocated.length).fill(0),
            relayerIndex,
            relayerGenerationIterationBitmap: relayerGenerationIterations,
            activeState: currentState,
            latestState: latestState,
            activeStateToPendingStateMap: this.getActiveStateToPendingStateMap(
              currentState,
              latestState
            ),
          },
          {
            gasLimit: 10000000,
          }
        ),
        `Relayer ${this.wallet.address}: Submitted transaction at ${blockNumber}`
      );
      // Delete transactions from mempool
      console.log(`Relayer ${this.wallet.address}: Deleting transactions from mempool`);
    } catch (e) {
      process.exit(1);
    }

    await this.mempool.removeTransactions(txnAllocated);
  }

  public async run() {
    config.wsProvider.on('block', async (blockNumber: number) => {
      if (config.inactiveRelayers.includes(this.wallet.address)) {
        return;
      }

      console.log(`Relayer ${this.wallet.address}: New block ${blockNumber}`);

      if (blockNumber % this.windowLength != 0) {
        return;
      }
      console.log(`Relayer ${this.wallet.address}: New window ${blockNumber}`);
      const windowIndex = blockNumber / this.windowLength;

      if (!(await this.isRelayerSelected(windowIndex))) {
        return;
      }
      this.windowsSelectedIn.add(windowIndex);

      // Check if transactions can be submitted
      const pendingTransactions = Array.from(await this.mempool.getTransactions());
      if (pendingTransactions.length === 0) {
        this.windowsSelectedInButNoTransactions.add(windowIndex);
        return;
      }

      const { currentState, latestState } = await this.getState();

      const [txnAllocated, relayerGenerationIterations, relayerIndex]: [
        string[],
        BigNumber,
        BigNumber
      ] = await this.application.allocateMinimalApplicationTransaction(
        this.wallet.address,
        pendingTransactions,
        currentState
      );

      if (txnAllocated.length === 0) {
        console.log(`Relayer ${this.wallet.address}: No transactions allocated`);
        this.windowsSelectedInButNoTransactions.add(windowIndex);
        return;
      } else {
        console.log(
          `Relayer ${this.wallet.address}: Allocated ${txnAllocated.length} transactions`
        );
      }

      await this.submitTransactions(
        blockNumber,
        txnAllocated,
        relayerIndex.toNumber(),
        relayerGenerationIterations.toNumber(),
        currentState,
        latestState
      );
    });

    config.wsProvider.on('block', async () => {
      if (Math.random() < config.relayerClaimProbability) {
        await this.claimRewards();
      }
    });
  }

  public getAdddress() {
    return this.wallet.address;
  }
}
