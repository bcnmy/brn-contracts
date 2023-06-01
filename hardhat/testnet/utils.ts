import type { ContractTransaction } from 'ethers';

export const logTransaction = async (
  tx: Promise<ContractTransaction>,
  log: string,
  wait: number | undefined = undefined
) => {
  try {
    const { transactionHash, status } = await (await tx).wait(wait);
    if (status === 0) {
      console.log(`${log}:  ${transactionHash} failed`);
    } else {
      console.log(`${log}:  ${transactionHash} succeeded`);
    }
  } catch (e) {
    console.log(`Error in ${log}:  ${JSON.stringify(e)}`);
    throw e;
  }
};
