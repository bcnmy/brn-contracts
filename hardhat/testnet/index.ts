import { config } from './config';
import { Mempool } from './mempool';
import { Relayer } from './relayer';
import { Wallet } from 'ethers';
import { metrics } from './metrics';

(async () => {
  console.log('Starting simulation..');

  // Initialize the Mempool
  const mempool = new Mempool();

  // Initialize the relayers
  const relayers: Relayer[] = [];

  // Initialize the foundation relayer
  relayers.push(
    new Relayer(
      process.env.FOUNDATION_RELAYER_PRIVATE_KEY!,
      (
        await config.transactionAllocator.relayerInfo(
          new Wallet(process.env.FOUNDATION_RELAYER_PRIVATE_KEY!, config.httpProvider).address
        )
      ).stake,
      mempool
    )
  );
  await relayers[0].init();

  // Initialize rest of the relayers
  for (let i = 1; i < config.relayerCount; i++) {
    const stake = (await config.transactionAllocator.minimumStakeAmount()).mul(i);
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

  await metrics.setRelayers(
    relayers.map((r) => r.getAdddress()),
    relayers.map((r) => r.stake)
  );

  // Start the relayers
  for (const relayer of relayers) {
    relayer.run();
  }

  // Start the mempool
  mempool.init();
})();
