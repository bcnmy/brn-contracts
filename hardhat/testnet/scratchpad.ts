import {
  IMockWormholeReceiver__factory,
  ITATransactionAllocation__factory,
} from '../../typechain-types';
import { config } from './config';

const data = '0x4e487b710000000000000000000000000000000000000000000000000000000000000011';
const iface = IMockWormholeReceiver__factory.createInterface();

for (const [, error] of Object.entries(iface.errors)) {
  try {
    const decoded = iface.decodeErrorResult(error, data);

    console.log(error, decoded);
  } catch (e) {}
}
