import { BigNumber, Wallet } from 'ethers';
import { config } from './config';
import { hashToRelayerState } from './state-tracker';
import { Mempool } from './mempool';
import { logTransaction } from './utils';
import { RelayerStateStruct } from '../../typechain-types/src/mock/minimal-application/MinimalApplication';
import { NonceManagerFactory, NonceManager } from './nonce-manager';
import { IWormholeApplication, IWormholeApplication__factory } from '../../typechain-types';
import { parseEther } from 'ethers/lib/utils';

const targetChainConfig = config.targetChain;
const { bondToken, transactionAllocator } = targetChainConfig;

export class Relayer {
  wallet: Wallet;
  windowLength = 0;
  application: IWormholeApplication;
  windowsSelectedIn = new Set<number>();
  windowsSelectedInButNoTransactions = new Set<number>();
  claimedRewards = BigNumber.from(0);
  nonceManager?: NonceManager;

  static stateHashCache: Map<number, [string, string]> = new Map();
  static allotedRelayersCache: Map<number, string[]> = new Map();

  constructor(
    privateKey: string,
    public readonly stake: BigNumber,
    private readonly mempool: Mempool
  ) {
    this.wallet = new Wallet(privateKey, config.targetChain.httpProvider);
    this.application = IWormholeApplication__factory.connect(
      transactionAllocator.address,
      this.wallet
    );
    console.log("Relayer's address: ", this.wallet.address);
  }

  public async init() {
    this.windowLength = (await transactionAllocator.blocksPerWindow()).toNumber();
    console.log(`Relayer ${this.wallet.address}: Window Length: ${this.windowLength}`);
    this.nonceManager = await NonceManagerFactory.getNonceManager(this.wallet);

    // Fund Relayer
    const relayerBalance = await this.wallet.getBalance();
    if (relayerBalance.lt(targetChainConfig.fundingAmount)) {
      console.log(`Relayer ${this.wallet.address}: Funding..`);
      const nonceManager = await NonceManagerFactory.getNonceManager(
        targetChainConfig.fundingWallet
      );
      await logTransaction(
        targetChainConfig.fundingWallet.sendTransaction({
          to: this.wallet.address,
          nonce: await nonceManager.getNextNonce(),
          value: targetChainConfig.fundingAmount,
        }),
        `Relayer ${this.wallet.address}: Funding Tx`
      );
    }

    if ((await transactionAllocator.relayerInfo(this.wallet.address)).stake.gt(0)) {
      console.log(`Relayer ${this.wallet.address}: Relayer already registered`);
      return;
    }

    console.log(`Relayer ${this.wallet.address}: Registering..`);

    // Mint Token
    console.log(`Relayer ${this.wallet.address}: Minting tokens..`);
    await logTransaction(
      bondToken.connect(this.wallet).mint(this.wallet.address, this.stake, {
        nonce: this.nonceManager.getNextNonce(),
      }),
      `Relayer ${this.wallet.address}: Tokens mint`
    );

    // Approve Tokens
    console.log(`Relayer ${this.wallet.address}: Approving tokens..`);
    await logTransaction(
      bondToken.connect(this.wallet).approve(transactionAllocator.address, this.stake, {
        nonce: await this.nonceManager.getNextNonce(),
      }),
      `Relayer ${this.wallet.address}: Tokens Approval`
    );

    const [, latestHash] = await transactionAllocator.relayerStateHash();
    const relayerState = hashToRelayerState[latestHash];
    if (!relayerState) {
      throw new Error(
        `Relayer ${this.wallet.address}: Relayer state not found for hash ${latestHash}`
      );
    }

    // Register
    console.log(`Relayer ${this.wallet.address}: Registering..`);
    await logTransaction(
      transactionAllocator
        .connect(this.wallet)
        .register(relayerState, this.stake, [this.wallet.address], 'endpoint', 0, {
          nonce: await this.nonceManager.getNextNonce(),
        }),
      `Relayer ${this.wallet.address}: Registered`
    );
  }

  private getactiveStateIndexToExpectedMemoryStateIndex(
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

    const [currentStateHash, latestHash] = await transactionAllocator.relayerStateHash();
    Relayer.stateHashCache.set(window, [currentStateHash, latestHash]);
    return [currentStateHash, latestHash];
  }

  private async getAllotedRelayers(window: number): Promise<string[]> {
    if (Relayer.allotedRelayersCache.has(window)) {
      return Relayer.allotedRelayersCache.get(window)!;
    }

    const { currentState } = await this.getState();

    const [allotedRelayers] = await transactionAllocator.allocateRelayers(currentState);
    Relayer.allotedRelayersCache.set(window, allotedRelayers);
    return allotedRelayers;
  }

  public async claimRewards() {
    const relayerStatus = (await transactionAllocator.relayerInfo(this.wallet.address)).status;
    if (relayerStatus === 3) {
      console.log(`Relayer ${this.wallet.address}: Relayer is jailed. Not claiming rewards`);
      return;
    }

    console.log(`Relayer ${this.wallet.address}: Claiming rewards`);
    const balanceBefore = await bondToken.balanceOf(this.wallet.address);
    await logTransaction(
      transactionAllocator.connect(this.wallet).claimProtocolReward({
        nonce: await this.nonceManager!.getNextNonce(),
      }),
      `Relayer ${this.wallet.address}: Claimed rewards`
    );
    const balanceAfter = await bondToken.balanceOf(this.wallet.address);
    this.claimedRewards = this.claimedRewards.add(balanceAfter.sub(balanceBefore));
  }

  private async isRelayerSelected(windowIndex: number): Promise<boolean> {
    const allotedRelayers = await this.getAllotedRelayers(windowIndex);
    return allotedRelayers.includes(this.wallet.address);
  }

  private async getState() {
    const [currentStateHash, latestStateHash] = await transactionAllocator.relayerStateHash();
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
      const values = new Array(txnAllocated.length).fill(parseEther('0.02'));
      const value = values.reduce((a, b) => a.add(b), BigNumber.from(0));
      await logTransaction(
        transactionAllocator.connect(this.wallet).execute(
          {
            reqs: txnAllocated,
            forwardedNativeAmounts: values,
            relayerIndex,
            relayerGenerationIterationBitmap: relayerGenerationIterations,
            activeState: currentState,
            latestState: latestState,
            activeStateIndexToExpectedMemoryStateIndex:
              this.getactiveStateIndexToExpectedMemoryStateIndex(currentState, latestState),
          },
          {
            nonce: await this.nonceManager!.getNextNonce(),
            value,
          }
        ),
        `Relayer ${this.wallet.address}: Submitted transaction at ${blockNumber}`
      );
      // Delete transactions from mempool
      console.log(`Relayer ${this.wallet.address}: Deleting transactions from mempool`);
    } catch (e) {
      console.log(e);
      process.exit(1);
    }

    await this.mempool.removeTransactions(txnAllocated);
  }

  public async run() {
    targetChainConfig.wsProvider.on('block', async (blockNumber: number) => {
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
      ] = await this.application.allocateWormholeDeliveryVAA(
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
  }

  public getAdddress() {
    return this.wallet.address;
  }
}
