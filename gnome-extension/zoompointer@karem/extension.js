import GObject from 'gi://GObject';
import Gio from 'gi://Gio';
import St from 'gi://St';
import Clutter from 'gi://Clutter';
import * as PanelMenu from 'resource:///org/gnome/shell/ui/panelMenu.js';
import * as Main from 'resource:///org/gnome/shell/ui/main.js';
import {Extension} from 'resource:///org/gnome/shell/extensions/extension.js';

const IFACE = `
<node>
  <interface name="org.gnome.Shell.Extensions.ZoomPointer">
    <method name="GetPointer">
      <arg type="i" direction="out" name="x"/>
      <arg type="i" direction="out" name="y"/>
    </method>
    <method name="ZoomOn"/>
    <method name="ZoomOff"/>
  </interface>
</node>`;

const BUS_NAME = 'org.gnome.Shell.Extensions.ZoomPointer';
const OBJ_PATH = '/org/gnome/Shell/Extensions/ZoomPointer';

const ZoomIndicator = GObject.registerClass(
class ZoomIndicator extends PanelMenu.Button {
    _init() {
        super._init(0.0, 'OBS Zoom Indicator', false);
        const box = new St.BoxLayout({style_class: 'panel-status-menu-box'});
        box.add_child(new St.Icon({
            icon_name: 'zoom-in-symbolic',
            style_class: 'system-status-icon',
        }));
        box.add_child(new St.Label({
            text: 'ZOOM',
            y_align: Clutter.ActorAlign.CENTER,
            style: 'margin-left: 4px; font-weight: bold;',
        }));
        this.add_child(box);
    }
});

export default class ZoomPointerExtension extends Extension {
    enable() {
        // Panel indicator — hidden until OBS reports it is zoomed in.
        this._indicator = new ZoomIndicator();
        Main.panel.addToStatusArea('zoompointer-indicator', this._indicator);
        this._indicator.visible = false;

        // D-Bus service consumed by the obs-zoom-to-mouse lua script.
        this._dbus = Gio.DBusExportedObject.wrapJSObject(IFACE, this);
        this._dbus.export(Gio.DBus.session, OBJ_PATH);
        this._ownerId = Gio.bus_own_name_on_connection(
            Gio.DBus.session, BUS_NAME, Gio.BusNameOwnerFlags.NONE, null, null);
    }

    disable() {
        if (this._ownerId) {
            Gio.bus_unown_name(this._ownerId);
            this._ownerId = 0;
        }
        if (this._dbus) {
            this._dbus.unexport();
            this._dbus = null;
        }
        if (this._indicator) {
            this._indicator.destroy();
            this._indicator = null;
        }
    }

    // Returns the global pointer position in stage (logical) pixels.
    GetPointer() {
        const [x, y] = global.get_pointer();
        return [Math.round(x), Math.round(y)];
    }

    ZoomOn() {
        if (this._indicator)
            this._indicator.visible = true;
    }

    ZoomOff() {
        if (this._indicator)
            this._indicator.visible = false;
    }
}
