const { expect } = require("chai");
const { ethers } = require("hardhat");

describe("DistillationMarket", function () {
  let token, registry, distill, owner, miner;

  beforeEach(async function () {
    [owner, miner] = await ethers.getSigners();
    const EtherToken = await ethers.getContractFactory("EtherToken");
    token = await EtherToken.deploy(owner.address, 365 * 24 * 60 * 60);
    await token.deployed();

    const NodeRegistry = await ethers.getContractFactory("NodeRegistry");
    registry = await NodeRegistry.deploy(
      token.address,
      ethers.utils.parseEther("1000"),
      ethers.utils.parseEther("100"),
      ethers.utils.parseEther("500"),
      0
    );
    await registry.deployed();

    const DistillationMarket = await ethers.getContractFactory("DistillationMarket");
    distill = await DistillationMarket.deploy(
      token.address,
      registry.address,
      ethers.utils.parseEther("100"),
      92,
      ethers.utils.parseEther("0.01")
    );
    await distill.deployed();

    // Fund miner and approve both registry and distill
    await token.transfer(miner.address, ethers.utils.parseEther("10000"));
    await token.connect(miner).approve(registry.address, ethers.utils.parseEther("10000"));
    await token.connect(miner).approve(distill.address, ethers.utils.parseEther("10000"));

    // Fund owner and approve distill for task creation
    await token.approve(distill.address, ethers.utils.parseEther("10000"));

    await registry.connect(miner).register(1, "ipfs://proxy", ethers.utils.parseEther("1000"));

    const ADMIN_ROLE = ethers.utils.keccak256(ethers.utils.toUtf8Bytes("ADMIN_ROLE"));
    await registry.grantRole(ADMIN_ROLE, owner.address);
    const RESOLVER_ROLE = ethers.utils.keccak256(ethers.utils.toUtf8Bytes("RESOLVER_ROLE"));
    await distill.grantRole(RESOLVER_ROLE, owner.address);
  });

  it("should create a distillation task", async function () {
    await distill.connect(owner).createTask("gpt-4", ethers.utils.parseEther("1000"), "ipfs://prompt-tree");
    const task = await distill.distillTasks(0);
    expect(task.targetModel).to.equal("gpt-4");
    expect(task.active).to.equal(true);
  });

  it("should complete full batch lifecycle", async function () {
    await distill.connect(owner).createTask("gpt-4", ethers.utils.parseEther("1000"), "ipfs://prompt-tree");
    await distill.connect(miner).claimBatch(0);
    const mockData = "ipfs://distilled-data";
    const mockHash = ethers.utils.keccak256(ethers.utils.toUtf8Bytes("mock-response"));
    await distill.connect(miner).submitBatch(0, mockData, mockHash, "0x", 100);
    await distill.connect(owner).verifyBatch(0, 95);
    await distill.connect(miner).finalizeBatch(0);
    const batch = await distill.getBatch(0);
    expect(batch.status).to.equal(5);
  });

  it("should reject low-quality batches", async function () {
    await distill.connect(owner).createTask("gpt-4", ethers.utils.parseEther("1000"), "ipfs://prompt-tree");
    await distill.connect(miner).claimBatch(0);
    await distill.connect(miner).submitBatch(0, "ipfs://bad-data", ethers.constants.HashZero, "0x", 100);
    await distill.connect(owner).verifyBatch(0, 50);
    await distill.connect(miner).finalizeBatch(0);
    const batch = await distill.getBatch(0);
    expect(batch.status).to.equal(5);
  });
});
