import { IWormhole__factory, WormholeRelayerMock__factory } from '../typechain-types';

const data =
  '0x79cbfdbe00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000001';

const iface = WormholeRelayerMock__factory.createInterface();

for (const [, error] of Object.entries(iface.errors)) {
  try {
    const result = WormholeRelayerMock__factory.createInterface().decodeErrorResult(error, data);

    console.log(error, result);
  } catch (e) {}
}
