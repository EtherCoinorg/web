"""Ethercoin GPU Node Client — simulates a compute node in the network."""

import json, time, os, hashlib, threading
from dataclasses import dataclass, field
from typing import Optional
from enum import Enum


class NodeType(Enum):
    GPU_MINER = 0
    PROXY_NODE = 1
    VERIFIER = 2


@dataclass
class Task:
    id: int
    model_cid: str
    input_cid: str
    expected_eflops: int
    verification_mode: str  # optimistic, zk, tee
    reward: int
    status: str = "pending"


@dataclass
class Batch:
    task_id: int
    batch_id: int
    data_cid: str = ""
    response_hash: str = ""
    data_point_count: int = 0
    status: str = "assigned"


class EthercoinNode:
    """Simulates an Ethercoin network node (GPU miner, proxy, or verifier)."""

    def __init__(self, address: str, node_type: NodeType, stake: int):
        self.address = address
        self.node_type = node_type
        self.stake = stake
        self.reputation = 100
        self.tasks_completed = 0
        self.active = True
        self._running = False
        self._thread: Optional[threading.Thread] = None

    def compute(self, task: Task) -> dict:
        """Simulate AI inference computation and return work proof."""
        import time as _time
        compute_time = task.expected_eflops / 1000.0
        _time.sleep(min(compute_time * 0.001, 0.5))

        proof = {
            "node": self.address,
            "task_id": task.id,
            "output_cid": f"ipfs://output-{hashlib.sha256(str(task.id).encode()).hexdigest()[:16]}",
            "anchor_hashes": [
                hashlib.sha256(f"layer_{i}_{task.id}".encode()).hexdigest()
                for i in range(5)
            ],
            "computation_eflops": task.expected_eflops,
            "timestamp": time.time(),
        }
        self.tasks_completed += 1
        self.reputation += 1
        return proof

    def verify(self, proof: dict) -> bool:
        """Verify a work proof (simulated)."""
        required = ["node", "task_id", "output_cid", "anchor_hashes", "computation_eflops"]
        return all(k in proof for k in required)

    def distill(self, prompt: str, proxy_path: list[str]) -> tuple[str, str]:
        """Simulate distillation: call a target API through proxy path."""
        response = f"Simulated response for: {prompt[:50]}..."
        response_hash = hashlib.sha256(response.encode()).hexdigest()
        proxy_sigs = "|".join(f"sig_{p}" for p in proxy_path)
        return response, response_hash

    def get_status(self) -> dict:
        return {
            "address": self.address,
            "type": self.node_type.name,
            "stake": self.stake,
            "reputation": self.reputation,
            "tasks_completed": self.tasks_completed,
            "active": self.active,
        }
