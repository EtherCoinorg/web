const hre = require("hardhat");

async function main() {
  const [deployer] = await hre.ethers.getSigners();
  console.log("Deploying with account:", deployer.address);

  // Deploy EtherToken
  const genesisDuration = 365 * 24 * 60 * 60; // 1 year
  const EtherToken = await hre.ethers.getContractFactory("EtherToken");
  const token = await EtherToken.deploy(deployer.address, genesisDuration);
  await token.waitForDeployment();
  console.log("EtherToken deployed:", await token.getAddress());

  // Deploy NodeRegistry
  const minStakeGPU = hre.ethers.parseEther("1000");
  const minStakeProxy = hre.ethers.parseEther("100");
  const minStakeVerifier = hre.ethers.parseEther("500");
  const NodeRegistry = await hre.ethers.getContractFactory("NodeRegistry");
  const registry = await NodeRegistry.deploy(
    await token.getAddress(),
    minStakeGPU,
    minStakeProxy,
    minStakeVerifier
  );
  await registry.waitForDeployment();
  console.log("NodeRegistry deployed:", await registry.getAddress());

  // Deploy TaskMarket
  const challengePeriod = 7 * 24 * 60 * 60; // 7 days
  const verifierFeeRatio = 5; // 5%
  const TaskMarket = await hre.ethers.getContractFactory("TaskMarket");
  const market = await TaskMarket.deploy(
    await token.getAddress(),
    await registry.getAddress(),
    challengePeriod,
    verifierFeeRatio
  );
  await market.waitForDeployment();
  console.log("TaskMarket deployed:", await market.getAddress());

  // Grant roles
  const RESOLVER_ROLE = hre.ethers.keccak256(hre.ethers.toUtf8Bytes("RESOLVER_ROLE"));
  const MINTER_ROLE = hre.ethers.keccak256(hre.ethers.toUtf8Bytes("MINTER_ROLE"));
  const ADMIN_ROLE = hre.ethers.keccak256(hre.ethers.toUtf8Bytes("ADMIN_ROLE"));

  await token.grantRole(MINTER_ROLE, await market.getAddress());
  await registry.grantRole(ADMIN_ROLE, await market.getAddress());
  console.log("Roles granted");

  // Deploy DistillationMarket
  const minStakeDistill = hre.ethers.parseEther("100");
  const similarityThreshold = 92; // 0.92 * 100
  const rewardPerPoint = hre.ethers.parseEther("0.01");
  const DistillationMarket = await hre.ethers.getContractFactory("DistillationMarket");
  const distill = await DistillationMarket.deploy(
    await token.getAddress(),
    await registry.getAddress(),
    minStakeDistill,
    similarityThreshold,
    rewardPerPoint
  );
  await distill.waitForDeployment();
  console.log("DistillationMarket deployed:", await distill.getAddress());

  console.log("\nDeployment complete!");
  console.log("Token:", await token.getAddress());
  console.log("Registry:", await registry.getAddress());
  console.log("TaskMarket:", await market.getAddress());
  console.log("DistillationMarket:", await distill.getAddress());
}

main().catch(console.error);
