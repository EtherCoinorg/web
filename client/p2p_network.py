"""Simulated P2P networking layer for Ethercoin."""

import json, time, hashlib, random
from dataclasses import dataclass, field
from typing import Optional
from enum import Enum


class MessageType(Enum):
    TASK_ANNOUNCE = "task_announce"
    TASK_ASSIGN = "task_assign"
    WORK_SUBMIT = "work_submit"
    CHALLENGE = "challenge"
    DISTILL_BATCH = "distill_batch"
    PROXY_FORWARD = "proxy_forward"
    PING = "ping"
    PONG = "pong"


@dataclass
class Message:
    msg_type: MessageType
    sender: str
    payload: dict
    signature: str = ""
    timestamp: float = field(default_factory=time.time)


class P2PNetwork:
    """Simple in-process P2P network simulation.
    In production, this would use libp2p with noise encryption."""

    def __init__(self):
        self.nodes: dict[str, object] = {}
        self.messages: list[Message] = []
        self.proxy_routes: dict[str, list[str]] = {}

    def register_node(self, address: str, node: object):
        self.nodes[address] = node

    def send(self, msg: Message) -> bool:
        if msg.sender not in self.nodes:
            return False
        msg.signature = self._sign(msg)
        self.messages.append(msg)
        return True

    def broadcast(self, msg: Message) -> int:
        count = 0
        for addr in self.nodes:
            if addr != msg.sender:
                m = Message(msg.msg_type, msg.sender, msg.payload)
                m.signature = self._sign(m)
                self.messages.append(m)
                count += 1
        return count

    def _sign(self, msg: Message) -> str:
        data = f"{msg.msg_type.value}{msg.sender}{json.dumps(msg.payload, sort_keys=True)}{msg.timestamp}"
        return hashlib.sha256(data.encode()).hexdigest()[:16]

    def onion_route(self, payload: dict, path: list[str]) -> list[str]:
        """Simulate onion encryption routing through proxy nodes.
        Returns the path signatures."""
        sigs = []
        for i, hop in enumerate(path):
            layer = json.dumps({
                "hop": i,
                "next": path[i + 1] if i + 1 < len(path) else "destination",
                "payload_hash": hashlib.sha256(json.dumps(payload).encode()).hexdigest()[:8],
            })
            sigs.append(f"{hop}_sig_{hashlib.sha256(layer.encode()).hexdigest()[:12]}")
        return sigs

    def get_messages(self, address: str, msg_type: Optional[MessageType] = None) -> list[Message]:
        msgs = [m for m in self.messages if m.sender != address]
        if msg_type:
            msgs = [m for m in msgs if m.msg_type == msg_type]
        return msgs[-10:]
