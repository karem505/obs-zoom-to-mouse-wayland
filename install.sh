#!/usr/bin/env bash
#
# obs-zoom-to-mouse-wayland installer (GNOME on Wayland)
# - downloads the upstream obs-zoom-to-mouse.lua (v1.0.1) and applies the Wayland patch locally
# - installs the GNOME Shell extension (cursor + top-bar indicator)
# - installs the global-hotkey bridge and binds Ctrl+Alt+Z / Ctrl+Alt+A
#
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Pinned upstream base (BlankSourceCode/obs-zoom-to-mouse v1.0.1). We patch a local
# copy at install time; the upstream file is "all rights reserved" and is NOT redistributed.
UPSTREAM_SHA="23b27d925b2e95635b63a833f01c620f019c0239"
UPSTREAM_URL="https://raw.githubusercontent.com/BlankSourceCode/obs-zoom-to-mouse/${UPSTREAM_SHA}/obs-zoom-to-mouse.lua"

EXT_UUID="zoompointer@karem"
DBUS_NAME="org.gnome.Shell.Extensions.ZoomPointer"
EXT_DIR="$HOME/.local/share/gnome-shell/extensions/$EXT_UUID"
BIN_DIR="$HOME/.local/bin"
SHARE_DIR="$HOME/.local/share/obs-zoom-to-mouse-wayland"
LUA_OUT="$SHARE_DIR/obs-zoom-to-mouse.lua"
ZOOM_KEY="${ZOOM_KEY:-<Control><Alt>z}"
FOLLOW_KEY="${FOLLOW_KEY:-<Control><Alt>a}"

say()  { printf '\033[1;36m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[!]\033[0m %s\n' "$*"; }
die()  { printf '\033[1;31m[x]\033[0m %s\n' "$*" >&2; exit 1; }

# ---------------------------------------------------------------- preflight
[ "${XDG_SESSION_TYPE:-}" = "wayland" ] || warn "Session is '${XDG_SESSION_TYPE:-unknown}', not wayland. This project targets GNOME on Wayland."
case "${XDG_CURRENT_DESKTOP:-}" in *GNOME*) : ;; *) warn "Desktop is '${XDG_CURRENT_DESKTOP:-unknown}', not GNOME. The cursor extension and shortcuts are GNOME-specific." ;; esac
for c in curl patch python3 gsettings gnome-extensions; do command -v "$c" >/dev/null 2>&1 || die "Missing required command: $c"; done
python3 -c "import websocket" 2>/dev/null || warn "Python 'websocket-client' is missing. Global hotkeys need it: sudo apt install python3-websocket  (or: pip install --user websocket-client)"

# ---------------------------------------------------------------- 1. build patched lua
say "Downloading upstream obs-zoom-to-mouse.lua (v1.0.1) and applying the Wayland patch..."
mkdir -p "$SHARE_DIR"
curl -fsSL "$UPSTREAM_URL" | tr -d '\r' > "$SHARE_DIR/obs-zoom-to-mouse.orig.lua"
cp "$SHARE_DIR/obs-zoom-to-mouse.orig.lua" "$LUA_OUT"
patch -s "$LUA_OUT" < "$REPO_DIR/patches/wayland-support.patch" || die "Patch failed to apply (upstream may have changed)."
say "Patched OBS script written to: $LUA_OUT"

# ---------------------------------------------------------------- 2. GNOME extension
say "Installing GNOME Shell extension ($EXT_UUID)..."
mkdir -p "$EXT_DIR"
cp "$REPO_DIR/gnome-extension/$EXT_UUID/extension.js"  "$EXT_DIR/"
cp "$REPO_DIR/gnome-extension/$EXT_UUID/metadata.json" "$EXT_DIR/"

# ---------------------------------------------------------------- 3. hotkey bridge
say "Installing global-hotkey bridge to $BIN_DIR/obs-zoom-toggle.py ..."
mkdir -p "$BIN_DIR"
install -m 0755 "$REPO_DIR/bin/obs-zoom-toggle.py" "$BIN_DIR/obs-zoom-toggle.py"

# ---------------------------------------------------------------- 4. flatpak override
if flatpak info com.obsproject.Studio >/dev/null 2>&1; then
  say "Flatpak OBS detected — granting D-Bus access to the extension..."
  flatpak override --user --talk-name="$DBUS_NAME" com.obsproject.Studio
else
  say "Native OBS (no Flatpak override needed)."
fi

# ---------------------------------------------------------------- 5. enable extension + bind shortcuts
say "Enabling the extension and binding global shortcuts ($ZOOM_KEY / $FOLLOW_KEY)..."
ZOOM_KEY="$ZOOM_KEY" FOLLOW_KEY="$FOLLOW_KEY" BIN_DIR="$BIN_DIR" EXT_UUID="$EXT_UUID" python3 - <<'PY'
import os
from gi.repository import Gio

ext = os.environ["EXT_UUID"]
binpy = os.path.join(os.environ["BIN_DIR"], "obs-zoom-toggle.py")
zoom_key = os.environ["ZOOM_KEY"]
follow_key = os.environ["FOLLOW_KEY"]

# enable the extension so it auto-loads on next login
shell = Gio.Settings.new("org.gnome.shell")
en = list(shell.get_strv("enabled-extensions"))
if ext not in en:
    en.append(ext); shell.set_strv("enabled-extensions", en)
dis = list(shell.get_strv("disabled-extensions"))
if ext in dis:
    dis.remove(ext); shell.set_strv("disabled-extensions", dis)

# add two custom global keybindings without clobbering existing ones
BASE = "org.gnome.settings-daemon.plugins.media-keys"
KBSCHEMA = BASE + ".custom-keybinding"
PREFIX = "/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/"
mk = Gio.Settings.new(BASE)
paths = list(mk.get_strv("custom-keybindings"))

def slot_for(command, name, binding):
    # reuse an existing slot if it already points at our command (idempotent)
    for p in paths:
        s = Gio.Settings.new_with_path(KBSCHEMA, p)
        if s.get_string("command") == command:
            s.set_string("name", name); s.set_string("binding", binding)
            return p
    i = 0
    while f"{PREFIX}custom{i}/" in paths:
        i += 1
    p = f"{PREFIX}custom{i}/"
    s = Gio.Settings.new_with_path(KBSCHEMA, p)
    s.set_string("name", name); s.set_string("command", command); s.set_string("binding", binding)
    paths.append(p)
    return p

slot_for(f"/usr/bin/python3 {binpy} zoom",   "OBS Zoom Toggle",        zoom_key)
slot_for(f"/usr/bin/python3 {binpy} follow", "OBS Zoom Follow Toggle", follow_key)
mk.set_strv("custom-keybindings", paths)
Gio.Settings.sync()
print("   extension enabled; shortcuts bound:", zoom_key, follow_key)
PY

# ---------------------------------------------------------------- done
cat <<EOF

$(say "Install complete.")

NEXT STEPS (required):
  1) LOG OUT and LOG BACK IN once  (GNOME only loads new extension code at login).
  2) In OBS: Tools > Scripts > "+" and add:
        $LUA_OUT
  3) In OBS: Tools > WebSocket Server Settings > enable the server (needed for global hotkeys).
  4) In the script panel set "Zoom Source" to your screen capture (e.g. "Screen Capture (PipeWire)").

USAGE:
  $ZOOM_KEY    toggle zoom to mouse        $FOLLOW_KEY    toggle follow
  A "ZOOM" badge appears in the top bar while zoomed.

Verify anytime:  bash "$REPO_DIR/scripts/verify-zoom-pointer.sh"
EOF
