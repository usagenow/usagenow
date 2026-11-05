#!/usr/bin/env python3
"""Run the Debug-only menu bar regression scenario with an external watchdog.

Usage: scripts/test-menubar-runtime.py path/to/Debug/UsageNow.app
The scenario uses isolated fixture data and actual MenuBarExtra scenes. It never
controls other apps or accesses the user's provider data. A blocked main actor
is killed promptly instead of allowing the regression to exhaust system memory.
"""
import pathlib
import plistlib
import selectors
import subprocess
import sys
import time

app = pathlib.Path(sys.argv[1]).resolve()
info = plistlib.loads((app / "Contents/Info.plist").read_bytes())
if not info["CFBundleIdentifier"].endswith(".Debug") or info.get("SUPublicEDKey"):
    raise SystemExit("Refusing to run against a production app or an update-enabled build")
process = subprocess.Popen([str(app / "Contents/MacOS/UsageNow"), "--menubar-smoke-test", *sys.argv[2:]],
                           stdout=subprocess.PIPE, stderr=subprocess.STDOUT, bufsize=0)
selector = selectors.DefaultSelector()
selector.register(process.stdout, selectors.EVENT_READ)
started = last_heartbeat = time.monotonic()
buffer = b""
passed = False
try:
    while process.poll() is None:
        for key, _ in selector.select(timeout=0.2):
            data = key.fileobj.read(65536)
            buffer += data or b""
            while b"\n" in buffer:
                line, buffer = buffer.split(b"\n", 1)
                text = line.decode(errors="replace")
                if text == "MENUBAR_SMOKE heartbeat":
                    last_heartbeat = time.monotonic()
                elif text.startswith("MENUBAR_SMOKE "):
                    print(text, flush=True)
                    passed |= text == "MENUBAR_SMOKE passed"
        now = time.monotonic()
        if now - started > 65 or (now - started > 8 and now - last_heartbeat > 3):
            raise RuntimeError("Menu bar main-thread heartbeat stalled or scenario timed out")
    if not passed or process.returncode != 0:
        raise RuntimeError(f"Menu bar scenario failed (exit {process.returncode})")
    print("PASS: real menu bar scenes remained responsive through all transitions and clock ticks.")
finally:
    if process.poll() is None:
        process.kill()
        process.wait(timeout=5)
    selector.close()
