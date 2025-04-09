const { expect } = require("chai");
const { ethers } = require("hardhat");
const { time } = require("@nomicfoundation/hardhat-network-helpers");

describe("PublicitySpot Contract", function () {
  let publicitySpot;
  let owner, user1, user2;
  const basePrice = ethers.parseUnits("0.5", "ether");
  const annualRate = 500; // 5%

  beforeEach(async () => {
    [owner, user1, user2] = await ethers.getSigners();
    const PublicitySpot = await ethers.getContractFactory("PublicitySpot");
    publicitySpot = await PublicitySpot.deploy(basePrice, annualRate);

    await publicitySpot.waitForDeployment();
  });

  it("should handle a full purchase/replace/refund/withdraw scenario", async () => {
    const user1Price = ethers.parseUnits("2", "ether");

    await publicitySpot.connect(user1).buyPublicitySpot("ipfs://user1.jpg", user1Price, {
      value: basePrice,
    });

    expect(await publicitySpot.currentUser()).to.equal(user1.address);

    const fuelAmount = ethers.parseUnits("0.1", "ether"); // 1 year (2 eth * 0.05)
    await publicitySpot.connect(user1).addFuel({ value: fuelAmount });

    await publicitySpot.connect(user1).updateImage("ipfs://user1-new.jpg");

    await time.increase(time.duration.years(0.5));

    const user2Price = ethers.parseUnits("3", "ether");

    await publicitySpot.connect(user2).buyPublicitySpot("ipfs://user2.jpg", user2Price, {
      value: user1Price,
    });

    expect(await publicitySpot.currentUser()).to.equal(user2.address);

    const fuelAmount2 = ethers.parseUnits("0.001", "ether");
    await publicitySpot.connect(user2).addFuel({ value: fuelAmount2 });
    
    expect(await publicitySpot.getCurrentImage()).to.equal("ipfs://user2.jpg");

    const oldUser1Balance = await ethers.provider.getBalance(user1.address);
    await publicitySpot.connect(user1).claim();
    const user1Balance = await ethers.provider.getBalance(user1.address);

    expect(user1Balance).to.be.closeTo(
        oldUser1Balance + basePrice + ethers.parseUnits("0.05", "ether"),
        ethers.parseUnits("0.0001", "ether")
    ); // oldUser1Balance + purchased price by user1 + 6 months remaining - fees


    /* TO FIX
    const oldOwnerBalance = await ethers.provider.getBalance(owner.address);
    await publicitySpot.connect(owner).withdraw();
    const ownerBalance = await ethers.provider.getBalance(owner.address);

    /*expect(ownerBalance).to.be.closeTo(
        oldOwnerBalance + ethers.parseUnits("0.05", "ether") + user2Price + basePrice - user1Balance,
        ethers.parseUnits("0.0001", "ether")
    ); // oldOwnerBalance + basePrice + 6 months remaining - fees
    */
  });

  it("should block image update after time expires", async () => {
    const user1Price = ethers.parseUnits("2", "ether");

    await publicitySpot.connect(user1).buyPublicitySpot("ipfs://user1.jpg", user1Price, {
      value: basePrice,
    });

    expect(await publicitySpot.currentUser()).to.equal(user1.address);

    const fuelAmount = ethers.parseUnits("0.1", "ether"); // 1 year (2 eth *0.05)
    await publicitySpot.connect(user1).addFuel({ value: fuelAmount });

    await publicitySpot.connect(user1).updateImage("ipfs://user1-new.jpg");
    expect(await publicitySpot.getCurrentImage()).to.equal("ipfs://user1-new.jpg");

    await time.increase(time.duration.years(1) - time.duration.minutes(1));
    expect(await publicitySpot.getRemainingTime()).to.be.greaterThan(0);
    expect(await publicitySpot.getCurrentImage()).to.equal("ipfs://user1-new.jpg");

    await time.increase(time.duration.minutes(1));
    expect(await publicitySpot.getRemainingTime()).to.be.equals(0);
    expect(await publicitySpot.getCurrentImage()).to.equal("");
  });
});
