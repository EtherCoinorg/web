const { expect } = require("chai");
const { ethers } = require("hardhat");

describe("TaskMarket", function () {
  let token, registry, market, owner, miner, verifier, user;

  beforeEach(async function () {
    [owner, miner, verifier, user] = await ethers.getSigners();
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

    const TaskMarket = await ethers.getContractFactory("TaskMarket");
    market = await TaskMarket.deploy(token.address, registry.address, 7 * 24 * 60 * 60, 5);
    await market.deployed();

    const RESOLVER_ROLE = ethers.utils.keccak256(ethers.utils.toUtf8Bytes("RESOLVER_ROLE"));
    await market.grantRole(RESOLVER_ROLE, owner.address);

    const ADMIN_ROLE = ethers.utils.keccak256(ethers.utils.toUtf8Bytes("ADMIN_ROLE"));
    const RECORDER_ROLE = ethers.utils.keccak256(ethers.utils.toUtf8Bytes("RECORDER_ROLE"));
    await registry.grantRole(ADMIN_ROLE, owner.address);
    await registry.grantRole(ADMIN_ROLE, market.address);
    await registry.grantRole(RECORDER_ROLE, market.address);

    for (const signer of [miner, verifier, user]) {
      await token.transfer(signer.address, ethers.utils.parseEther("10000"));
      await token.connect(signer).approve(registry.address, ethers.utils.parseEther("10000"));
      await token.connect(signer).approve(market.address, ethers.utils.parseEther("10000"));
    }

    await registry.connect(miner).register(0, "ipfs://hwproof", ethers.utils.parseEther("1000"));
    await registry.connect(verifier).register(2, "ipfs://hwproof", ethers.utils.parseEther("500"));
  });

  it("should create a task", async function () {
    await market.connect(user).createTask("ipfs://model", "ipfs://input", 1500, 0, ethers.utils.parseEther("100"));
    const task = await market.getTask(0);
    expect(task.creator).to.equal(user.address);
    expect(task.expectedEFLOPS.toNumber()).to.equal(1500);
    expect(task.reward.eq(ethers.utils.parseEther("100"))).to.be.true;
  });

  it("should complete full task lifecycle", async function () {
    const reward = ethers.utils.parseEther("100");
    await market.connect(user).createTask("ipfs://model", "ipfs://input", 1500, 0, reward);
    await market.connect(owner).assignTask(0, miner.address);
    await market.connect(miner).submitWork(0, "ipfs://proof");

    await ethers.provider.send("evm_increaseTime", [7 * 24 * 60 * 60 + 1]);
    await ethers.provider.send("evm_mine");

    await market.connect(owner).finalizeTask(0);
    const task = await market.getTask(0);
    expect(task.status).to.equal(4);
  });

  it("should handle challenge and resolve honest", async function () {
    await market.connect(user).createTask("ipfs://model", "ipfs://input", 1500, 0, ethers.utils.parseEther("100"));
    await market.connect(owner).assignTask(0, miner.address);
    await market.connect(miner).submitWork(0, "ipfs://proof");
    await market.connect(verifier).challengeTask(0);
    await market.connect(owner).resolveChallenge(0, true);
    expect((await market.getTask(0)).status).to.equal(4);
  });
});
