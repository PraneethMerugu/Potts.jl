#!/usr/bin/env python3
"""Convert ParallelTestRunner's stable verbose table into structured JSON."""

import argparse
import json
import re
from pathlib import Path


ROW = re.compile(
    r"^(?P<fixture>.+?)\s+\((?P<worker>\d+)\)\s*│\s*"
    r"(?P<test>[\d.]+)\s*│\s*(?P<init>[\d.]+)\s*│\s*"
    r"(?P<compile>[\d.]+)\s*│\s*(?P<gc>[\d.]+)\s*│\s*"
    r"(?P<gc_percent>[\d.]+)\s*│\s*(?P<allocation>[\d.]+)\s*│\s*"
    r"(?P<rss>[\d.]+)\s*│\s*$"
)
ANSI = re.compile(r"\x1b\[[0-9;]*m")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("log")
    parser.add_argument("output")
    parser.add_argument("--job", required=True)
    args = parser.parse_args()
    fixtures = []
    for raw_line in Path(args.log).read_text(errors="replace").splitlines():
        match = ROW.match(ANSI.sub("", raw_line))
        if not match:
            continue
        values = match.groupdict()
        test_time = float(values["test"])
        compile_percent = float(values["compile"])
        fixtures.append(
            {
                "fixture": values["fixture"].strip(),
                "worker": int(values["worker"]),
                "test_seconds": test_time,
                "initialization_seconds": float(values["init"]),
                "compile_percent": compile_percent,
                "compile_share_seconds": test_time * compile_percent / 100,
                "execution_share_seconds": test_time * (1 - compile_percent / 100),
                "gc_seconds": float(values["gc"]),
                "gc_percent": float(values["gc_percent"]),
                "allocated_megabytes": float(values["allocation"]),
                "rss_megabytes": float(values["rss"]),
                "exceeds_50_seconds": test_time > 50,
            }
        )
    result = {
        "schema_version": 1,
        "job": args.job,
        "fixture_count": len(fixtures),
        "fixtures": fixtures,
        "totals": {
            "test_seconds": sum(item["test_seconds"] for item in fixtures),
            "initialization_seconds": sum(item["initialization_seconds"] for item in fixtures),
            "compile_share_seconds": sum(item["compile_share_seconds"] for item in fixtures),
            "execution_share_seconds": sum(item["execution_share_seconds"] for item in fixtures),
            "allocated_megabytes": sum(item["allocated_megabytes"] for item in fixtures),
            "peak_rss_megabytes": max((item["rss_megabytes"] for item in fixtures), default=0),
        },
    }
    Path(args.output).write_text(json.dumps(result, indent=2) + "\n")


if __name__ == "__main__":
    main()
