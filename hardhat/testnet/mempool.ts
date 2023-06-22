import { solidityKeccak256 } from 'ethers/lib/utils';
import { config } from './config';
import { NonceManagerFactory } from './nonce-manager';
import { logTransaction } from './utils';
import { ContractReceipt, constants } from 'ethers';
import {
  parseSequenceFromLogEth,
  getSignedVAA,
  ChainId,
  getEmitterAddressEth,
  parseSequencesFromLogEth,
} from '@certusone/wormhole-sdk';
import { NodeHttpTransport } from '@improbable-eng/grpc-web-node-http-transport';
import { IWormholeApplication__factory } from '../../typechain-types/factories/src/wormhole/interfaces';

export class Mempool {
  pool: Set<string> = new Set();

  hashes = [];

  public async init() {
    await this.generateTransaction();
    setInterval(async () => {
      await this.generateTransaction();
    }, config.generationIntervalSec * 1000);
    // this.processMockWormholeReceiverSourceTransactionReceipts(
    //   await Promise.all(
    //     this.hashes.map(async (hash) => config.sourceChain.httpProvider.getTransactionReceipt(hash))
    //   )
    // );
  }

  private async generateTransaction() {
    const { txGenerator, receiver, chainId: sourceChainId, gasPrice } = config.sourceChain;
    const { wormholeChainId: targetWormholeChainId, receiver: targetReceiver } = config.targetChain;

    const nonceManager = await NonceManagerFactory.getNonceManager(txGenerator);

    const receipts = await Promise.all(
      new Array(config.transactionsPerGenerationInterval).fill(1).map(async () => {
        const nonce = await nonceManager.getNextNonce();
        console.log(
          `Peforming wormhole transaction with nonce ${nonce} on source chain ${sourceChainId}...`
        );
        return await logTransaction(
          receiver
            .connect(txGenerator)
            .sendPayload(
              targetWormholeChainId,
              solidityKeccak256(['uint256'], [Math.floor(Math.random() * 1000000)]),
              config.executionGasLimit,
              0,
              targetReceiver.address,
              {
                nonce,
                gasPrice,
              }
            ),
          'Wormhole Source Transaction Sent'
        );
      })
    );

    await this.processMockWormholeReceiverSourceTransactionReceipts(receipts);
  }

  public async getTransactions(): Promise<Set<string>> {
    const transactions = new Set(this.pool);
    return transactions;
  }

  public async removeTransactions(tx: string[]) {
    tx.forEach((t) => {
      this.pool.delete(t);
    });
  }

  private async processMockWormholeReceiverSourceTransactionReceipts(receipts: ContractReceipt[]) {
    const {
      chainId,
      wormholeCoreAddress: bridgeAddress,
      wormholeRelayerAddress: emitterAddress,
      wormholeEmitterChainName: emitterChain,
    } = config.sourceChain;

    const deliveryVAASequences = receipts
      .map((r) => parseSequencesFromLogEth(r, bridgeAddress))
      .reduce((a, b) => a.concat(b), []);

    console.log(`Delivery VAA sequences: ${deliveryVAASequences}`);

    const deliveryVAAs = await Promise.all(
      deliveryVAASequences.map(
        async (sequence) =>
          await new Promise<Uint8Array>((resolve, reject) => {
            let counter = 0;
            const id = setInterval(async () => {
              try {
                counter += 1;
                console.log(
                  `Polling for wormhole VAA for sequence ${sequence} on chain ${chainId}`
                );
                const { vaaBytes } = await getSignedVAA(
                  config.wormholeRpc,
                  emitterChain as ChainId,
                  getEmitterAddressEth(emitterAddress),
                  sequence,
                  {
                    transport: NodeHttpTransport(),
                  }
                );
                clearInterval(id);
                resolve(vaaBytes);
              } catch (e) {
                console.error(
                  `Failed to get VAA for sequence ${sequence} with error ${JSON.stringify(
                    e
                  )}, retrying...`
                );
              }
            }, config.wormholePollingIntervalMs);
          })
      )
    );

    console.log('fetching VAAs complete');

    const txs = deliveryVAAs.map((vaa) =>
      IWormholeApplication__factory.createInterface().encodeFunctionData('executeWormhole', [
        [],
        vaa,
        [],
      ])
    );

    txs.forEach((t) => {
      this.pool.add(t);
    });
  }
}
