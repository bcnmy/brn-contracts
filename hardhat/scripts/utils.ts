import { Interface } from 'ethers/lib/utils';
// import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers';
// import { Wallet } from 'ethers';
// import { ITransactionAllocator } from '../typechain-types';

export const getSelectors = (_interface: Interface) => {
  const signatures = Object.keys(_interface.functions);
  const selectors = signatures
    .filter((v) => v !== 'init(bytes)')
    .map((v) => _interface.getSighash(v));
  return selectors;
};

// export const signTransaction = async (
//   tx: ForwardRequestStruct,
//   chainId: number,
//   wallet: SignerWithAddress | Wallet,
//   txnAllocator: ITransactionAllocator
// ): Promise<ForwardRequestStruct> => {
//   const scwAddress = await txnAllocator.predictSmartContractWalletAddress(wallet.address);
//   const domain = {
//     name: 'SmartWallet',
//     version: '1',
//     chainId: chainId.toString(),
//     verifyingContract: scwAddress,
//   };
//   const types = {
//     SmartContractExecutionRequest: [
//       { name: 'from', type: 'address' },
//       { name: 'to', type: 'address' },
//       { name: 'paymaster', type: 'address' },
//       { name: 'value', type: 'uint256' },
//       { name: 'gas', type: 'uint256' },
//       { name: 'fixedgas', type: 'uint256'},
//       { name: 'nonce', type: 'uint256' },
//       { name: 'data', type: 'bytes' },
//     ],
//   };
//   const signature = wallet._signTypedData(domain, types, tx);
//   tx.signature = signature;

//   return tx;
// };
