# OBS Zoom to Mouse for Wayland (GNOME)

**Zoom-to-mouse / zoom-to-cursor for OBS Studio that actually works on Wayland** —
on GNOME (Ubuntu, Fedora, etc.) with **PipeWire screen capture**, live **cursor
following**, **global hotkeys**, and a **top-bar zoom indicator**.

[![License: GPL-3.0](https://img.shields.io/badge/License-GPLv3-blue.svg)](LICENSE)
![Platform: GNOME Wayland](https://img.shields.io/badge/Platform-GNOME%20Wayland-orange.svg)
![OBS Studio 30%2B](https://img.shields.io/badge/OBS%20Studio-30%2B%20(Flatpak%20%7C%20native)-purple.svg)

> The popular [`obs-zoom-to-mouse`](https://github.com/BlankSourceCode/obs-zoom-to-mouse)
> Lua script can't follow the cursor on Wayland, doesn't see the PipeWire capture
> source, and can crash on OBS 32. This project fixes all three and adds global
> hotkeys plus a panel indicator — without leaving Wayland or disabling security.

<p align="center">
  <img src="docs/images/demo.gif" alt="OBS zoom-to-mouse following the mouse cursor on GNOME Wayland, with a top-bar ZOOM indicator" width="720">
</p>

## Table of Contents

- [Why zoom-to-mouse breaks on Wayland](#why-zoom-to-mouse-breaks-on-wayland)
- [Features](#features)
- [Requirements](#requirements)
- [Installation](#installation)
- [Post-install setup (required)](#post-install-setup-required)
- [Usage](#usage)
- [How it works](#how-it-works)
- [Troubleshooting](#troubleshooting)
- [FAQ](#faq)
- [Uninstall](#uninstall)
- [Credits & attribution](#credits--attribution)
- [License](#license)

## Why zoom-to-mouse breaks on Wayland

Wayland intentionally restricts what applications can do, and three of those
restrictions each break a different part of zoom-to-mouse:

1. **Cursor position is hidden.** The upstream script reads the mouse with X11's
   `XQueryPointer`, which returns a *frozen* position under Wayland (XWayland only
   sees the pointer over X11 windows). The zoom never follows the cursor.
2. **The capture source is PipeWire**, not X11 `xshm_input`, so the script never
   lists "Screen Capture (PipeWire)" as a zoom source.
3. **Global hotkeys don't reach OBS** when it's in the background — Wayland won't
   let a backgrounded app grab keyboard shortcuts.

This project solves each one properly (see [How it works](#how-it-works)) instead
of telling you to fall back to an X11 session.

## Features

- ✅ **Live cursor following on Wayland** via a tiny GNOME Shell extension (uses
  `global.get_pointer()` — **no "unsafe mode", no root, no `xdotool`**).
- ✅ **PipeWire screen capture** is auto-detected as a valid zoom source.
- ✅ **Global hotkeys** (`Ctrl+Alt+Z` zoom, `Ctrl+Alt+A` follow) that work from any
  app, bridged through OBS's built-in WebSocket.
- ✅ **Top-bar "ZOOM" indicator** that appears while you're zoomed in.
- ✅ **OBS 32 compatibility fix** for the removed `obs_sceneitem_get_info` API.
- ✅ Works with **Flatpak and native OBS**; one-command install and uninstall.

## Requirements

| Component | Needed |
|-----------|--------|
| Desktop | **GNOME on Wayland** (Ubuntu 22.04+/24.04+, Fedora, etc.) |
| OBS Studio | 30 or newer (Flatpak `com.obsproject.Studio` or native) |
| GNOME Shell | 45–50 (ESM extensions) |
| Python | `python3` + `websocket-client` (`sudo apt install python3-websocket`) |
| Tools | `curl`, `patch`, `gsettings`, `gnome-extensions` (preinstalled on GNOME) |

## Installation

```bash
git clone https://github.com/karem505/obs-zoom-to-mouse-wayland.git
cd obs-zoom-to-mouse-wayland
bash install.sh
```

The installer:

1. **Downloads** the upstream `obs-zoom-to-mouse.lua` (pinned to `v1.0.1`) and
   applies the Wayland patch **on your machine** (the upstream file is *not*
   redistributed here — see [Credits & attribution](#credits--attribution)).
2. Installs the **GNOME extension** (`zoompointer@karem`).
3. Installs the **hotkey bridge** to `~/.local/bin/obs-zoom-toggle.py`.
4. Adds the **Flatpak D-Bus override** (only if OBS is a Flatpak).
5. Binds **global shortcuts** (override with `ZOOM_KEY=...` / `FOLLOW_KEY=...`).

> Custom keys, for example:
> `ZOOM_KEY='<Super>z' FOLLOW_KEY='<Super>a' bash install.sh`

## Post-install setup (required)

1. **Log out and log back in once.** GNOME only loads a new extension's code at
   login, and Wayland can't restart the shell in place. This is a one-time step.
2. In OBS: **Tools → Scripts → ＋** and add the patched script printed by the
   installer (`~/.local/share/obs-zoom-to-mouse-wayland/obs-zoom-to-mouse.lua`).
3. In OBS: **Tools → WebSocket Server Settings → enable the server** (required for
   the global hotkeys; the bridge reads its port/password automatically).
4. In the script panel, set **Zoom Source** to your **Screen Capture (PipeWire)**.

Verify everything at any time:

```bash
bash scripts/verify-zoom-pointer.sh
```

## Usage

| Shortcut | Action |
|----------|--------|
| `Ctrl + Alt + Z` | Toggle zoom to mouse |
| `Ctrl + Alt + A` | Toggle cursor following while zoomed |

While zoomed in, a **🔍 ZOOM** badge shows in the GNOME top bar and disappears when
you zoom out.

## How it works

Three small, focused pieces cooperate over D-Bus and OBS's WebSocket:

```mermaid
flowchart LR
    K["Global shortcut<br/>Ctrl+Alt+Z"] -->|runs| B["obs-zoom-toggle.py"]
    B -->|"WebSocket: TriggerHotkeyByName"| O["OBS + patched<br/>obs-zoom-to-mouse.lua"]
    O -->|"D-Bus: GetPointer"| E["GNOME extension<br/>zoompointer@karem"]
    E -->|"global.get_pointer()"| G["GNOME Shell"]
    O -->|"D-Bus: ZoomOn / ZoomOff"| E
    E -->|show / hide| I["Top-bar ZOOM indicator"]
```

- **GNOME extension** (`zoompointer@karem`) exposes the real cursor position and a
  panel indicator over the session bus (`org.gnome.Shell.Extensions.ZoomPointer`).
- **Patched Lua script** reads the cursor in-process via GIO (no per-frame
  subprocess), recognizes the PipeWire source, and toggles the indicator.
- **Hotkey bridge** lets a GNOME-owned shortcut fire the OBS hotkey globally.

## Troubleshooting

| Symptom | Fix |
|---------|-----|
| **Black screen in the OBS capture / preview** | **Restart OBS, or reload the script: Tools → Scripts → select it → ↻ (reload).** This re-initializes the PipeWire capture and the cursor connection. |
| Zoom doesn't follow the cursor | You haven't logged out/in since installing — do it once. Then `bash scripts/verify-zoom-pointer.sh`. |
| Top-bar **ZOOM** badge never appears | Same as above (extension not loaded yet), then reload the OBS script. |
| Global hotkey does nothing | Enable **Tools → WebSocket Server Settings** in OBS; install `python3-websocket`. |
| "Screen Capture (PipeWire)" missing from Zoom Source | You're on X11, or the source isn't in the current scene — switch to a Wayland session and add the capture. |
| Zoom lands in the wrong spot (HiDPI) | On fractional scaling, enable "Set manual source position" and set Scale X/Y = physical ÷ logical resolution. |

## FAQ

**Does OBS zoom-to-mouse work on Wayland?**
Not out of the box — the upstream script relies on X11 APIs. This project makes it
work on GNOME Wayland by reading the cursor through a GNOME Shell extension and
bridging hotkeys through OBS's WebSocket.

**Why is my OBS screen black after waking from sleep or reconnecting a monitor?**
The PipeWire capture stream drops. **Restart OBS or reload the OBS script**
(Tools → Scripts → ↻) to re-establish it — this is the most common fix.

**Do I need to disable GNOME "unsafe mode" or run anything as root?**
No. The extension calls `global.get_pointer()` from inside GNOME Shell, so no
unsafe mode, no root, and no `xdotool`/`ydotool` are required.

**Does this work on KDE Plasma / Sway / Hyprland?**
The cursor extension and shortcuts are GNOME-specific. The approach (compositor
provides the pointer, hotkeys bridged via WebSocket) can be ported, but this repo
targets **GNOME Wayland**.

**Why does the installer download the script instead of including it?**
The upstream `obs-zoom-to-mouse.lua` is "all rights reserved" with no license, so
it can't be redistributed. The installer fetches it from the original repository
and applies our patch locally. See [Credits & attribution](#credits--attribution).

**Why do global hotkeys need OBS's WebSocket?**
Wayland blocks background apps from grabbing global keys. A GNOME shortcut (which
*is* global) runs a tiny script that tells OBS to fire the hotkey over WebSocket.

## Uninstall

```bash
bash uninstall.sh
```

Then remove the script in OBS (Tools → Scripts) and log out/in to fully unload the
extension.

## Credits & attribution

- Original **obs-zoom-to-mouse** Lua script © **BlankSourceCode** —
  <https://github.com/BlankSourceCode/obs-zoom-to-mouse>. All credit for the core
  zoom functionality belongs to them. This repository does **not** redistribute
  their script; it patches a copy you download. See [`NOTICE`](NOTICE).
- Wayland support, GNOME extension, hotkey bridge, and indicator by this project's
  contributors.

## License

The original work in this repository (extension, bridge, scripts, installer, and
patch) is licensed under the **GNU GPL-3.0** — see [`LICENSE`](LICENSE). The
upstream OBS script retains its own copyright and is not included here.
