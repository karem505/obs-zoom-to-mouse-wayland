#!/usr/bin/env bash
# Diagnose the obs-zoom-to-mouse-wayland setup. Run it AFTER logging out/in once.
set -u
UUID="zoompointer@karem"
NAME="org.gnome.Shell.Extensions.ZoomPointer"
OBJ="/org/gnome/Shell/Extensions/ZoomPointer"

echo "1) Session type (must be wayland):"
echo "   XDG_SESSION_TYPE=${XDG_SESSION_TYPE:-unknown}  desktop=${XDG_CURRENT_DESKTOP:-unknown}"

echo
echo "2) GNOME extension state:"
gnome-extensions info "$UUID" 2>&1 | grep -E "Name|State" || echo "   NOT FOUND — run install.sh, then log out/in."

echo
echo "3) Live pointer over D-Bus (move the mouse between the two reads):"
A=$(gdbus call --session --dest "$NAME" --object-path "$OBJ" --method "$NAME.GetPointer" 2>&1)
echo "   read 1: $A"; sleep 2
B=$(gdbus call --session --dest "$NAME" --object-path "$OBJ" --method "$NAME.GetPointer" 2>&1)
echo "   read 2: $B"
if [[ "$A" == *Error* || -z "$A" ]]; then
  echo "   FAIL: extension not answering. Log out/in, then: gnome-extensions enable $UUID"
elif [[ "$A" == "$B" ]]; then
  echo "   WARN: same value twice — did the mouse move? If it never changes, the extension isn't reading the cursor."
else
  echo "   OK: pointer is live and changing."
fi

echo
echo "4) Indicator round-trip (a 'ZOOM' badge should blink in the top bar):"
gdbus call --session --dest "$NAME" --object-path "$OBJ" --method "$NAME.ZoomOn"  >/dev/null 2>&1 && echo "   ZoomOn sent"
sleep 1
gdbus call --session --dest "$NAME" --object-path "$OBJ" --method "$NAME.ZoomOff" >/dev/null 2>&1 && echo "   ZoomOff sent"

echo
echo "5) Flatpak D-Bus override (only needed for Flatpak OBS):"
if flatpak info com.obsproject.Studio >/dev/null 2>&1; then
  grep -q "$NAME" "$HOME/.local/share/flatpak/overrides/com.obsproject.Studio" 2>/dev/null \
    && echo "   OK: override present" || echo "   MISSING: flatpak override --user --talk-name=$NAME com.obsproject.Studio"
else
  echo "   native OBS detected — no override needed"
fi

echo
echo "6) obs-websocket reachable (for global hotkeys):"
( exec 3<>/dev/tcp/127.0.0.1/4455 ) 2>/dev/null && echo "   OK: port 4455 open" \
  || echo "   not listening — enable OBS Tools > WebSocket Server Settings"
