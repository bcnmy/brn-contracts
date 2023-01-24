import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers';
import { Wallet } from 'ethers';
import { TransactionAllocator } from '../typechain-types';
import type { ForwardRequestStruct } from '../typechain-types/contracts/SmartWallet';

export const signTransaction = async (
  tx: ForwardRequestStruct,
  chainId: number,
  wallet: SignerWithAddress | Wallet,
  txnAllocator: TransactionAllocator
): Promise<ForwardRequestStruct> => {
  const scwAddress = await txnAllocator.predictSmartContractWalletAddress(wallet.address);
  const domain = {
    name: 'SmartWallet',
    version: '1',
    chainId: chainId.toString(),
    verifyingContract: scwAddress,
  };
  const types = {
    SmartContractExecutionRequest: [
      { name: 'from', type: 'address' },
      { name: 'to', type: 'address' },
      { name: 'paymaster', type: 'address' },
      { name: 'value', type: 'uint256' },
      { name: 'gas', type: 'uint256' },
      { name: 'fixedgas', type: 'uint256'},
      { name: 'nonce', type: 'uint256' },
      { name: 'data', type: 'bytes' },
    ],
  };
  const signature = wallet._signTypedData(domain, types, tx);
  tx.signature = signature;

  return tx;
};
