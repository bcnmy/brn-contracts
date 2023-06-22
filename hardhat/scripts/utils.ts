import { Interface } from 'ethers/lib/utils';

export const getSelectors = (_interface: Interface) => {
  const signatures = Object.keys(_interface.functions);
  const selectors = signatures
    .filter((v) => v !== 'init(bytes)')
    .map((v) => _interface.getSighash(v));
  return selectors;
};
