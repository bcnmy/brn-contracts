import { ethers } from 'hardhat';
import {
  TADelegation__factory,
  TAProxy__factory,
  TARelayerManagement__factory,
  TATransactionAllocation__factory,
  TransactionMock__factory,
} from '../typechain-types';
import { ITransactionAllocator__factory } from '../typechain-types/factories/src/transaction-allocator/interfaces';
import { InitalizerParamsStruct } from '../typechain-types/src/transaction-allocator/TAProxy';
import { getSelectors } from './utils';
const deploymentConfig = require('../script/TA.Deployment.Config.json');

export const deploy = async (params: InitalizerParamsStruct = deploymentConfig) => {
  console.log('Deploying contract...');
  const [deployer] = await ethers.getSigners();

  // Deploy Modules
  const taDelegationModule = await new TADelegation__factory(deployer).deploy();
  const taRelayerManagmenetModule = await new TARelayerManagement__factory(deployer).deploy();
  const taTransactionAllocationModule = await new TATransactionAllocation__factory(
    deployer
  ).deploy();

  const modules = [taDelegationModule, taRelayerManagmenetModule, taTransactionAllocationModule];

  // Deploy Proxy
  const proxy = await new TAProxy__factory(deployer).deploy(
    modules.map((module) => module.address),
    modules.map((module) => getSelectors(module.interface)),
    params
  );
  const txnAllocator = ITransactionAllocator__factory.connect(proxy.address, deployer);

  // Deploy Mock
  const txMock = await new TransactionMock__factory(deployer).deploy();

  return { txnAllocator, txMock };
};
