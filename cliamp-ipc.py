#!/usr/bin/env python3
import json
import os
import socket
import sys
from pathlib import Path


def request(payload):
    config_home = os.environ.get("XDG_CONFIG_HOME")
    base = Path(config_home) if config_home else Path.home() / ".config"
    sock_path = base / "cliamp" / "cliamp.sock"
    with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as sock:
        sock.settimeout(3)
        sock.connect(str(sock_path))
        sock.sendall((json.dumps(payload) + "\n").encode())
        data = b""
        while not data.endswith(b"\n"):
            chunk = sock.recv(65536)
            if not chunk:
                break
            data += chunk
    return json.loads(data.decode() or "{}")


try:
    action = sys.argv[1] if len(sys.argv) > 1 else "queue"
    if action == "queue":
        payload = {"cmd": "queue.list"}
    elif action == "play" and len(sys.argv) > 2:
        payload = {"cmd": "queue.play", "index": int(sys.argv[2])}
    else:
        raise ValueError("invalid cliamp IPC request")
    print(json.dumps(request(payload), ensure_ascii=False))
except Exception as exc:
    print(json.dumps({"ok": False, "error": str(exc)}))
    sys.exit(1)
