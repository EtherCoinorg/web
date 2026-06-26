import pytest
import sys, os
sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))

from client.node_client import EthercoinNode, NodeType, Task, Batch
from client.p2p_network import P2PNetwork, Message, MessageType


class TestNodeClient:
    def test_gpu_miner_creation(self):
        node = EthercoinNode("test_miner", NodeType.GPU_MINER, 1000)
        assert node.address == "test_miner"
        assert node.node_type == NodeType.GPU_MINER
        assert node.stake == 1000
        assert node.reputation == 100
        assert node.active == True

    def test_compute_proof(self):
        node = EthercoinNode("miner_1", NodeType.GPU_MINER, 1000)
        task = Task(id=1, model_cid="ipfs://model", input_cid="ipfs://input",
                    expected_eflops=1500, verification_mode="optimistic", reward=100)
        proof = node.compute(task)
        assert proof["task_id"] == 1
        assert proof["computation_eflops"] == 1500
        assert len(proof["anchor_hashes"]) == 5
        assert node.tasks_completed == 1

    def test_verify_honest_proof(self):
        verifier = EthercoinNode("verifier_1", NodeType.VERIFIER, 500)
        proof = {
            "node": "miner_1", "task_id": 1, "output_cid": "ipfs://out",
            "anchor_hashes": ["a", "b", "c", "d", "e"], "computation_eflops": 1500,
        }
        assert verifier.verify(proof) == True

    def test_verify_tampered_proof(self):
        verifier = EthercoinNode("verifier_1", NodeType.VERIFIER, 500)
        proof = {"node": "miner_1", "task_id": 1}
        assert verifier.verify(proof) == False

    def test_distillation(self):
        node = EthercoinNode("miner_1", NodeType.GPU_MINER, 1000)
        response, resp_hash = node.distill("What is AI?", ["proxy_1", "proxy_2"])
        assert len(resp_hash) == 64
        assert "What is AI?" in response

    def test_node_status(self):
        node = EthercoinNode("n1", NodeType.GPU_MINER, 1000)
        s = node.get_status()
        assert s["address"] == "n1"
        assert s["type"] == "GPU_MINER"
        assert s["tasks_completed"] == 0


class TestP2PNetwork:
    def test_register_and_send(self):
        net = P2PNetwork()
        node = EthercoinNode("n1", NodeType.GPU_MINER, 1000)
        net.register_node("n1", node)
        msg = Message(MessageType.PING, "n1", {"data": "hello"})
        assert net.send(msg) == True

    def test_broadcast(self):
        net = P2PNetwork()
        for name in ["n1", "n2", "n3"]:
            net.register_node(name, EthercoinNode(name, NodeType.GPU_MINER, 1000))
        msg = Message(MessageType.TASK_ANNOUNCE, "n1", {"task_id": 1})
        count = net.broadcast(msg)
        assert count == 2

    def test_onion_routing(self):
        net = P2PNetwork()
        sigs = net.onion_route({"prompt": "test"}, ["a", "b", "c"])
        assert len(sigs) == 3
        assert all(s.startswith(("a_", "b_", "c_")) for s in sigs)

    def test_get_messages(self):
        net = P2PNetwork()
        for name in ["n1", "n2"]:
            net.register_node(name, EthercoinNode(name, NodeType.GPU_MINER, 1000))
        msg = Message(MessageType.TASK_ANNOUNCE, "n1", {"id": 1})
        net.broadcast(msg)
        msgs = net.get_messages("n2", MessageType.TASK_ANNOUNCE)
        assert len(msgs) >= 1
