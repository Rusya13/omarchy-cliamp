#!/usr/bin/env python3
"""Focus the terminal pane running cliamp, or launch cliamp if it is absent."""
import json
import os
import subprocess
import sys


def run(*args):
    if args and args[0] == "herdr":
        # Quickshell is not itself inside the Pi pane, so make the target
        # Herdr session explicit instead of falling back to a new terminal.
        args = ("herdr", "--session", "pi-agent", *args[1:])
    return subprocess.run(args, capture_output=True, text=True, timeout=3,
                          env={**os.environ, "HERDR_ENV": "1"})


def output_json(*args):
    try:
        result = run(*args)
        return json.loads(result.stdout)
    except Exception:
        return {}


def herdr_panes():
    return output_json("herdr", "pane", "list").get("result", {}).get("panes", [])


def pi_pane(panes):
    return next((pane for pane in panes if pane.get("agent") == "pi"), None)


def is_cliamp_pane(pane_id):
    info = output_json("herdr", "pane", "process-info", "--pane", pane_id)
    processes = info.get("result", {}).get("process_info", {}).get("foreground_processes", [])
    return any((p.get("name") == "cliamp" or p.get("argv", [""])[0] == "cliamp") for p in processes)


def focus_herdr_cliamp():
    panes = herdr_panes()
    target = next((p for p in panes if p.get("pane_id") and is_cliamp_pane(p["pane_id"])), None)
    if not target:
        return False

    workspace = target.get("workspace_id")
    pi = pi_pane(panes)
    if not workspace:
        return False
    if pi and target.get("tab_id") != pi.get("tab_id"):
        # Keep the running process, but put its pane beside Pi in the same
        # Herdr tab, rather than creating another terminal window.
        run("herdr", "pane", "move", target["pane_id"], "--tab", pi["tab_id"],
            "--split", "right", "--target-pane", pi["pane_id"], "--focus")
    else:
        # Focus the cliamp sibling, not merely the already-focused workspace.
        run("herdr", "workspace", "focus", workspace)
        if pi:
            run("herdr", "pane", "focus", "--pane", pi["pane_id"],
                "--direction", "right")
    return True


def open_in_pi_herdr():
    panes = herdr_panes()
    pi = pi_pane(panes)
    if not pi:
        return False

    created = run("herdr", "pane", "split", "--pane", pi["pane_id"],
                  "--direction", "right", "--cwd", pi.get("cwd", os.path.expanduser("~")),
                  "--focus")
    if created.returncode != 0:
        return False
    try:
        response = json.loads(created.stdout)
        pane_id = response["result"]["pane"]["pane_id"]
    except (ValueError, KeyError, TypeError):
        return False
    run("herdr", "pane", "run", pane_id, "cliamp")
    return True


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


if focus_herdr_cliamp() or focus_hyprland_cliamp() or open_in_pi_herdr():
    sys.exit(0)

# No Herdr or existing terminal was found: create/focus a dedicated TUI window.
subprocess.Popen([
    "omarchy-launch-or-focus-tui",
    "--app-id=org.omarchy.cliamp",
    "cliamp",
], start_new_session=True)
