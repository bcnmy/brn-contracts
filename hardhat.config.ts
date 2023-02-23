import { HardhatUserConfig } from 'hardhat/config';
import { execSync } from 'child_process';
import '@typechain/hardhat';
import 'hardhat-preprocessor';
import '@nomiclabs/hardhat-ethers';

const config: HardhatUserConfig = {
  solidity: {
    compilers: [
      {
        version: '0.8.17',
        settings: {
          outputSelection: {
            '*': {
              '*': ['storageLayout'],
            },
          },
          optimizer: {
            enabled: true,
            runs: 2000,
          },
          viaIR: true,
        },
      },
    ],
  },
  preprocess: {
    eachLine: (hre) => ({
      transform: (line: string) => {
        if (line.match(/^\s*import /i)) {
          for (const [from, to] of getRemappings()) {
            if (line.includes(from)) {
              line = line.replace(from, to);
              break;
            }
          }
        }
        return line;
      },
    }),
  },
  paths: {
    sources: './src',
    cache: './cache_hardhat',
  },
};

let getRawRemappings = (): string => {
  const remappings = execSync('forge remappings', { encoding: 'utf8' });
  console.log(`Output of "forge remappings":\n${remappings}`);
  getRawRemappings = () => remappings;
  return remappings;
};

const getRemappings = () =>
  getRawRemappings()
    .split('\n')
    .filter(Boolean) // remove empty lines
    .map((line) => line.trim().split('='));

export default config;
