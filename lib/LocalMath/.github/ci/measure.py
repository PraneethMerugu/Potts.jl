#!/usr/bin/env python3
"""Run one CI phase and append a portable, non-gating JSON record."""

import argparse
import datetime
import json
import os
import platform
import resource
import subprocess
import sys
import time
from pathlib import Path


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--output", required=True)
    parser.add_argument("--job", required=True)
    parser.add_argument("--phase", required=True)
    parser.add_argument("--log")
    parser.add_argument("--annotation", action="append", default=[])
    parser.add_argument("command", nargs=argparse.REMAINDER)
    args = parser.parse_args()
    command = args.command[1:] if args.command[:1] == ["--"] else args.command
    if not command:
        parser.error("a command is required after --")

    output = Path(args.output)
    output.mkdir(parents=True, exist_ok=True)
    annotations = dict(item.split("=", 1) for item in args.annotation)
    started_at = datetime.datetime.now(datetime.timezone.utc)
    started = time.monotonic_ns()
    usage_before = resource.getrusage(resource.RUSAGE_CHILDREN)

    log_handle = open(args.log, "wb") if args.log else None
    process = None
    exit_code = 127
    launch_error = None
    try:
        process = subprocess.Popen(command, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
        assert process.stdout is not None
        for chunk in iter(lambda: process.stdout.read1(65536), b""):
            sys.stdout.buffer.write(chunk)
            sys.stdout.buffer.flush()
            if log_handle:
                log_handle.write(chunk)
        exit_code = process.wait()
    except KeyboardInterrupt:
        if process is not None:
            process.terminate()
            process.wait()
        exit_code = 130
    except OSError as error:
        launch_error = f"{type(error).__name__}: {error}"
        print(launch_error, file=sys.stderr)
    finally:
        if log_handle:
            log_handle.close()

    usage_after = resource.getrusage(resource.RUSAGE_CHILDREN)
    duration = (time.monotonic_ns() - started) / 1_000_000_000
    # ru_maxrss is KiB on Linux and bytes on macOS.
    max_rss_kib = usage_after.ru_maxrss / 1024 if sys.platform == "darwin" else usage_after.ru_maxrss
    record = {
        "schema_version": 1,
        "job": args.job,
        "phase": args.phase,
        "started_at": started_at.isoformat(),
        "duration_seconds": duration,
        "exit_code": exit_code,
        "user_cpu_seconds": usage_after.ru_utime - usage_before.ru_utime,
        "system_cpu_seconds": usage_after.ru_stime - usage_before.ru_stime,
        "max_child_rss_kib": max_rss_kib,
        "command": command,
        "process_id": process.pid if process is not None else None,
        "launch_error": launch_error,
        "runner_os": os.environ.get("RUNNER_OS", platform.system()),
        "runner_arch": os.environ.get("RUNNER_ARCH", platform.machine()),
        "github_sha": os.environ.get("GITHUB_SHA"),
        "github_run_id": os.environ.get("GITHUB_RUN_ID"),
        "julia_version": os.environ.get("JULIA_VERSION"),
        "annotations": annotations,
    }
    with (output / "phases.jsonl").open("a", encoding="utf-8") as stream:
        json.dump(record, stream, separators=(",", ":"))
        stream.write("\n")
    return exit_code


if __name__ == "__main__":
    raise SystemExit(main())
