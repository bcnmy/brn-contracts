import { ethers } from 'hardhat';
import { BigNumber, BigNumberish } from 'ethers';
import { keccak256 } from 'ethers/lib/utils';
import { BicoForwarder } from '../typechain-types';

const abiCoder = new ethers.utils.AbiCoder();

const hashFunction = (baseSeed: string, index: number) =>
  keccak256(abiCoder.encode(['bytes32', 'uint256'], [baseSeed, index]));

const findRelayerInStake = async (value: BigNumber, TransactionAllocator: BicoForwarder) => {
  let low = BigNumber.from(0);
  let high = await TransactionAllocator.relayerCount();

  while (low.lt(high)) {
    const mid = low.add(high).div(2);
    const valueAtMid = await TransactionAllocator.relayerStakePrefixSum(mid);
    if (valueAtMid.gte(value)) {
      high = mid;
    } else {
      low = mid.add(1);
    }
  }

  const relayer = await TransactionAllocator.relayerStakePrefixSumIndexToRelayer(low);
  console.log(`Relayer ${relayer} selected at index ${low} against prn ${value}`);
  return { relayer, index: low };
};

export const relayerSelection = async (
  blockNumber: BigNumberish,
  TransactionAllocator: BicoForwarder
): Promise<{
  relayers: string[];
  iterationLog: string[];
  selectionProofs: Record<string, BicoForwarder.SelectionProofStruct>;
}> => {
  const relayersPerWindow = await TransactionAllocator.relayersPerWindow();
  const blocksWindow = await TransactionAllocator.blocksWindow();

  const baseSeed = keccak256(
    abiCoder.encode(['uint256'], [BigNumber.from(blockNumber).div(blocksWindow)])
  );

  const relayerSelectionLog: string[] = [];
  const relayersSelected: string[] = [];
  const relayerSelectionIterationList = new Map<string, number[]>();
  const isRelayerSelected = new Map<string, boolean>();

  // Perfom relayer selection
  let iteration = 0;
  while (relayersPerWindow.gt(relayersSelected.length)) {
    console.log(`Iteration ${iteration}...`);
    const seed = hashFunction(baseSeed, iteration);
    const stakeSum = await TransactionAllocator.relayerStakePrefixSum(
      await TransactionAllocator.relayerCount()
    );
    const randomStake = BigNumber.from(seed).mod(stakeSum);
    const { relayer } = await findRelayerInStake(randomStake, TransactionAllocator);

    if (!isRelayerSelected.has(relayer)) {
      isRelayerSelected.set(relayer, true);
      relayersSelected.push(relayer);
    }

    relayerSelectionLog.push(relayer);
    if (!relayerSelectionIterationList.has(relayer)) {
      relayerSelectionIterationList.set(relayer, []);
    }
    relayerSelectionIterationList.get(relayer)?.push(iteration);
  }

  const selectionProofs: Record<string, BicoForwarder.SelectionProofStruct> = {};
  // Generate Proofs
  for (let i = 0; i < relayerSelectionLog.length; ++i) {
    const chosenRelayer = relayerSelectionLog[i];

    // The selection proof is simply the iteration at which the relayer was selected
    selectionProofs[chosenRelayer] = {
      relayerProof: {
        iteration: i,
      },
      duplicatesProof: [],
    };

    // If duplicate relayers were selected befor this relayer, we need to prove for the duplicates as well
    if (relayersPerWindow.lte(i)) {
      const isDuplicateRelayerSelected = new Map<string, boolean>();
      let currentRelayerIndex = i;
      let duplicateScanIndex = i - 1;

      // Iterate backwards and add duplicate relayers to the list until the chosen relayer
      // falls in the relayersPerWindow window
      while (relayersPerWindow.lte(currentRelayerIndex)) {
        const relayer = relayerSelectionLog[--duplicateScanIndex];
        const relayerSelectionIndices = relayerSelectionIterationList.get(relayer);
        if (!relayerSelectionIndices) {
          throw new Error(`Relayer ${relayer} not found in selection iteration list`);
        }

        if (relayerSelectionIndices.length > 1 && !isDuplicateRelayerSelected.has(relayer)) {
          // Select the duplicate relayer and add to the duplicate proof list
          isDuplicateRelayerSelected.set(relayer, true);
          selectionProofs[chosenRelayer].duplicatesProof.push({
            relayer,
            iterations: relayerSelectionIndices,
          });

          // Update the new position of the chosen relayer after removing the duplicates
          currentRelayerIndex -= relayerSelectionIndices.length - 1;
        }
      }
    }
  }

  return { relayers: relayersSelected, iterationLog: relayerSelectionLog, selectionProofs };
};
