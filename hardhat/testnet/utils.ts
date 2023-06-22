import type { ContractReceipt, ContractTransaction } from 'ethers';

export const logTransaction = async (
  tx: Promise<ContractTransaction>,
  log: string,
  wait: number | undefined = undefined
): Promise<ContractReceipt> => {
  try {
    const receipt = await (await tx).wait(wait);
    const { transactionHash, status } = receipt;
    if (status === 0) {
      console.log(`${log}:  ${transactionHash} failed`);
    } else {
      console.log(`${log}:  ${transactionHash} succeeded`);
    }
    return receipt;
  } catch (e) {
    console.log(`Error in ${log}:  ${JSON.stringify(e)}`);
    throw e;
  }
};
