#!/usr/bin/env python3
"""Focus the terminal pane running cliamp, or launch cliamp if it is absent."""
import json
import os
import subprocess
import sys
import time


def run(*args):
    return subprocess.run(args, capture_output=True, text=True, timeout=3)


def output_json(*args):
    try:
        result = run(*args)
        return json.loads(result.stdout)
    except Exception:
        return {}


def herdr_panes():
    return output_json("herdr", "pane", "list").get("result", {}).get("panes", [])


def pi_workspace(panes):
    for pane in panes:
        if pane.get("agent") == "pi":
            return pane.get("workspace_id")
    return None


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
    pi_ws = pi_workspace(panes)
    if not workspace:
        return False
    if pi_ws and workspace != pi_ws:
        # Keep the running process, but put its pane in the Pi/Herdr window.
        run("herdr", "pane", "move", target["pane_id"], "--workspace", pi_ws,
            "--new-tab", "--label", "cliamp", "--focus")
    else:
        run("herdr", "workspace", "focus", workspace)
    return True


def open_in_pi_herdr():
    panes = herdr_panes()
    workspace = pi_workspace(panes)
    if not workspace:
        return False

    before = {
        tab.get("tab_id")
        for tab in output_json("herdr", "tab", "list").get("result", {}).get("tabs", [])
    }
    created = run("herdr", "tab", "create", "--workspace", workspace,
                  "--label", "cliamp", "--focus")
    if created.returncode != 0:
        return False

    for _ in range(10):
        time.sleep(0.1)
        tabs = output_json("herdr", "tab", "list").get("result", {}).get("tabs", [])
        new_tabs = [t for t in tabs if t.get("tab_id") not in before
                    and t.get("workspace_id") == workspace]
        if not new_tabs:
            continue
        tab_id = new_tabs[-1].get("tab_id")
        panes = herdr_panes()
        target = next((p for p in panes if p.get("tab_id") == tab_id), None)
        if target:
            run("herdr", "pane", "run", target["pane_id"], "cliamp")
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


if focus_herdr_cliamp() or focus_hyprland_cliamp() or open_in_pi_herdr():
    sys.exit(0)

# No Herdr or existing terminal was found: create/focus a dedicated TUI window.
subprocess.Popen([
    "omarchy-launch-or-focus-tui",
    "--app-id=org.omarchy.cliamp",
    "cliamp",
], start_new_session=True)
