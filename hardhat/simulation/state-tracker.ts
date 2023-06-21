import { Wallet } from 'ethers';
import { RelayerStateStruct } from '../../typechain-types/src/mock/minimal-application/MinimalApplication';
import { config } from './config';

export const hashToRelayerState: Record<string, RelayerStateStruct> = {};

config.transactionAllocatorWs.on(
  'NewRelayerState',
  (latestHash: string, latestRelayerState: RelayerStateStruct) => {
    console.log(`State Tracker: Received NewRelayerState event with hash: ${latestHash}`);
    hashToRelayerState[latestHash] = latestRelayerState;
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
  const defaultHash = '0x8ebc1cb924d705d3d4201a6d0a45bfd5db9e0a7f2203d4ec44da62b0f1233ed9';
  const foundationRelayerAddress = new Wallet(
    process.env.ANVIL_DEFAULT_PRIVATE_KEY!,
    config.httpProvider
  ).address;
  const relayers = [foundationRelayerAddress];
  const cdf = [10000];
  hashToRelayerState[defaultHash] = {
    cdf,
    relayers,
  };

  for (const log of logs) {
    const parsedLog = config.transactionAllocator.interface.parseLog(log);
    hashToRelayerState[parsedLog.args.relayerStateHash] = parsedLog.args.relayerState;
    console.log(
      `State Tracker: Fetched state for hash: ${parsedLog.args.relayerStateHash}: ${JSON.stringify(
        parsedLog.args.relayerState,
        null,
        2
      )}`
    );
  }
})();
