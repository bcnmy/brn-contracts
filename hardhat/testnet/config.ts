import * as dotenv from 'dotenv';
import { ethers } from 'ethers';
import {
  BRNWormholeDeliveryProvider__factory,
  ERC20FreeMint__factory,
  ITransactionAllocator__factory,
  MockWormholeReceiver__factory,
} from '../../typechain-types';
import { ChainId } from '@certusone/wormhole-sdk';
import { parseUnits } from 'ethers/lib/utils';

dotenv.config();

const addresses = {
  80001: {
    WormholeDeliveryProvider: '0x222E53bfA14e8686a165d0b88779535eA7C13eA7',
    MockWormholeReceiver: '0x7A7771c89CDfEd3dFb92DEEaFaca4472a14b01Ba',
    WormholeCore: '0x0CBE91CF822c73C2315FB05100C2F714765d5c20',
    WormholeRelayer: '0x0591C25ebd0580E0d4F27A82Fc2e24E7489CB5e0',
  },
  43113: {
    Token: '0xF9C3e58C6ca8DF57F5BC94c7ecCCABFaE3845068',
    TAProxy: '0xC5C04dEc932138935b6c1A31206e1FB63e2f5527',
    WormholeDeliveryProvider: '0xFc42BfbbA51B448c2A82e0f8d85064486352D0f7',
    MockWormholeReceiver: '0xB9B32A13C612eC7E6Ad804f9C052992b0131aA3C',
    WormholeCore: '0x7bbcE28e64B3F8b84d876Ab298393c38ad7aac4C',
    WormholeRelayer: '0xA3cF45939bD6260bcFe3D66bc73d60f19e49a8BB',
  },
};

const providers = {
  80001: {
    rpc: process.env.MUMBAI_RPC_URL!,
    httpProvider: new ethers.providers.JsonRpcBatchProvider(process.env.MUMBAI_RPC_URL!),
    wsProvider: new ethers.providers.WebSocketProvider(process.env.MUMBAI_WS_URL!),
  },
  43113: {
    rpc: process.env.FUJI_RPC_URL!,
    httpProvider: new ethers.providers.JsonRpcBatchProvider(process.env.FUJI_RPC_URL!),
    wsProvider: new ethers.providers.WebSocketProvider(process.env.FUJI_WS_URL!),
  },
};

const chainIdToWormholeChain = {
  80001: 5,
  43113: 6,
};

const wormholeEmitterChainName: Record<number, ChainId> = {
  1: 'ethereum',
  10: 'optimism',
  56: 'bsc',
  137: 'polygon',
  250: 'fantom',
  42161: 'arbitrum',
  43114: 'avalanche',
  5: 'ethereum',
  69: 'optimism',
  420: 'optimism',
  97: 'bsc',
  80001: 'polygon',
  4002: 'fantom',
  421611: 'arbitrum',
  43113: 'avalanche',
} as unknown as Record<number, ChainId>;

const sourceChain = 80001;
const targetChain = 43113;

const config = {
  sourceChain: {
    chainId: sourceChain,
    gasPrice: parseUnits('5', 'gwei'),
    wormholeChainId: chainIdToWormholeChain[sourceChain],
    wormholeEmitterChainName: wormholeEmitterChainName[sourceChain],
    wormholeCoreAddress: addresses[sourceChain].WormholeCore,
    wormholeRelayerAddress: addresses[sourceChain].WormholeRelayer,
    txGenerator: new ethers.Wallet(process.env.PRIVATE_KEY!, providers[sourceChain].httpProvider),
    ...providers[sourceChain],
    deliveryProvider: BRNWormholeDeliveryProvider__factory.connect(
      addresses[sourceChain].WormholeDeliveryProvider,
      providers[sourceChain].httpProvider
    ),
    receiver: MockWormholeReceiver__factory.connect(
      addresses[sourceChain].MockWormholeReceiver,
      providers[sourceChain].httpProvider
    ),
  },
  targetChain: {
    chainId: targetChain,
    wormholeChainId: chainIdToWormholeChain[targetChain],
    wormholeEmitterChainName: wormholeEmitterChainName[targetChain],
    wormholeCoreAddress: addresses[targetChain].WormholeCore,
    wormholeRelayerAddress: addresses[targetChain].WormholeRelayer,
    fundingWallet: new ethers.Wallet(process.env.PRIVATE_KEY!, providers[targetChain].httpProvider),
    fundingAmount: ethers.utils.parseEther('0.01'),
    taDeploymentBlock: 23333519,
    ...providers[targetChain],
    bondToken: ERC20FreeMint__factory.connect(
      addresses[targetChain].Token,
      providers[targetChain].httpProvider
    ),
    transactionAllocator: ITransactionAllocator__factory.connect(
      addresses[targetChain].TAProxy,
      providers[targetChain].httpProvider
    ),
    transactionAllocatorWs: ITransactionAllocator__factory.connect(
      addresses[targetChain].TAProxy,
      providers[targetChain].wsProvider
    ),
    deliveryProvider: BRNWormholeDeliveryProvider__factory.connect(
      addresses[targetChain].WormholeDeliveryProvider,
      providers[targetChain].httpProvider
    ),
    receiver: MockWormholeReceiver__factory.connect(
      addresses[targetChain].MockWormholeReceiver,
      providers[targetChain].httpProvider
    ),
  },
  transactionsPerGenerationInterval: 1,
  generationIntervalSec: 10000,
  relayerCount: 3,
  inactiveRelayers: [ethers.constants.AddressZero],
  executionGasLimit: 100000,
  wormholePollingIntervalMs: 1000,
  wormholeRpc: 'https://wormhole-v2-testnet-api.certus.one',
};

export { config };
