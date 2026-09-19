#!/usr/bin/env python3
"""Summarize one ordinary Potts shard without imposing timing thresholds."""

import argparse
import json
import re
import tomllib
from pathlib import Path


PRECOMPILE = re.compile(
    r"(?P<count>\d+) dependenc(?:y|ies) successfully precompiled in "
    r"(?P<seconds>[0-9.]+) seconds?"
)


def phases(path):
    result = []
    if not path.exists():
        return result
    lines = path.read_text(errors="replace").splitlines()
    for line in lines[1:]:
        fields = line.split("\t")
        if len(fields) != 5:
            continue
        result.append({
            "phase": fields[0],
            "started_at": fields[1],
            "finished_at": fields[2],
            "duration_seconds": float(fields[3]),
            "status": fields[4],
        })
    return result


def fixtures(directory):
    result = []
    if not directory.exists():
        return result
    for path in sorted(directory.glob("*.toml")):
        result.append(tomllib.loads(path.read_text())["measurement"])
    return result


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--directory", default="ci-telemetry")
    parser.add_argument("--shard", required=True)
    args = parser.parse_args()
    directory = Path(args.directory)
    phase_records = phases(directory / "phases.tsv")
    fixture_records = fixtures(directory / "fixtures")
    log = (directory / "test.log").read_text(errors="replace")
    precompile_records = [
        {"dependencies": int(match.group("count")), "duration_seconds": float(match.group("seconds"))}
        for match in PRECOMPILE.finditer(log)
    ]
    loaded_extensions = sorted({
        extension
        for item in fixture_records
        for extension in item.get("loaded_extension_modules", [])
    })
    total_seconds = sum(
        item["duration_seconds"] for item in phase_records
        if item["phase"] == "package-test"
    )
    summary = {
        "schema_version": 1,
        "shard": args.shard,
        "phases": phase_records,
        "environment_resolution_seconds": sum(
            item["duration_seconds"] for item in phase_records
            if item["phase"] == "environment-resolution"
        ),
        "automatic_precompile": {
            "observed": bool(precompile_records),
            "duration_seconds": sum(item["duration_seconds"] for item in precompile_records),
            "records": precompile_records,
        },
        "worker_compilation_seconds": sum(
            item["compilation_seconds"] for item in fixture_records
        ),
        "scientific_execution_seconds": sum(
            item["scientific_execution_seconds"] for item in fixture_records
        ),
        "fixture_count": len(fixture_records),
        "failed_fixture_count": sum(item["status"] != "success" for item in fixture_records),
        "loaded_extension_modules": loaded_extensions,
        "total_runner_seconds": total_seconds,
        "total_runner_minutes": total_seconds / 60,
    }
    (directory / "package-shard-summary.json").write_text(
        json.dumps(summary, indent=2) + "\n"
    )


if __name__ == "__main__":
    main()
