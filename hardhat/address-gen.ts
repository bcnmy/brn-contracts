import { ethers } from 'ethers';
import * as dotenv from 'dotenv';

dotenv.config();

const seedPharse = process.env.RELAYER_GENERATION_SEED_PHRASE;

if (!seedPharse) {
  throw new Error('No seed phrase found');
}

for (let i = 0; i < 10; ++i) {
  const wallet = ethers.Wallet.fromMnemonic(
    process.env.RELAYER_GENERATION_SEED_PHRASE!,
    `m/44'/60'/0'/0/${i}`
  );
  console.log(`Address ${i}: ${wallet.address}, privateKey: ${wallet.privateKey}`);
}
