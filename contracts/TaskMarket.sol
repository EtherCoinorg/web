// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "./NodeRegistry.sol";

contract TaskMarket is AccessControl {
    using SafeERC20 for IERC20;

    bytes32 public constant RESOLVER_ROLE = keccak256("RESOLVER_ROLE");

    enum TaskStatus { PENDING, ASSIGNED, COMPLETED, CHALLENGED, FINALIZED, DISPUTED }
    enum VerificationMode { OPTIMISTIC, ZK, TEE }

    struct Task {
        uint256 id;
        address creator;
        string modelCID;
        string inputCID;
        uint256 expectedEFLOPS;
        VerificationMode verificationMode;
        uint256 reward;
        uint256 challengeStake;
        TaskStatus status;
        address assignedNode;
        string workProofCID;
        uint256 createdAt;
        uint256 challengeDeadline;
        uint256 finalizedAt;
    }

    IERC20 public etherToken;
    NodeRegistry public nodeRegistry;
    uint256 public nextTaskId;
    uint256 public challengePeriod;
    uint256 public verifierFeeRatio;

    mapping(uint256 => Task) public tasks;
    uint256 public totalTasksCompleted;
    uint256 public totalEFLOPSVerified;

    event TaskCreated(uint256 indexed taskId, address indexed creator, string modelCID, uint256 reward);
    event TaskAssigned(uint256 indexed taskId, address indexed node);
    event TaskCompleted(uint256 indexed taskId, address indexed node, string workProofCID);
    event TaskChallenged(uint256 indexed taskId, address indexed challenger);
    event TaskFinalized(uint256 indexed taskId, bool verified);
    event TaskDisputed(uint256 indexed taskId, address indexed challenger);

    constructor(address _etherToken, address _nodeRegistry, uint256 _challengePeriod, uint256 _verifierFeeRatio) {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(RESOLVER_ROLE, msg.sender);
        etherToken = IERC20(_etherToken);
        nodeRegistry = NodeRegistry(_nodeRegistry);
        challengePeriod = _challengePeriod;
        verifierFeeRatio = _verifierFeeRatio;
    }

    function createTask(
        string calldata modelCID,
        string calldata inputCID,
        uint256 expectedEFLOPS,
        VerificationMode verificationMode,
        uint256 reward
    ) external returns (uint256) {
        require(reward > 0, "Reward must be positive");
        uint256 challengeStake = reward * 10 / 100;

        etherToken.safeTransferFrom(msg.sender, address(this), reward + challengeStake);

        uint256 taskId = nextTaskId++;
        tasks[taskId] = Task({
            id: taskId,
            creator: msg.sender,
            modelCID: modelCID,
            inputCID: inputCID,
            expectedEFLOPS: expectedEFLOPS,
            verificationMode: verificationMode,
            reward: reward,
            challengeStake: challengeStake,
            status: TaskStatus.PENDING,
            assignedNode: address(0),
            workProofCID: "",
            createdAt: block.timestamp,
            challengeDeadline: 0,
            finalizedAt: 0
        });

        emit TaskCreated(taskId, msg.sender, modelCID, reward);
        return taskId;
    }

    function assignTask(uint256 taskId, address node) external onlyRole(RESOLVER_ROLE) {
        Task storage t = tasks[taskId];
        require(t.status == TaskStatus.PENDING, "Not pending");
        require(nodeRegistry.getNodeStatus(node) == NodeRegistry.NodeStatus.ACTIVE, "Node not active");

        t.status = TaskStatus.ASSIGNED;
        t.assignedNode = node;
        t.challengeDeadline = block.timestamp + challengePeriod;

        emit TaskAssigned(taskId, node);
    }

    function submitWork(uint256 taskId, string calldata workProofCID) external {
        Task storage t = tasks[taskId];
        require(t.status == TaskStatus.ASSIGNED, "Not assigned");
        require(msg.sender == t.assignedNode, "Not assigned node");

        t.status = TaskStatus.COMPLETED;
        t.workProofCID = workProofCID;

        emit TaskCompleted(taskId, msg.sender, workProofCID);
    }

    function finalizeTask(uint256 taskId) external {
        Task storage t = tasks[taskId];
        require(t.status == TaskStatus.COMPLETED, "Not completed");
        require(block.timestamp >= t.challengeDeadline, "Challenge period not ended");

        t.status = TaskStatus.FINALIZED;
        t.finalizedAt = block.timestamp;

        uint256 nodeReward = t.reward * (100 - verifierFeeRatio) / 100;

        etherToken.safeTransfer(t.assignedNode, nodeReward);
        etherToken.safeTransfer(t.creator, t.challengeStake);

        nodeRegistry.recordTask(t.assignedNode);

        totalTasksCompleted++;
        totalEFLOPSVerified += t.expectedEFLOPS;

        emit TaskFinalized(taskId, true);
    }

    function challengeTask(uint256 taskId) external {
        Task storage t = tasks[taskId];
        require(t.status == TaskStatus.COMPLETED, "Not completed");
        require(block.timestamp < t.challengeDeadline, "Challenge period ended");
        require(nodeRegistry.getNodeStatus(msg.sender) == NodeRegistry.NodeStatus.ACTIVE, "Only active verifiers");

        t.status = TaskStatus.CHALLENGED;
        emit TaskChallenged(taskId, msg.sender);
    }

    function resolveChallenge(uint256 taskId, bool nodeHonest) external onlyRole(RESOLVER_ROLE) {
        Task storage t = tasks[taskId];
        require(t.status == TaskStatus.CHALLENGED, "Not challenged");

        t.status = TaskStatus.FINALIZED;
        t.finalizedAt = block.timestamp;

        if (nodeHonest) {
            uint256 nodeReward = t.reward * (100 - verifierFeeRatio) / 100;
            etherToken.safeTransfer(t.assignedNode, nodeReward);
            etherToken.safeTransfer(t.creator, t.challengeStake);
            totalTasksCompleted++;
            totalEFLOPSVerified += t.expectedEFLOPS;
        } else {
            uint256 slashPct = 50;
            uint256 available = t.reward + t.challengeStake;
            etherToken.safeTransfer(t.creator, available);
            nodeRegistry.slash(t.assignedNode, slashPct);
        }
        emit TaskFinalized(taskId, nodeHonest);
    }

    function getTask(uint256 taskId) external view returns (Task memory) {
        return tasks[taskId];
    }
}
