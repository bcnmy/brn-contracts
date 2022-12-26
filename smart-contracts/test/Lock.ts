import { time, loadFixture } from "@nomicfoundation/hardhat-network-helpers";
import { anyValue } from "@nomicfoundation/hardhat-chai-matchers/withArgs";
import { expect } from "chai";
import { ethers } from "hardhat";

describe("Lock", function () {
  // We define a fixture to reuse the same setup in every test.
  // We use loadFixture to run this setup once, snapshot that state,
  // and reset Hardhat Network to that snapshot in every test.
  async function deployTxnAllocator() {
    // const ONE_YEAR_IN_SECS = 365 * 24 * 60 * 60;
    // const ONE_GWEI = 1_000_000_000;

    // const lockedAmount = ONE_GWEI;
    // const unlockTime = (await time.latest()) + ONE_YEAR_IN_SECS;

    // // Contracts are deployed using the first signer/account by default
    // const [owner, otherAccount] = await ethers.getSigners();

    // const Lock = await ethers.getContractFactory("Lock");
    // const lock = await Lock.deploy(unlockTime, { value: lockedAmount });

    // return { lock, unlockTime, lockedAmount, owner, otherAccount };
    const blocksWindow = 10
    const withdrawDelay = 1
    const realyersPerWindow = 2

    const TxnAllocator = await ethers.getContractFactory("BicoForwarder")
    const txnAllocator = await TxnAllocator.deploy(blocksWindow, withdrawDelay, realyersPerWindow);

    const TransactionMock = await ethers.getContractFactory("TransactionMock")
    const transactionMock = await TransactionMock.deploy();

    return { blocksWindow, withdrawDelay, realyersPerWindow, txnAllocator, transactionMock }

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
      const { realyersPerWindow, txnAllocator } = await loadFixture(deployTxnAllocator);

      expect(await txnAllocator.realyersPerWindow()).to.equal(realyersPerWindow);
    });
  });

  // describe("Withdrawals", function () {
  //   describe("Validations", function () {
  //     it("Should revert with the right error if called too soon", async function () {
  //       const { lock } = await loadFixture(deployOneYearLockFixture);

  //       await expect(lock.withdraw()).to.be.revertedWith(
  //         "You can't withdraw yet"
  //       );
  //     });

  //     it("Should revert with the right error if called from another account", async function () {
  //       const { lock, unlockTime, otherAccount } = await loadFixture(
  //         deployOneYearLockFixture
  //       );

  //       // We can increase the time in Hardhat Network
  //       await time.increaseTo(unlockTime);

  //       // We use lock.connect() to send a transaction from another account
  //       await expect(lock.connect(otherAccount).withdraw()).to.be.revertedWith(
  //         "You aren't the owner"
  //       );
  //     });

  //     it("Shouldn't fail if the unlockTime has arrived and the owner calls it", async function () {
  //       const { lock, unlockTime } = await loadFixture(
  //         deployOneYearLockFixture
  //       );

  //       // Transactions are sent using the first signer by default
  //       await time.increaseTo(unlockTime);

  //       await expect(lock.withdraw()).not.to.be.reverted;
  //     });
  //   });

  //   describe("Events", function () {
  //     it("Should emit an event on withdrawals", async function () {
  //       const { lock, unlockTime, lockedAmount } = await loadFixture(
  //         deployOneYearLockFixture
  //       );

  //       await time.increaseTo(unlockTime);

  //       await expect(lock.withdraw())
  //         .to.emit(lock, "Withdrawal")
  //         .withArgs(lockedAmount, anyValue); // We accept any value as `when` arg
  //     });
  //   });

  //   describe("Transfers", function () {
  //     it("Should transfer the funds to the owner", async function () {
  //       const { lock, unlockTime, lockedAmount, owner } = await loadFixture(
  //         deployOneYearLockFixture
  //       );

  //       await time.increaseTo(unlockTime);

  //       await expect(lock.withdraw()).to.changeEtherBalances(
  //         [owner, lock],
  //         [lockedAmount, -lockedAmount]
  //       );
  //     });
  //   });
  // });
});
