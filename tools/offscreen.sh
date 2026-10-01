#!/bin/bash
# Runs ./godot with its window inside an unmapped X window, so it never shows or takes focus,
# but still renders (viewport readback works):
#   tools/offscreen.sh [godot args...]     e.g. tools/offscreen.sh -- --trackshots pu_forest 0.5
# --path . and --resolution 1280x720 are added unless given.
cd "$(dirname "$0")/.." || exit 1
python3 - <<'PY' > /tmp/offscreen_$$.xid &
import gi, signal
gi.require_version('Gtk', '3.0'); gi.require_version('GdkX11', '3.0')
from gi.repository import Gtk, GLib
w = Gtk.Window(); w.set_default_size(1280, 720); w.realize()
print(w.get_window().get_xid(), flush=True)
signal.signal(signal.SIGTERM, lambda *a: Gtk.main_quit())
GLib.timeout_add_seconds(7200, Gtk.main_quit)
Gtk.main()
PY
parent=$!
trap 'kill $parent 2>/dev/null; rm -f /tmp/offscreen_$$.xid' EXIT
for _ in $(seq 50); do [ -s /tmp/offscreen_$$.xid ] && break; sleep 0.1; done
extra=()
[[ " $* " == *" --path "* ]] || extra+=(--path .)
[[ " $* " == *" --resolution "* ]] || extra+=(--resolution 1280x720)
./godot "${extra[@]}" --wid "$(cat /tmp/offscreen_$$.xid)" "$@"
