import { ethers } from 'hardhat';
import {
  TADelegation__factory,
  TAProxy__factory,
  TARelayerManagement__factory,
  TATransactionAllocation__factory,
  ApplicationMock__factory,
  MockERC20__factory,
  MockERC20,
} from '../typechain-types';
import { ITransactionAllocator__factory } from '../typechain-types/factories/src/transaction-allocator/interfaces';
import { InitalizerParamsStruct } from '../typechain-types/src/transaction-allocator/TAProxy';
import { getSelectors } from './utils';

export const deploy = async (params: InitalizerParamsStruct) => {
  console.log('Deploying contract...');
  const [deployer] = await ethers.getSigners();

  // Deploy Modules
  const taDelegationModule = await new TADelegation__factory(deployer).deploy();
  const taRelayerManagmenetModule = await new TARelayerManagement__factory(deployer).deploy();
  const taTransactionAllocationModule = await new TATransactionAllocation__factory(
    deployer
  ).deploy();

  const modules = [taDelegationModule, taRelayerManagmenetModule, taTransactionAllocationModule];

  // Deploy Token
  let token: MockERC20;
  if (params.bondTokenAddress === ethers.constants.AddressZero) {
    token = await new MockERC20__factory(deployer).deploy('BICO', 'BICO');
    params.bondTokenAddress = token.address;
  } else {
    token = MockERC20__factory.connect(await params.bondTokenAddress, deployer);
  }

  // Deploy Proxy
  const proxy = await new TAProxy__factory(deployer).deploy(
    modules.map((module) => module.address),
    modules.map((module) => getSelectors(module.interface)),
    params
  );
  const txnAllocator = ITransactionAllocator__factory.connect(proxy.address, deployer);

  // Deploy Mock
  const txMock = await new ApplicationMock__factory(deployer).deploy();

  return { txnAllocator, txMock, token };
};
