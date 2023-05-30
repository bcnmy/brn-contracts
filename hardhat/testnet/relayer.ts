import { BigNumber, BigNumberish, Wallet } from 'ethers';
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

  constructor(
    privateKey: string,
    private readonly stake: BigNumberish,
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
          value: config.fundingAmount.sub(relayerBalance),
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

  public async run() {
    config.wsProvider.on('block', async (blockNumber: number) => {
      console.log(`Relayer ${this.wallet.address}: New block ${blockNumber}`);

      if (blockNumber % this.windowLength != 0) {
        return;
      }
      console.log(`Relayer ${this.wallet.address}: New window ${blockNumber}`);

      // Check if transactions can be submitted
      const pendingTransactions = Array.from(await this.mempool.getTransactions()).map(
        (tx) => tx.data
      );
      if (pendingTransactions.length === 0) {
        console.log(`Relayer ${this.wallet.address}: No pending transactions`);
        return;
      }

      // Get the current state
      const [currentStateHash, latestHash] = await config.transactionAllocator.relayerStateHash();
      const currentState = hashToRelayerState[currentStateHash];
      if (!currentState) {
        throw new Error(
          `Relayer ${this.wallet.address}: Current state not found for hash ${currentStateHash}`
        );
      }
      const latestState = hashToRelayerState[latestHash];
      if (!latestState) {
        throw new Error(
          `Relayer ${this.wallet.address}: Latest state not found for hash ${latestHash}`
        );
      }

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
        return;
      } else {
        console.log(
          `Relayer ${this.wallet.address}: Allocated ${txnAllocated.length} transactions`
        );
      }

      // Submit transactions
      console.log(`Relayer ${this.wallet.address}: Submitting transactions`);
      await logTransaction(
        config.transactionAllocator.connect(this.wallet).execute({
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
        }),
        `Relayer ${this.wallet.address}: Submitted transactions`
      );
    });
  }
}
