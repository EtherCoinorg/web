#!/usr/bin/env python3
"""Ethercoin CLI — interact with the Ethercoin network."""

import argparse, sys, os, json, time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from client.node_client import EthercoinNode, NodeType, Task, Batch
from client.p2p_network import P2PNetwork, Message, MessageType


def cmd_status(args):
    print("Ethercoin Node Status (simulated)")
    print("=" * 50)
    for addr, node in NET.nodes.items():
        s = node.get_status()
        print(f"  {addr}")
        for k, v in s.items():
            print(f"    {k}: {v}")


def cmd_create_task(args):
    node = list(NET.nodes.values())[0]
    task = Task(
        id=args.task_id or int(time.time()),
        model_cid=args.model,
        input_cid=args.input,
        expected_eflops=args.eflops,
        verification_mode=args.mode,
        reward=args.reward,
    )
    print(f"Task created: {task.id}")
    print(f"  Model: {task.model_cid}")
    print(f"  EFLOPs: {task.expected_eflops}")
    print(f"  Mode: {task.verification_mode}")
    return task


def cmd_compute(args):
    for addr, node in NET.nodes.items():
        if node.node_type == NodeType.GPU_MINER:
            task = Task(
                id=args.task_id,
                model_cid=args.model,
                input_cid=args.input,
                expected_eflops=args.eflops,
                verification_mode=args.mode,
                reward=args.reward,
            )
            print(f"Computing task {task.id} on node {addr}...")
            proof = node.compute(task)
            print(f"  Output: {proof['output_cid']}")
            print(f"  Anchors: {len(proof['anchor_hashes'])} hashes")
            print(f"  Verified EFLOPs: {proof['computation_eflops']}")
            return proof
    print("No GPU miner nodes registered")


def cmd_verify(args):
    proof = {
        "node": args.node,
        "task_id": args.task_id,
        "output_cid": args.output,
        "anchor_hashes": [f"hash_{i}" for i in range(5)],
        "computation_eflops": args.eflops,
    }
    verifier = None
    for addr, node in NET.nodes.items():
        if node.node_type == NodeType.VERIFIER:
            verifier = node
            break
    if verifier:
        result = verifier.verify(proof)
        print(f"Verification result: {'PASSED' if result else 'FAILED'}")
    else:
        print("No verifier nodes registered")


def cmd_distill(args):
    miner = None
    for addr, node in NET.nodes.items():
        if node.node_type == NodeType.GPU_MINER:
            miner = node
            break
    if not miner:
        print("No miner nodes found")
        return

    proxy_path = args.proxies.split(",") if args.proxies else ["proxy_1", "proxy_2", "proxy_3"]

    sigs = NET.onion_route({"prompt": args.prompt}, proxy_path)
    response, resp_hash = miner.distill(args.prompt, proxy_path)

    print(f"Distillation complete:")
    print(f"  Prompt: {args.prompt[:60]}...")
    print(f"  Response hash: {resp_hash[:16]}...")
    print(f"  Proxy path: {' → '.join(proxy_path)}")
    print(f"  Path signatures: {len(sigs)} hops")


def cmd_incentives(args):
    print("ETHER Token Economics (simulated)")
    print("=" * 50)
    max_supply = 210_000_000_000
    genesis_pct = 10
    mining_pct = 90
    emission_years = 40
    print(f"  Max Supply:     {max_supply:,} ETHER")
    print(f"  Genesis:        {genesis_pct}% ({max_supply * genesis_pct // 100:,} ETHER)")
    print(f"  Mining:         {mining_pct}% ({max_supply * mining_pct // 100:,} ETHER)")
    print(f"  Emission Years: {emission_years}")
    print(f"  Annual Decay:   ~{pow(0.5, 1/emission_years)*100:.1f}% yearly")
    print()
    print("  Reward per EFLOP: 0.000001 ETHER (governed by DAO)")


def cmd_help(args):
    parser.print_help()


def _init_network() -> P2PNetwork:
    net = P2PNetwork()
    for name, (nt, stake) in [
        ("miner_1", (NodeType.GPU_MINER, 1000)),
        ("miner_2", (NodeType.GPU_MINER, 2000)),
        ("proxy_1", (NodeType.PROXY_NODE, 100)),
        ("proxy_2", (NodeType.PROXY_NODE, 100)),
        ("verifier_1", (NodeType.VERIFIER, 500)),
    ]:
        node = EthercoinNode(name, nt, stake)
        net.register_node(name, node)
    return net

NET: P2PNetwork | None = None

parser = argparse.ArgumentParser(description="Ethercoin CLI — decentralized AI compute network")
parser.set_defaults(func=cmd_help)
sub = parser.add_subparsers()

p = sub.add_parser("status", help="Show network status")
p.set_defaults(func=cmd_status)

p = sub.add_parser("create-task", help="Create a compute task")
p.add_argument("--task-id", type=int)
p.add_argument("--model", default="ipfs://llama-7b")
p.add_argument("--input", default="ipfs://input-data")
p.add_argument("--eflops", type=int, default=1500)
p.add_argument("--mode", default="optimistic")
p.add_argument("--reward", type=int, default=100)
p.set_defaults(func=cmd_create_task)

p = sub.add_parser("compute", help="Run computation on a GPU miner node")
p.add_argument("--task-id", type=int, default=1)
p.add_argument("--model", default="ipfs://llama-7b")
p.add_argument("--input", default="ipfs://input-data")
p.add_argument("--eflops", type=int, default=1500)
p.add_argument("--mode", default="optimistic")
p.add_argument("--reward", type=int, default=100)
p.set_defaults(func=cmd_compute)

p = sub.add_parser("verify", help="Verify a computation proof")
p.add_argument("--node", default="miner_1")
p.add_argument("--task-id", type=int, default=1)
p.add_argument("--output", default="ipfs://output-hash")
p.add_argument("--eflops", type=int, default=1500)
p.set_defaults(func=cmd_verify)

p = sub.add_parser("distill", help="Run distillation through proxy network")
p.add_argument("--prompt", default="What is the capital of France?")
p.add_argument("--proxies", default="proxy_1,proxy_2,proxy_3")
p.set_defaults(func=cmd_distill)

p = sub.add_parser("incentives", help="Show token economics parameters")
p.set_defaults(func=cmd_incentives)


def main():
    global NET
    if NET is None:
        NET = _init_network()
    args = parser.parse_args()
    args.func(args)


if __name__ == "__main__":
    main()
