#!/usr/bin/env python3
"""Hold-to-zoom daemon for obs-zoom-to-mouse-wayland.

Grabs the keyboard globally via evdev so the key combination is dedicated to
zoom. Requires access to /dev/input — run as root or add your user to the
input group (``sudo usermod -aG input $USER`` then log out/in).

Hold  Alt + Ctrl + X  to zoom in.
Release Alt + Ctrl + X  to zoom out.

Usage:
    sudo python3 obs-zoom-hold.py
    # or, as your user (after joining the input group):
    python3 obs-zoom-hold.py
"""
import sys
import os
import subprocess

try:
    from evdev import InputDevice, ecodes, list_devices
except ImportError:
    print("Missing dependency: install python3-evdev (or: pip install --user evdev)", file=sys.stderr)
    sys.exit(1)

DBUS_NAME = "org.gnome.Shell.Extensions.ZoomPointer"
DBUS_PATH = "/org/gnome/Shell/Extensions/ZoomPointer"
BRIDGE = os.path.expanduser("~/.local/bin/obs-zoom-toggle.py")

MODIFIER_KEYS = {
    ecodes.KEY_LEFTALT,
    ecodes.KEY_RIGHTALT,
    ecodes.KEY_LEFTCTRL,
    ecodes.KEY_RIGHTCTRL,
}
TARGET_KEY = ecodes.KEY_X  # 'x'


class HoldToZoom:
    def __init__(self):
        self.zoomed = False
        self.mods = set()
        self.device = self._find_keyboard()

    def _find_keyboard(self):
        for path in list_devices():
            dev = InputDevice(path)
            caps = dev.capabilities()
            if ecodes.EV_KEY in caps:
                keys = caps[ecodes.EV_KEY]
                if TARGET_KEY in keys and ecodes.KEY_LEFTALT in keys:
                    return dev
            dev.close()
        raise RuntimeError("No keyboard device found")

    # ---------------------------------------------------------------- D-Bus
    def dbus(self, method):
        """Call a method on the GNOME extension over the session bus."""
        subprocess.run(
            [
                "dbus-send",
                "--session",
                "--dest=" + DBUS_NAME,
                DBUS_PATH,
                "org.gnome.Shell.Extensions.ZoomPointer." + method,
            ],
            capture_output=True,
        )

    # ---------------------------------------------------------------- OBS
    def obs_trigger(self):
        """Ask OBS to fire its zoom hotkey via the WebSocket bridge."""
        if os.path.exists(BRIDGE):
            subprocess.run([BRIDGE, "zoom"], capture_output=True)

    # ---------------------------------------------------------------- actions
    def zoom_in(self):
        if self.zoomed:
            return
        self.dbus("ZoomOn")          # show the top-bar ZOOM indicator
        self.obs_trigger()           # toggle OBS zoom on (from off)
        self.zoomed = True

    def zoom_out(self):
        if not self.zoomed:
            return
        self.dbus("ZoomOff")         # hide the top-bar ZOOM indicator
        self.obs_trigger()           # toggle OBS zoom off (from on)
        self.zoomed = False

    # ---------------------------------------------------------------- main loop
    def run(self):
        self.device.grab()           # exclusive grab — no other app sees these keys
        try:
            for event in self.device.read_loop():
                if event.type != ecodes.EV_KEY:
                    continue
                key = event.code

                if key in MODIFIER_KEYS:
                    if event.value == 1:   # key down
                        self.mods.add(key)
                    elif event.value == 0:  # key up
                        self.mods.discard(key)
                    continue

                if key != TARGET_KEY:
                    continue

                has_alt = ecodes.KEY_LEFTALT in self.mods or ecodes.KEY_RIGHTALT in self.mods
                has_ctrl = ecodes.KEY_LEFTCTRL in self.mods or ecodes.KEY_RIGHTCTRL in self.mods

                if event.value == 1:   # X pressed
                    if has_alt and has_ctrl:
                        self.zoom_in()
                elif event.value == 0:  # X released
                    self.zoom_out()
        finally:
            self.device.ungrab()
            self.device.close()


def main():
    try:
        HoldToZoom().run()
    except PermissionError:
        print("Permission denied: cannot access /dev/input. Run with sudo or add your user to the input group.", file=sys.stderr)
        sys.exit(1)
    except RuntimeError as e:
        print(str(e), file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()
