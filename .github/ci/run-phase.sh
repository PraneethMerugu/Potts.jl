#!/usr/bin/env bash
set -uo pipefail

phase=${1:?phase name is required}
shift

telemetry_file=${CI_TELEMETRY_FILE:-ci-telemetry/phases.tsv}
mkdir -p "$(dirname "$telemetry_file")"
if [[ ! -s "$telemetry_file" ]]; then
  printf 'phase\tstarted_at\tfinished_at\tduration_seconds\tstatus\n' > "$telemetry_file"
fi

started_at=$(date -u +'%Y-%m-%dT%H:%M:%SZ')
started_seconds=$SECONDS
"$@"
status=$?
duration_seconds=$((SECONDS - started_seconds))
finished_at=$(date -u +'%Y-%m-%dT%H:%M:%SZ')
printf '%s\t%s\t%s\t%s\t%s\n' \
  "$phase" "$started_at" "$finished_at" "$duration_seconds" "$status" >> "$telemetry_file"
exit "$status"
