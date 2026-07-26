"""Run CC3D 4.2.5 without writing its first-launch settings into the user home."""

import os
import runpy
import sys


if len(sys.argv) < 3:
    raise SystemExit(
        "usage: run_cc3d_isolated.py SETTINGS_ROOT RUN_SCRIPT [RUN_SCRIPT_ARGS...]"
    )

settings_root = os.path.abspath(sys.argv.pop(1))
run_script = os.path.abspath(sys.argv.pop(1))
os.makedirs(settings_root, exist_ok=True)

system_expanduser = os.path.expanduser


def isolated_expanduser(path):
    if path == "~":
        return settings_root
    return system_expanduser(path)


os.path.expanduser = isolated_expanduser
sys.argv[0] = run_script
runpy.run_path(run_script, run_name="__main__")
