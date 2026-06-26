const { expect } = require("chai");
const { ethers } = require("hardhat");

describe("NodeRegistry", function () {
  let token, registry, owner, node1;

  beforeEach(async function () {
    [owner, node1] = await ethers.getSigners();
    const EtherToken = await ethers.getContractFactory("EtherToken");
    token = await EtherToken.deploy(owner.address, 365 * 24 * 60 * 60);
    await token.deployed();

    const NodeRegistry = await ethers.getContractFactory("NodeRegistry");
    registry = await NodeRegistry.deploy(
      token.address,
      ethers.utils.parseEther("1000"),
      ethers.utils.parseEther("100"),
      ethers.utils.parseEther("500"),
      0 // no min staking duration for tests
    );
    await registry.deployed();

    await token.transfer(node1.address, ethers.utils.parseEther("5000"));
    await token.connect(node1).approve(registry.address, ethers.utils.parseEther("5000"));
  });

  it("should register a GPU miner", async function () {
    await registry.connect(node1).register(0, "ipfs://hwproof", ethers.utils.parseEther("1000"));
    const node = await registry.nodes(node1.address);
    expect(node.status).to.equal(1);
    expect(node.nodeType).to.equal(0);
    expect(node.stakeAmount.eq(ethers.utils.parseEther("1000"))).to.be.true;
    expect(node.reputation.toNumber()).to.equal(100);
  });

  it("should reject insufficient stake", async function () {
    try {
      await registry.connect(node1).register(0, "ipfs://hwproof", ethers.utils.parseEther("100"));
      expect.fail("Should have reverted");
    } catch (e) {
      expect(e.message).to.include("Insufficient stake");
    }
  });

  it("should allow exit and refund", async function () {
    await registry.connect(node1).register(0, "ipfs://hwproof", ethers.utils.parseEther("1000"));
    await registry.connect(node1).requestExit();
    const node = await registry.nodes(node1.address);
    expect(node.status).to.equal(3);
    const bal = await token.balanceOf(node1.address);
    expect(bal.eq(ethers.utils.parseEther("5000"))).to.be.true;
  });

  it("should record tasks and update reputation", async function () {
    await registry.connect(node1).register(0, "ipfs://hwproof", ethers.utils.parseEther("1000"));
    const RECORDER_ROLE = ethers.utils.keccak256(ethers.utils.toUtf8Bytes("RECORDER_ROLE"));
    await registry.grantRole(RECORDER_ROLE, owner.address);
    await registry.recordTask(node1.address);
    const node = await registry.nodes(node1.address);
    expect(node.tasksCompleted.toNumber()).to.equal(1);
  });

  it("should slash a node", async function () {
    await registry.connect(node1).register(0, "ipfs://hwproof", ethers.utils.parseEther("1000"));
    const ADMIN_ROLE = ethers.utils.keccak256(ethers.utils.toUtf8Bytes("ADMIN_ROLE"));
    await registry.grantRole(ADMIN_ROLE, owner.address);
    await registry.slash(node1.address, 30);
    const node = await registry.nodes(node1.address);
    expect(node.stakeAmount.eq(ethers.utils.parseEther("700"))).to.be.true;
  });
});
