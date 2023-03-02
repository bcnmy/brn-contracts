import { HardhatUserConfig } from 'hardhat/config';
import '@typechain/hardhat';
import '@nomiclabs/hardhat-ethers';
import '@nomicfoundation/hardhat-foundry';

const config: HardhatUserConfig = {
  solidity: {
    compilers: [
      {
        version: '0.8.19',
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
};

export default config;
