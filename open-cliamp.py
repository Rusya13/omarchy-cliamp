#!/usr/bin/env python3
"""Focus the terminal pane running cliamp, or launch cliamp if it is absent."""
import json
import os
import subprocess
import sys


def run(*args):
    return subprocess.run(args, capture_output=True, text=True, timeout=3)


def output_json(*args):
    try:
        result = run(*args)
        return json.loads(result.stdout)
    except Exception:
        return {}


def focus_herdr_cliamp():
    panes = output_json("herdr", "pane", "list").get("result", {}).get("panes", [])
    for pane in panes:
        pane_id = pane.get("pane_id")
        if not pane_id:
            continue
        info = output_json("herdr", "pane", "process-info", "--pane", pane_id)
        processes = info.get("result", {}).get("process_info", {}).get("foreground_processes", [])
        if not any((p.get("name") == "cliamp" or p.get("argv", [""])[0] == "cliamp") for p in processes):
            continue
        workspace = pane.get("workspace_id")
        if workspace:
            run("herdr", "workspace", "focus", workspace)
            return True
    return False


def focus_hyprland_cliamp():
    clients = output_json("hyprctl", "clients", "-j")
    if not isinstance(clients, list):
        return False

    cliamp_pids = set()
    try:
        pgrep = run("pgrep", "-x", "cliamp")
        cliamp_pids = {int(line) for line in pgrep.stdout.splitlines() if line.strip().isdigit()}
    except Exception:
        pass

    ancestors = set(cliamp_pids)
    for pid in list(cliamp_pids):
        while pid > 1:
            try:
                parent = int(run("ps", "-o", "ppid=", "-p", str(pid)).stdout.strip())
            except Exception:
                break
            if parent <= 0 or parent in ancestors:
                break
            ancestors.add(parent)
            pid = parent

    for client in clients:
        title = f"{client.get('title', '')} {client.get('initialTitle', '')}".lower()
        try:
            client_pid = int(client.get("pid", -1))
        except (TypeError, ValueError):
            client_pid = -1
        if client_pid in ancestors or "cliamp" in title:
            address = client.get("address")
            if address:
                run("hyprctl", "dispatch", "focuswindow", f"address:{address}")
                return True
    return False


if focus_herdr_cliamp() or focus_hyprland_cliamp():
    sys.exit(0)

# No existing terminal was found: create/focus a dedicated TUI window.
subprocess.Popen([
    "omarchy-launch-or-focus-tui",
    "--app-id=org.omarchy.cliamp",
    "cliamp",
], start_new_session=True)
