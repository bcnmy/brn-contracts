import AsyncLock from 'async-lock';
import PriorityQueue from 'js-priority-queue';
import { ethers } from 'ethers';

export class NonceManager {
  static #lock = new AsyncLock();
  #baseNonce = -1;
  #requestIndex = 0;
  #wallet: ethers.Wallet;
  #erroredNonces = new PriorityQueue<number>({ comparator: (a, b) => a - b });
  chainId: number;

  constructor(chainId: number, wallet: ethers.Wallet) {
    this.chainId = chainId;
    this.#wallet = wallet;
  }

  initialize = async () => {
    this.#baseNonce = await this.getBaseNonce();
    console.log(
      `Set base nonce for ${await this.#wallet.getAddress()} on ${this.chainId} as ${
        this.#baseNonce
      }`
    );
  };

  getNextNonce = async () => {
    let newNonce = -1;
    if (this.#baseNonce === -1) {
      throw new Error(`Base nonce is not set for chain ${this.chainId}`);
    }
    await NonceManager.#lock.acquire(
      `${await this.#wallet.getAddress()}_${this.chainId}_nonce`,
      async (done) => {
        if (
          this.#erroredNonces.length > 0 &&
          this.#erroredNonces.peek() < this.#baseNonce + this.#requestIndex
        ) {
          newNonce = this.#erroredNonces.dequeue();
        } else {
          newNonce = this.#baseNonce + this.#requestIndex++;
        }
        done();
      }
    );
    if (newNonce === -1) {
      throw new Error(`Nonce is not set for chain ${this.chainId}`);
    }
    console.log(
      `Next nonce for ${await this.#wallet.getAddress()} on ${this.chainId} is ${newNonce}`
    );
    return newNonce;
  };

  submitDeadNonce = (nonce: number) => this.#erroredNonces.queue(nonce);

  private getBaseNonce = async () => await this.#wallet.getTransactionCount();
}

export class NonceManagerFactory {
  static #nonceManagerMap: Record<string, Record<number, NonceManager>> = {};
  static #lock = new AsyncLock();

  static async getNonceManager(wallet: ethers.Wallet): Promise<NonceManager> {
    const address = await wallet.getAddress();
    const chainId = await wallet.getChainId();

    return new Promise((resolve, reject) => {
      try {
        NonceManagerFactory.#lock.acquire(`${address}_${chainId}_nonce_manager`, async (done) => {
          try {
            if (!NonceManagerFactory.#nonceManagerMap[address]?.[chainId]) {
              console.log(`Creating nonce manager for chain ${chainId}`);
              const nonceManager = new NonceManager(chainId, wallet);
              await nonceManager.initialize();
              if (!NonceManagerFactory.#nonceManagerMap[address]) {
                NonceManagerFactory.#nonceManagerMap[address] = {};
              }
              NonceManagerFactory.#nonceManagerMap[address][chainId] = nonceManager;
            }
            resolve(this.#nonceManagerMap[address][chainId]);
            done();
          } catch (e) {
            reject(new Error(`Error creating nonce manager: ${e}`));
          }
        });
      } catch (e) {
        reject(new Error(`Error taking lock for nonce manager creation: ${e}`));
      }
    });
  }
}
