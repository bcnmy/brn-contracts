import { BigNumberish, Wallet } from 'ethers';
import { config } from './config';
import { RelayerStateManager } from '../../typechain-types/src/wormhole/WormholeApplication';
import { parseEther } from 'ethers/lib/utils';

export const hashToRelayerState: Record<string, RelayerStateManager.RelayerStateStruct> = {};

config.transactionAllocatorWs.on(
  'NewRelayerState',
  (latestHash: string, relayers: string[], cdf: BigNumberish[]) => {
    console.log(`State Tracker: Received NewRelayerState event with hash: ${latestHash}`);
    hashToRelayerState[latestHash] = {
      relayers,
      cdf,
    };
  }
);

(async () => {
  // Fetch all past events
  const currentBlock = await config.httpProvider.getBlockNumber();
  const logs = await config.httpProvider.getLogs({
    fromBlock: 0,
    toBlock: currentBlock,
    topics: [config.transactionAllocator.interface.getEventTopic('NewRelayerState')],
  });

  // Default Case
  const defaultHash = '0x7172bafae3c84fc55ec0146222525742c1c2f455620fa5d58e2fc57356655ffd';
  const foundationRelayerAddress = new Wallet(
    process.env.ANVIL_DEFAULT_PRIVATE_KEY!,
    config.httpProvider
  ).address;
  const relayers = [foundationRelayerAddress];
  const cdf = [parseEther('10000')];
  hashToRelayerState[defaultHash] = {
    cdf,
    relayers,
  };

  for (const log of logs) {
    const parsedLog = config.transactionAllocator.interface.parseLog(log);
    const [relayerStateHash, relayers, cdf] = parsedLog.args;
    hashToRelayerState[relayerStateHash] = {
      relayers,
      cdf,
    };
    console.log(
      `State Tracker: Fetched state for hash: ${relayerStateHash}: ${JSON.stringify(
        hashToRelayerState[relayerStateHash],
        null,
        2
      )}`
    );
  }
})();
