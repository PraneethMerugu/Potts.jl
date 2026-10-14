#!/bin/bash
# Julia in its own systemd user scope (D-248): MemoryMax as the coordinator's branch checks
# (24G per process), and a low CPU weight so Lane S yields CPU time to anything else on its
# cores. The caller's CPU affinity (taskset) is inherited. Used as JULIA by item.sh, so
# .github/ci/parallel.sh runs unchanged.
exec systemd-run --user --scope -q -p MemoryMax=${POTTS_MEMMAX:-24G} \
    -p CPUWeight=${POTTS_CPUWEIGHT:-100} "${POTTS_JULIA_BIN:-$HOME/.juliaup/bin/julia}" "$@"
