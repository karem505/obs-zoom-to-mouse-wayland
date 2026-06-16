#!/usr/bin/env bash
# Remove obs-zoom-to-mouse-wayland (extension, bridge, shortcuts, flatpak override).
# Does NOT remove the OBS script from your OBS scene — remove it in Tools > Scripts.
set -uo pipefail

EXT_UUID="zoompointer@karem"
DBUS_NAME="org.gnome.Shell.Extensions.ZoomPointer"
EXT_DIR="$HOME/.local/share/gnome-shell/extensions/$EXT_UUID"
BIN="$HOME/.local/bin/obs-zoom-toggle.py"
SHARE_DIR="$HOME/.local/share/obs-zoom-to-mouse-wayland"

say() { printf '\033[1;36m==>\033[0m %s\n' "$*"; }

say "Disabling + removing GNOME extension..."
gnome-extensions disable "$EXT_UUID" 2>/dev/null || true
rm -rf "$EXT_DIR"

say "Removing global shortcuts that point at the bridge..."
python3 - <<'PY'
from gi.repository import Gio
BASE = "org.gnome.settings-daemon.plugins.media-keys"
KBSCHEMA = BASE + ".custom-keybinding"
mk = Gio.Settings.new(BASE)
paths = list(mk.get_strv("custom-keybindings"))
keep = []
for p in paths:
    s = Gio.Settings.new_with_path(KBSCHEMA, p)
    if "obs-zoom-toggle.py" in s.get_string("command"):
        for k in ("name", "command", "binding"):
            s.reset(k)
    else:
        keep.append(p)
mk.set_strv("custom-keybindings", keep)

shell = Gio.Settings.new("org.gnome.shell")
en = [e for e in shell.get_strv("enabled-extensions") if e != "zoompointer@karem"]
shell.set_strv("enabled-extensions", en)
Gio.Settings.sync()
print("   shortcuts removed; extension disabled")
PY

say "Removing bridge script + downloaded files..."
rm -f "$BIN"
rm -rf "$SHARE_DIR"

if flatpak info com.obsproject.Studio >/dev/null 2>&1; then
  say "Removing Flatpak D-Bus override..."
  flatpak override --user --no-talk-name="$DBUS_NAME" com.obsproject.Studio 2>/dev/null || true
fi

say "Done. Log out/in to fully unload the extension, and remove the script in OBS (Tools > Scripts)."
