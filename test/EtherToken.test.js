const { expect } = require("chai");
const { ethers } = require("hardhat");

describe("EtherToken", function () {
  let token, owner, addr1;

  beforeEach(async function () {
    [owner, addr1] = await ethers.getSigners();
    const EtherToken = await ethers.getContractFactory("EtherToken");
    token = await EtherToken.deploy(owner.address, 365 * 24 * 60 * 60);
    await token.deployed();
  });

  it("should have correct name and symbol", async function () {
    expect(await token.name()).to.equal("Ethercoin");
    expect(await token.symbol()).to.equal("ETHER");
  });

  it("should mint genesis allocation", async function () {
    const genesisAlloc = ethers.utils.parseEther("21000000000");
    const balance = await token.balanceOf(owner.address);
    expect(balance.eq(genesisAlloc)).to.be.true;
  });

  it("should enforce max supply", async function () {
    // Genesis = 21B. Max supply = 210B. So we can mint 210B - 21B = 189B more.
    const canMint = ethers.utils.parseEther("189000000000");
    await token.mint(owner.address, canMint);
    // Now at max supply — any more should revert
    let reverted = false;
    try {
      await token.mint(owner.address, 1);
    } catch {
      reverted = true;
    }
    expect(reverted).to.be.true;
  });

  it("should allow minting with role", async function () {
    await token.mint(addr1.address, 1000);
    const bal = await token.balanceOf(addr1.address);
    expect(bal.toNumber()).to.equal(1000);
  });
});
