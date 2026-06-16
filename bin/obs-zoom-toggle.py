#!/usr/bin/env python3
"""Trigger obs-zoom-to-mouse from a GLOBAL desktop shortcut on Wayland.

Wayland does not let OBS grab background (global) hotkeys, so the desktop
environment owns the key and runs this script, which tells OBS to fire the
hotkey by name over OBS's built-in WebSocket server (obs-websocket v5).

Usage:
    obs-zoom-toggle.py [zoom|follow]      (default: zoom)

Requires: python3-websocket (the "websocket-client" module) and OBS with the
WebSocket server enabled (Tools -> WebSocket Server Settings).
"""
import sys
import os
import json
import hashlib
import base64
import subprocess

HOTKEYS = {"zoom": "toggle_zoom_hotkey", "follow": "toggle_follow_hotkey"}

# obs-websocket config location for Flatpak OBS and native OBS, in priority order.
CONFIG_CANDIDATES = [
    "~/.var/app/com.obsproject.Studio/config/obs-studio/plugin_config/obs-websocket/config.json",
    "~/.config/obs-studio/plugin_config/obs-websocket/config.json",
]


def notify(msg):
    """Best-effort desktop notification (shortcut output is otherwise invisible)."""
    try:
        subprocess.Popen(["notify-send", "-a", "OBS Zoom", "OBS Zoom", msg])
    except Exception:
        pass


def find_config():
    for path in CONFIG_CANDIDATES:
        p = os.path.expanduser(path)
        if os.path.isfile(p):
            return p
    return None


def main():
    which = sys.argv[1] if len(sys.argv) > 1 else "zoom"
    hotkey = HOTKEYS.get(which, which)

    cfg_path = find_config()
    if not cfg_path:
        notify("OBS WebSocket config not found. Enable it in OBS: Tools > WebSocket Server Settings.")
        return 1
    try:
        cfg = json.load(open(cfg_path))
    except Exception as e:
        notify(f"Can't read OBS WebSocket config: {e}")
        return 1

    port = cfg.get("server_port", 4455)
    password = cfg.get("server_password", "")

    try:
        import websocket  # from the websocket-client package
    except ImportError:
        notify("Missing dependency: install python3-websocket (websocket-client).")
        return 1

    try:
        ws = websocket.create_connection(f"ws://127.0.0.1:{port}", timeout=3)
    except Exception:
        notify("OBS not reachable. Is OBS open with the WebSocket server enabled?")
        return 1

    try:
        hello = json.loads(ws.recv())["d"]
        ident = {"rpcVersion": 1, "eventSubscriptions": 0}
        auth = hello.get("authentication")
        if auth:
            secret = base64.b64encode(
                hashlib.sha256((password + auth["salt"]).encode()).digest()).decode()
            ident["authentication"] = base64.b64encode(
                hashlib.sha256((secret + auth["challenge"]).encode()).digest()).decode()
        ws.send(json.dumps({"op": 1, "d": ident}))
        if json.loads(ws.recv()).get("op") != 2:
            notify("OBS WebSocket authentication failed (wrong password?).")
            return 1
        ws.send(json.dumps({"op": 6, "d": {
            "requestType": "TriggerHotkeyByName",
            "requestData": {"hotkeyName": hotkey},
            "requestId": "1"}}))
        status = json.loads(ws.recv()).get("d", {}).get("requestStatus", {})
        if not status.get("result"):
            notify(f"OBS rejected hotkey '{hotkey}': {status.get('comment', status)}")
            return 1
    finally:
        ws.close()
    return 0


if __name__ == "__main__":
    sys.exit(main())
