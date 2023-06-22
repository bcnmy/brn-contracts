import { IWormholeApplication__factory } from '../../typechain-types';
import { config } from './config';
import { Mempool } from './mempool';
import { Relayer } from './relayer';
import { Wallet } from 'ethers';

const initializeWormholeApplication = async () => {
  const application = IWormholeApplication__factory.connect(
    config.targetChain.transactionAllocator.address,
    config.targetChain.fundingWallet
  );
  await application.initializeWormholeApplication(
    config.targetChain.wormholeCoreAddress,
    config.targetChain.wormholeRelayerAddress
  );
};

(async () => {
  console.log('Starting testnet run..');

  // await initializeWormholeApplication();

  const { targetChain } = config;

  // Initialize the Mempool
  const mempool = new Mempool();

  // Initialize the relayers
  const relayers: Relayer[] = [];

  // Initialize the foundation relayer
  relayers.push(
    new Relayer(
      process.env.FOUNDATION_RELAYER_PRIVATE_KEY!,
      (
        await targetChain.transactionAllocator.relayerInfo(
          new Wallet(process.env.ANVIL_DEFAULT_PRIVATE_KEY!, targetChain.httpProvider).address
        )
      ).stake,
      mempool
    )
  );
  await relayers[0].init();

  // Initialize rest of the relayers
  for (let i = 1; i < config.relayerCount; i++) {
    const stake = (await targetChain.transactionAllocator.minimumStakeAmount()).mul(i);
    const relayer = new Relayer(
      Wallet.fromMnemonic(
        process.env.RELAYER_GENERATION_SEED_PHRASE!,
        `m/44'/60'/0'/0/${i}`
      ).privateKey,
      stake,
      mempool
    );
    await relayer.init();
    relayers.push(relayer);
  }

  // Start the relayers
  for (const relayer of relayers) {
    relayer.run();
  }

  // Start the mempool
  mempool.init();
})();
