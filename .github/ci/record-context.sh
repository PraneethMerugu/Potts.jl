#!/usr/bin/env bash
set -euo pipefail

output=${CI_CONTEXT_FILE:-ci-telemetry/context.tsv}
mkdir -p "$(dirname "$output")"
printf 'key\tvalue\n' > "$output"

record() {
  printf '%s\t%s\n' "$1" "$2" >> "$output"
}

record repository "${GITHUB_REPOSITORY:-local}"
record workflow "${GITHUB_WORKFLOW:-local}"
record job "${GITHUB_JOB:-local}"
record run_id "${GITHUB_RUN_ID:-local}"
record run_attempt "${GITHUB_RUN_ATTEMPT:-local}"
record event "${GITHUB_EVENT_NAME:-local}"
record runner_os "${RUNNER_OS:-$(uname -s)}"
record runner_arch "${RUNNER_ARCH:-$(uname -m)}"
record runner_image "${ImageOS:-unknown}-${ImageVersion:-unknown}"
record source_revision "$(git rev-parse HEAD)"
record julia_version "$(julia --startup-file=no -e 'print(VERSION)')"
record julia_cpu_target "${JULIA_CPU_TARGET:-default}"
record julia_num_threads "${JULIA_NUM_THREADS:-default}"
record project "${JULIA_PROJECT:-default}"

for path in Project.toml Manifest.toml benchmark/Project.toml benchmark/Manifest.toml \
  benchmark/backends/metal/Project.toml benchmark/backends/metal/Manifest.toml \
  integration/Project.toml integration/Manifest.toml \
  integration/replay/Project.toml integration/replay/Manifest.toml; do
  [[ -f "$path" ]] || continue
  record "sha256:$path" "$(shasum -a 256 "$path" | awk '{print $1}')"
done

for sibling in deps/LocalMath deps/CorePotts; do
  [[ -d "$sibling/.git" || -f "$sibling/.git" ]] || continue
  record "revision:$sibling" "$(git -C "$sibling" rev-parse HEAD)"
done
