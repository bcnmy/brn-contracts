import { BigNumberish, Wallet } from 'ethers';
import { config } from './config';
import fs from 'fs';
import path from 'path';
import { parseEther, solidityKeccak256 } from 'ethers/lib/utils';
import { RelayerStateManager } from '../../typechain-types/src/wormhole/WormholeApplication';

const hashToRelayerStatePath = path.join(__dirname, 'hashToRelayerState.json');

// Read hashToRelayerState from a file
export const hashToRelayerState: Record<string, RelayerStateManager.RelayerStateStruct> =
  fs.existsSync(hashToRelayerStatePath)
    ? JSON.parse(fs.readFileSync(hashToRelayerStatePath).toString())
    : {};

const targetChainConfig = config.targetChain;
const { transactionAllocatorWs, httpProvider } = targetChainConfig;

transactionAllocatorWs.on(
  'NewRelayerState',
  (latestHash: string, relayers: string[], cdf: BigNumberish[]) => {
    console.log(`State Tracker: Received NewRelayerState event with hash: ${latestHash}`);
    hashToRelayerState[latestHash] = {
      cdf,
      relayers,
    };

    // Write hashToRelayerState to a file
    fs.writeFileSync(hashToRelayerStatePath, JSON.stringify(hashToRelayerState));
  }
);

// Default Case
const foundationRelayerAddress = new Wallet(
  process.env.TESTNET_FOUNDATION_RELAYER_PRIVATE_KEY!,
  httpProvider
).address;
const relayers = [foundationRelayerAddress];
const cdf = [parseEther('10000')];

const defaultHash = solidityKeccak256(
  ['bytes32', 'bytes32'],
  [solidityKeccak256(['uint16[]'], [cdf]), solidityKeccak256(['address[]'], [relayers])]
);

console.log('Default Hash: ', defaultHash);

hashToRelayerState[defaultHash] = {
  cdf,
  relayers,
};
