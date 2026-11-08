"""Replay PreviewStream's paths on the real ScreenHub and Forward, against the live phone.

argv: <patched server dir> <iphone_use_select.py> <phone host> <mjpeg port>
"""

import importlib.util
import os
import sys
import tempfile
import time

server_dir, selector_path, host, port = sys.argv[1], sys.argv[2], sys.argv[3], int(sys.argv[4])
sys.path.insert(0, server_dir)
import wda_screen  # noqa: E402

spec = importlib.util.spec_from_file_location("iphone_use_select", selector_path)
selector = importlib.util.module_from_spec(spec)
spec.loader.exec_module(selector)

relay = selector.Forward(host, port)
os.environ["IPHONE_USE_MJPEG_URL"] = f"http://127.0.0.1:{relay.port}/"


def poll_until_frame(hub, seconds=8.0):
    deadline = time.monotonic() + seconds
    while time.monotonic() < deadline:
        wire = hub.frame()
        if wire["frame"]:
            return wire
        time.sleep(0.2)
    return wire


def frames_for(hub, seconds=2.0):
    got, seq = 0, 0
    deadline = time.monotonic() + seconds
    while time.monotonic() < deadline:
        wire = hub.frame(after_seq=seq)
        if wire["frame"]:
            got += 1
            seq = wire["frame"]["seq"]
        time.sleep(0.15)
    return got, wire


this_host = tempfile.mkdtemp(prefix="host-a-")
other_host = tempfile.mkdtemp(prefix="host-b-")

print("1. The relayed stream feeds the preview")
viewer = wda_screen.ScreenHub(this_host)
wire = poll_until_frame(viewer)
f = wire["frame"]
print(f"   first frame: {f and (f['width'], f['height'], f['mimeType'])}, paused={wire['paused']}")

print("2. Another process on this host pauses (same state file)")
pauser = wda_screen.ScreenHub(this_host)
pauser.set_paused(True)
time.sleep(0.5)
got, wire = frames_for(viewer)
print(
    f"   viewer frames while paused: {got}, paused={wire['paused']}, "
    f"frame_available={wire['frame_available']}, curl alive={viewer._child is not None}"
)
pauser.set_paused(False)
got, wire = frames_for(viewer, 4.0)
print(f"   viewer frames after resume: {got}")

print("3. An agent on another host pauses (its own state file)")
elsewhere = wda_screen.ScreenHub(other_host)
elsewhere.set_paused(True)
time.sleep(0.5)
got, wire = frames_for(viewer)
print(f"   viewer frames while the other host is paused: {got}, paused={wire['paused']}")
elsewhere.set_paused(False)

print("4. The panel closes: no poll for the lease time")
time.sleep(wda_screen.FRAME_LEASE_SECONDS + 1.5)
print(f"   curl alive after the lease: {viewer._child is not None}")

viewer.close()
relay.close()
