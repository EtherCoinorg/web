// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract NodeRegistry is AccessControl {
    using SafeERC20 for IERC20;

    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    bytes32 public constant RECORDER_ROLE = keccak256("RECORDER_ROLE");

    enum NodeType { GPU_MINER, PROXY_NODE, VERIFIER }
    enum NodeStatus { UNREGISTERED, ACTIVE, SLASHED, EXITED }

    struct Node {
        NodeType nodeType;
        NodeStatus status;
        address owner;
        string hardwareProofCID;
        uint256 stakeAmount;
        uint256 reputation;
        uint256 tasksCompleted;
        uint256 tasksVerified;
        uint256 registeredAt;
        uint256 lastActive;
    }

    IERC20 public etherToken;
    uint256 public minStakeGPU;
    uint256 public minStakeProxy;
    uint256 public minStakeVerifier;
    uint256 public minStakingDuration;

    uint256 public totalNodes;
    mapping(address => Node) public nodes;
    mapping(NodeType => address[]) public activeNodesByType;
    mapping(address => uint256) public nodeIndex;

    event NodeRegistered(address indexed node, NodeType nodeType, uint256 stake);
    event NodeStatusChanged(address indexed node, NodeStatus status);
    event StakeIncreased(address indexed node, uint256 additional);
    event StakeWithdrawn(address indexed node, uint256 amount);
    event ReputationUpdated(address indexed node, uint256 newScore);

    constructor(
        address _etherToken,
        uint256 _minStakeGPU,
        uint256 _minStakeProxy,
        uint256 _minStakeVerifier,
        uint256 _minStakingDuration
    ) {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(ADMIN_ROLE, msg.sender);
        etherToken = IERC20(_etherToken);
        minStakeGPU = _minStakeGPU;
        minStakeProxy = _minStakeProxy;
        minStakeVerifier = _minStakeVerifier;
        minStakingDuration = _minStakingDuration;
    }

    function register(NodeType nodeType, string calldata hardwareProofCID, uint256 stakeAmount) external {
        require(nodes[msg.sender].status == NodeStatus.UNREGISTERED, "Already registered");
        uint256 requiredStake = _requiredStake(nodeType);
        require(stakeAmount >= requiredStake, "Insufficient stake");

        etherToken.safeTransferFrom(msg.sender, address(this), stakeAmount);

        nodes[msg.sender] = Node({
            nodeType: nodeType,
            status: NodeStatus.ACTIVE,
            owner: msg.sender,
            hardwareProofCID: hardwareProofCID,
            stakeAmount: stakeAmount,
            reputation: 100,
            tasksCompleted: 0,
            tasksVerified: 0,
            registeredAt: block.timestamp,
            lastActive: block.timestamp
        });
        nodeIndex[msg.sender] = activeNodesByType[nodeType].length;
        activeNodesByType[nodeType].push(msg.sender);
        totalNodes++;

        emit NodeRegistered(msg.sender, nodeType, stakeAmount);
    }

    function increaseStake(uint256 additional) external {
        Node storage n = nodes[msg.sender];
        require(n.status == NodeStatus.ACTIVE, "Not active");
        etherToken.safeTransferFrom(msg.sender, address(this), additional);
        n.stakeAmount += additional;
        emit StakeIncreased(msg.sender, additional);
    }

    function requestExit() external {
        Node storage n = nodes[msg.sender];
        require(n.status == NodeStatus.ACTIVE, "Not active");
        require(block.timestamp >= n.registeredAt + minStakingDuration, "Staking period not met");
        n.status = NodeStatus.EXITED;
        _removeFromActiveList(msg.sender, n.nodeType);
        etherToken.safeTransfer(msg.sender, n.stakeAmount);
        n.stakeAmount = 0;
        emit NodeStatusChanged(msg.sender, NodeStatus.EXITED);
    }

    function slash(address nodeAddress, uint256 penaltyPct) external onlyRole(ADMIN_ROLE) {
        Node storage n = nodes[nodeAddress];
        require(n.status == NodeStatus.ACTIVE, "Not active");
        uint256 penalty = n.stakeAmount * penaltyPct / 100;
        n.stakeAmount -= penalty;
        etherToken.safeTransfer(address(0xdead), penalty);
        if (n.stakeAmount < _requiredStake(n.nodeType)) {
            n.status = NodeStatus.SLASHED;
            _removeFromActiveList(nodeAddress, n.nodeType);
            emit NodeStatusChanged(nodeAddress, NodeStatus.SLASHED);
        }
    }

    function updateReputation(address nodeAddress, uint256 newScore) external onlyRole(ADMIN_ROLE) {
        Node storage n = nodes[nodeAddress];
        require(n.status == NodeStatus.ACTIVE, "Not active");
        n.reputation = newScore;
        emit ReputationUpdated(nodeAddress, newScore);
    }

    function recordTask(address nodeAddress) external onlyRole(RECORDER_ROLE) {
        Node storage n = nodes[nodeAddress];
        if (n.status == NodeStatus.ACTIVE) {
            n.tasksCompleted++;
            n.lastActive = block.timestamp;
        }
    }

    function getNodeStatus(address nodeAddress) external view returns (NodeStatus) {
        return nodes[nodeAddress].status;
    }

    function getNodeType(address nodeAddress) external view returns (NodeType) {
        return nodes[nodeAddress].nodeType;
    }

    function getActiveNodes(NodeType nodeType) external view returns (address[] memory) {
        return activeNodesByType[nodeType];
    }

    function _requiredStake(NodeType nodeType) internal view returns (uint256) {
        if (nodeType == NodeType.GPU_MINER) return minStakeGPU;
        if (nodeType == NodeType.PROXY_NODE) return minStakeProxy;
        if (nodeType == NodeType.VERIFIER) return minStakeVerifier;
        return type(uint256).max;
    }

    function _removeFromActiveList(address node, NodeType nodeType) internal {
        address[] storage list = activeNodesByType[nodeType];
        uint256 idx = nodeIndex[node];
        uint256 last = list.length - 1;
        if (idx != last) {
            address lastAddr = list[last];
            list[idx] = lastAddr;
            nodeIndex[lastAddr] = idx;
        }
        list.pop();
        delete nodeIndex[node];
    }
}
