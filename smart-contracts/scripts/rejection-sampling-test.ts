import { BigNumber } from 'ethers';
import { solidityKeccak256 } from 'ethers/lib/utils';

const windowLength = 10;

const runs = 10;
const totalRelayers = 5000;
const blockNumber = 12313110;
const relayersPerWindow = 1000;

const selectionRandomValues = (iteration: number, selectionIndex: number, maxStake: BigNumber) => {
  const baseHash = solidityKeccak256(['uint256'], [BigNumber.from(blockNumber).div(windowLength)]);
  return {
    randomIndex: BigNumber.from(
      solidityKeccak256(
        ['bytes32', 'uint256', 'uint256', 'uint256'],
        [baseHash, iteration, selectionIndex, 1]
      )
    ).mod(totalRelayers),
    randomStake: BigNumber.from(
      solidityKeccak256(
        ['bytes32', 'uint256', 'uint256', 'uint256'],
        [baseHash, iteration, selectionIndex, 2]
      )
    ).mod(maxStake),
  };
};

(async () => {
  const randomStakes = Array.from({ length: totalRelayers }, () =>
    BigNumber.from(10)
      .pow(18)
      .mul(Math.floor(Math.random() * 10000))
  );

  const maxStake = randomStakes.reduce((a, b) => (a.gt(b) ? a : b));

  const selectionsCount = new Array(runs)
    .fill(0)
    .map(() =>
      new Array(relayersPerWindow).fill(0).map((_, index) => {
        let selections = 0;
        while (true) {
          const { randomIndex, randomStake } = selectionRandomValues(index, selections, maxStake);
          if (randomStake.lte(randomStakes[randomIndex.toNumber()])) {
            break;
          }
          selections++;
        }
        return selections + 1;
      })
    )
    .reduce((a, b) => a.concat(b), []);

  const maxSelections = selectionsCount.reduce((a, b) => (a > b ? a : b));
  const minSelections = selectionsCount.reduce((a, b) => (a < b ? a : b));
  const averageSelections = selectionsCount.reduce((a, b) => a + b, 0) / selectionsCount.length;
  const medianSelections = selectionsCount.sort((a, b) => a - b)[
    Math.floor(selectionsCount.length / 2)
  ];
  // Generate frequency table
  const frequencyTable = selectionsCount.reduce((acc, val) => {
    (acc as any)[val] = ((acc as any)[val] || 0) + 1;
    return acc;
  }, {});
  console.log(
    JSON.stringify(
      { maxSelections, minSelections, averageSelections, medianSelections, frequencyTable },
      null,
      2
    )
  );
})();
