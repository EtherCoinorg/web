// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "./NodeRegistry.sol";

contract DistillationMarket is AccessControl {
    using SafeERC20 for IERC20;

    bytes32 public constant RESOLVER_ROLE = keccak256("RESOLVER_ROLE");

    enum BatchStatus { PENDING, ASSIGNED, SUBMITTED, VERIFIED, REJECTED, FINALIZED }

    struct DistillTask {
        uint256 id;
        address creator;
        string targetModel;
        uint256 totalReward;
        uint256 paidOut;
        string promptTreeRoot;
        uint256 createdAt;
        bool active;
    }

    struct Batch {
        uint256 taskId;
        uint256 batchId;
        address miner;
        string dataCID;
        bytes32 responseHash;
        bytes proxyPathSigs;
        uint256 dataPointCount;
        BatchStatus status;
        uint256 verifiedCount;
        uint256 stakedAmount;
    }

    IERC20 public etherToken;
    NodeRegistry public nodeRegistry;
    uint256 public nextTaskId;
    uint256 public nextBatchId;
    uint256 public minStakeDistill;
    uint256 public similarityThreshold;
    uint256 public rewardPerPoint;

    mapping(uint256 => DistillTask) public distillTasks;
    mapping(uint256 => Batch) public batches;
    mapping(uint256 => uint256[]) public taskBatches;

    event DistillTaskCreated(uint256 indexed taskId, string targetModel, uint256 totalReward);
    event BatchClaimed(uint256 indexed taskId, uint256 indexed batchId, address indexed miner);
    event BatchSubmitted(uint256 indexed taskId, uint256 indexed batchId, string dataCID);
    event BatchVerified(uint256 indexed taskId, uint256 indexed batchId, uint256 verifiedCount);
    event BatchFinalized(uint256 indexed taskId, uint256 indexed batchId, uint256 reward);

    constructor(
        address _etherToken,
        address _nodeRegistry,
        uint256 _minStakeDistill,
        uint256 _similarityThreshold,
        uint256 _rewardPerPoint
    ) {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(RESOLVER_ROLE, msg.sender);
        etherToken = IERC20(_etherToken);
        nodeRegistry = NodeRegistry(_nodeRegistry);
        minStakeDistill = _minStakeDistill;
        similarityThreshold = _similarityThreshold;
        rewardPerPoint = _rewardPerPoint;
    }

    function createTask(
        string calldata targetModel,
        uint256 totalReward,
        string calldata promptTreeRoot
    ) external returns (uint256) {
        require(totalReward > 0, "Reward must be positive");

        etherToken.safeTransferFrom(msg.sender, address(this), totalReward);

        uint256 taskId = nextTaskId++;
        distillTasks[taskId] = DistillTask({
            id: taskId,
            creator: msg.sender,
            targetModel: targetModel,
            totalReward: totalReward,
            paidOut: 0,
            promptTreeRoot: promptTreeRoot,
            createdAt: block.timestamp,
            active: true
        });

        emit DistillTaskCreated(taskId, targetModel, totalReward);
        return taskId;
    }

    function claimBatch(uint256 taskId) external returns (uint256) {
        DistillTask storage dt = distillTasks[taskId];
        require(dt.active, "Task not active");
        require(dt.paidOut < dt.totalReward, "No remaining reward");
        require(
            nodeRegistry.getNodeStatus(msg.sender) == NodeRegistry.NodeStatus.ACTIVE,
            "Not an active node"
        );

        etherToken.safeTransferFrom(msg.sender, address(this), minStakeDistill);

        uint256 batchId = nextBatchId++;
        batches[batchId] = Batch({
            taskId: taskId,
            batchId: batchId,
            miner: msg.sender,
            dataCID: "",
            responseHash: bytes32(0),
            proxyPathSigs: "",
            dataPointCount: 0,
            status: BatchStatus.ASSIGNED,
            verifiedCount: 0,
            stakedAmount: minStakeDistill
        });
        taskBatches[taskId].push(batchId);

        emit BatchClaimed(taskId, batchId, msg.sender);
        return batchId;
    }

    function submitBatch(
        uint256 batchId,
        string calldata dataCID,
        bytes32 responseHash,
        bytes calldata proxyPathSigs,
        uint256 dataPointCount
    ) external {
        Batch storage b = batches[batchId];
        require(b.status == BatchStatus.ASSIGNED, "Not assigned");
        require(msg.sender == b.miner, "Not the claimer");

        b.dataCID = dataCID;
        b.responseHash = responseHash;
        b.proxyPathSigs = proxyPathSigs;
        b.dataPointCount = dataPointCount;
        b.status = BatchStatus.SUBMITTED;

        emit BatchSubmitted(b.taskId, batchId, dataCID);
    }

    function verifyBatch(uint256 batchId, uint256 verifiedCount) external onlyRole(RESOLVER_ROLE) {
        Batch storage b = batches[batchId];
        require(b.status == BatchStatus.SUBMITTED, "Not submitted");

        if (verifiedCount >= b.dataPointCount * similarityThreshold / 100) {
            b.status = BatchStatus.VERIFIED;
            b.verifiedCount = verifiedCount;
        } else {
            b.status = BatchStatus.REJECTED;
        }

        emit BatchVerified(b.taskId, batchId, verifiedCount);
    }

    function finalizeBatch(uint256 batchId) external {
        Batch storage b = batches[batchId];
        require(b.status == BatchStatus.VERIFIED || b.status == BatchStatus.REJECTED, "Not ready");

        BatchStatus finalStatus = b.status;
        b.status = BatchStatus.FINALIZED;

        DistillTask storage dt = distillTasks[b.taskId];

        if (finalStatus == BatchStatus.VERIFIED) {
            uint256 reward = b.verifiedCount * rewardPerPoint;
            uint256 remaining = dt.totalReward - dt.paidOut;
            if (reward > remaining) reward = remaining;
            dt.paidOut += reward;
            if (dt.paidOut >= dt.totalReward) dt.active = false;
            etherToken.safeTransfer(b.miner, reward);
            etherToken.safeTransfer(b.miner, b.stakedAmount);
        } else {
            etherToken.safeTransfer(address(0xdead), b.stakedAmount);
        }

        emit BatchFinalized(b.taskId, batchId, b.verifiedCount * rewardPerPoint);
    }

    function getTaskBatches(uint256 taskId) external view returns (uint256[] memory) {
        return taskBatches[taskId];
    }

    function getBatch(uint256 batchId) external view returns (Batch memory) {
        return batches[batchId];
    }
}
