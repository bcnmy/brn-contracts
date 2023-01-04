import { time, loadFixture } from "@nomicfoundation/hardhat-network-helpers";
import { anyValue } from "@nomicfoundation/hardhat-chai-matchers/withArgs";
import { expect } from "chai";
import { ethers } from "hardhat";
import { Interface } from "ethers/lib/utils";

describe("BRN", function () {
  async function deployTxnAllocator() {

    const [deployer, relayer1, relayer1Acc1, relayer1Acc2, relayer2, relayer2Acc1, relayer2Acc2, relayer3, relayer3Acc1, relayer3Acc2] = await ethers.getSigners();
    
    const blocksWindow = 10
    const withdrawDelay = 1
    const relayersPerWindow = 2

    const TxnAllocator = await ethers.getContractFactory("BicoForwarder")
    const txnAllocator = await TxnAllocator.deploy(blocksWindow, withdrawDelay, relayersPerWindow);

    const TransactionMock = await ethers.getContractFactory("TransactionMock")
    const transactionMock = await TransactionMock.deploy();

    return { relayer1, relayer1Acc1, relayer1Acc2, relayer2, relayer2Acc1, relayer2Acc2, relayer3, relayer3Acc1, relayer3Acc2, blocksWindow, withdrawDelay, relayersPerWindow, TxnAllocator, txnAllocator, TransactionMock, transactionMock }

  }

  describe("Deployment", function () {
    it("Should set the right blocksWindow", async function () {
      const { blocksWindow, txnAllocator } = await loadFixture(deployTxnAllocator);

      expect(await txnAllocator.blocksWindow()).to.equal(blocksWindow);
    });

    it("Should set the right withdrawDelay", async function () {
      const { withdrawDelay, txnAllocator } = await loadFixture(deployTxnAllocator);

      expect(await txnAllocator.withdrawDelay()).to.equal(withdrawDelay);
    });

    it("Should set the right realyersPerWindow", async function () {
      const { relayersPerWindow, txnAllocator } = await loadFixture(deployTxnAllocator);

      expect(await txnAllocator.relayersPerWindow()).to.equal(relayersPerWindow);
    });
  });

  describe("Registration", function () {
    it("Should register a realyer", async function() {
      
      const { relayer1, relayer1Acc1, relayer1Acc2, TransactionMock ,txnAllocator, transactionMock } = await loadFixture(deployTxnAllocator);
      const txn = await txnAllocator.connect(relayer1).register(ethers.utils.parseEther("1"), [relayer1Acc1.address, relayer1Acc2.address], "endpoint")
      const rc = await txn.wait()
      const filter = txnAllocator.filters.RelayerRegistered()
      //@ts-ignore
      const fromBlock = await ethers.provider.getBlock()
      const events = await txnAllocator.queryFilter(filter, fromBlock.number)
      
      expect(events[0].args.stake).to.be.equal(ethers.utils.parseEther("1"))
      expect(events[0].args.accounts[0]).to.be.equal(relayer1Acc1.address)
      expect(events[0].args.accounts[1]).to.be.equal(relayer1Acc2.address)
      expect(events[0].args.endpoint).to.be.equal("endpoint")

    });
  });

  describe("Relayer Selection", function () {
    it("Should select random relayers", async function() {
      
      const { relayer1, relayer1Acc1, relayer1Acc2, relayer2,relayer2Acc1, relayer2Acc2, relayer3, relayer3Acc1, relayer3Acc2, relayersPerWindow, txnAllocator } = await loadFixture(deployTxnAllocator);
      await txnAllocator.connect(relayer1).register(ethers.utils.parseEther("1"), [relayer1Acc1.address, relayer1Acc2.address], "endpoint")
      await txnAllocator.connect(relayer2).register(ethers.utils.parseEther("2"), [relayer2Acc1.address, relayer2Acc2.address], "endpoint")
      await txnAllocator.connect(relayer3).register(ethers.utils.parseEther("2"), [relayer3Acc1.address, relayer3Acc2.address], "endpoint")
      //TODO: should add set to particular block
      const selectedRelayers = await txnAllocator.allocateRelayers(0);
      expect(selectedRelayers.length).to.be.equal(relayersPerWindow);
      expect(selectedRelayers[0]).to.be.equal(relayer3.address);
      expect(selectedRelayers[1]).to.be.equal(relayer2.address);
    });
  });

  describe("Transaction Allocation", function () {
    it("Should allocate transaction", async function() {
      const { relayer1, relayer1Acc1, relayer1Acc2, TransactionMock, relayer2,relayer2Acc1, relayer2Acc2, relayer3, relayer3Acc1, relayer3Acc2, txnAllocator, transactionMock } = await loadFixture(deployTxnAllocator);
      await txnAllocator.connect(relayer1).register(ethers.utils.parseEther("1"), [relayer1Acc1.address, relayer1Acc2.address], "endpoint")
      await txnAllocator.connect(relayer2).register(ethers.utils.parseEther("2"), [relayer2Acc1.address, relayer2Acc2.address], "endpoint")
      await txnAllocator.connect(relayer3).register(ethers.utils.parseEther("2"), [relayer3Acc1.address, relayer3Acc2.address], "endpoint")

      const calldataAdd = TransactionMock.interface.encodeFunctionData('mockAdd', ["1", "2"]);
      const calldataSub = TransactionMock.interface.encodeFunctionData('mockSubtract', ["12", "2"]);
      const calldataUpd = TransactionMock.interface.encodeFunctionData('mockUpdate', ["12"]);

      const txnAllocated1 = await txnAllocator.connect(relayer1Acc2).allocateTransaction([calldataAdd, calldataSub, calldataUpd])      
      const txnAllocated2 = await txnAllocator.connect(relayer2Acc1).allocateTransaction([calldataAdd, calldataSub, calldataUpd])
      const txnAllocated3 = await txnAllocator.connect(relayer3Acc1).allocateTransaction([calldataAdd, calldataSub, calldataUpd])

      expect(txnAllocated1.length).to.be.equal(0);
      expect(txnAllocated2.length).to.be.equal(2);
      expect(txnAllocated2[0]).to.be.equal(calldataSub);
      expect(txnAllocated2[1]).to.be.equal(calldataUpd);
      expect(txnAllocated3.length).to.be.equal(1);
      expect(txnAllocated3[0]).to.be.equal(calldataAdd);
      
    });
  });

});
