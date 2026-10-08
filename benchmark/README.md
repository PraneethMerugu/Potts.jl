# Benchmarks

- `graner.jl` — fresh-process timing of Graner–Glazier (load, problem build, first MCS,
  first MCS after `remake`, warm throughput):
  `julia -t auto --project=benchmark benchmark/graner.jl [seq|cpu|metal] [mcs] [scale]`
- `benchmarks.jl` — BenchmarkTools `SUITE` (AirspeedVelocity-compatible) of the warm MCS.
- `lib/PottsModels/data/graner/` — the pre-equilibrated 72² initial condition (64 cells).
- `gate.jl` — the zero-allocation check of a warm MCS (D-053, D-157), with informational
  timings against this machine's rows of `baseline.toml`:
  `julia --project=benchmark benchmark/gate.jl [rocm|metal] [update] [--strict]` (CPU rows
  always, plus the named device backend). It exits 1 when a CPU row allocates; a row
  slower than its baseline is only flagged (`--strict` restores the old 5 % CPU rule).
  Whether a change is slower is decided by `ab.jl`.
- `ab.jl` / `ab_one.jl` — the paired A/B (AUTONOMY §7.4, P6.0bb), below.
- `machine.jl` — the machine table (keys of `baseline.toml`, pinning) and the Tuple type
  cache seeding shared by the gate and the A/B.
- `test/p6_0s_v7_tooling.jl` (frozen, D-090), `test/exclusive_transition.jl` and
  `test/p6_0bb_ab.jl` — tests of the lock, the gate's timing and the A/B harness.

### Machines and baselines (D-157)

`baseline.toml` is keyed by machine and backend: `[mac.cpu]`, `[mac.metal]`,
`[nucbox.cpu]`, `[nucbox.rocm]`, each with a `[<machine>.meta]` table; rows are
`<case>.<alg>` in ns/site per warm MCS (device rows are checkerboard). A machine is matched
by CPU model in `machine.jl` (or named with `POTTS_MACHINE`); an unknown one gets a key from
its CPU model, and `gate.jl ... update` writes only its own table. The `mac` rows are the
Apple M1 Pro; a new machine (the Mac Studio of P6.0bi) gets its own key and rows.

On the NucBox (Ryzen AI Max+ 395, 16 cores / 32 threads; logical n and n + 16 share
physical core n) a timed process runs pinned to one logical CPU of the reserved cores 12–15
(default 12, `POTTS_BENCH_CPU` to change), with its SMT sibling (n + 16) idle; everything
else, precompilation included, runs on `taskset -c 0-11,16-27`, as CI does. Every heavy
child also runs under a memory cap, `systemd-run --user --scope -p MemoryMax=8G`
(`POTTS_BENCH_MEMMAX`, 0 for none), because the machine is shared with CI and other jobs.
`gate.jl` re-runs itself pinned, and `ab.jl` pins each timed child. Before timing, both wait
while a CI job (`Runner.Worker`) runs, and for ROCm while another process holds the GPU
(a KFD client): a CI job's GPU group made a ROCm Graner–Glazier MCS read 2500 instead of
47 ns/site. Unpinned, under load, an Akeeb sequential run read 40 or 71 ns/site depending
on SMT sharing (a same-commit control of 1.729).

### The paired A/B (`ab.jl`, P6.0bb)

    julia benchmark/ab.jl <base> <candidate> <cases|all> <cpu|rocm|metal> [rounds] [options]
    julia benchmark/ab.jl --inprocess <checkout> <variants.jl> <cpu|rocm|metal> [rounds] [options]

By default it:

- **seeds the Tuple type cache** of every timed process to the same number of entries
  (500 000) after the packages load and before anything is built. Kernel launches look up
  Tuple types, and the table grows fourfold when it fills; a session with the packages
  loaded sits just below a growth (222k–243k entries of 262144 on the NucBox), and a
  session that happened to create more types times differently (D-145: Metal OpenVT read
  1.07–1.115 unseeded, 0.996 seeded).
- **runs two same-commit controls**: `<base>-abctl` and `<candidate>-abctl`, detached
  worktrees of the base's and the candidate's commits (created, or checked to be clean
  worktrees of the same repository and moved there; both checkouts must be clean). Two
  checkouts of one commit read up to 16 % apart unseeded on Metal (P6.2b); the controls
  show how far apart they read here.
- **interleaves**: every round runs each side once, each in a fresh process under the
  machine lock, and the order rotates, so each side runs first equally often (8 rounds for
  4 sides). When only the workload or the parameters change, `--inprocess` times both in
  one process, with second copies of the base and the candidate as the controls:
  `<variants.jl>` defines `AB_VARIANTS`, a vector of `label => T -> PottsProblem`, base
  first (example: `ab_variants_akeeb_mu.jl`, P6.2b's μ = 30 vs 24).
- **gives every side the same environment**: `--project=<side>/benchmark` with the side's
  test project stacked on JULIA_LOAD_PATH (the device packages come from there, for every
  side alike).
- **waits inside the lock**: each timed child, once it holds `tools/exclusive.sh` and
  before it loads a package, waits as above, until one overall deadline (`--max-wait`,
  4 h). It then reports what disturbed it at its start or end (a CI job, another GPU
  client, a busy SMT sibling, another busy reserved CPU); disturbed runs are listed.
- **pins** on the NucBox, as above.

The timed harness is this checkout's `ab_one.jl` and `gate.jl` for every side (its path and
commit are printed), run in each side's environment, so an older base is timed by the same
code; a side's own `ab_one.jl` is not used, and only the base and its control may lack a
case that `all` names.

Per case it prints three ratios, candidate/base, base-ctl/base and cand-ctl/candidate, each
as the statistic (`--stat`) and a 95 % bootstrap interval of the median per-round ratio
(rounds resampled with replacement, fixed seed). The statistic is `paired` for CPU and
ROCm: the median over rounds of the per-round ratio, which cancels a slow drift of the
machine, since the sides of a round run back to back (a drifting ROCm hour read worst
controls 1.024 on the fastest medians and 1.006 paired). For Metal it is `fastest`: each
side's fastest run median, i.e. the same GPU power state (D-145).

The verdict uses the controls as the resolution (coordinator ruling, 2026-10-07). `dev` is
the largest control deviation |ratio − 1| over every case and both controls (0 without
controls), and the pass margin is `1 + tolerance − dev` (printed). A control that reads
apart narrows what passes; it never loosens it.

| exit | meaning |
|---|---|
| 0 | pass: every candidate/base ≤ margin |
| 1 | regression: some candidate/base > 1 + `--tolerance` (0.05) |
| 2 | unreadable: some candidate/base between the margin and 1 + tolerance; re-run, or judge with the controls' range stated |
| 3 | some timed run was disturbed (listed); takes precedence: time again with the machine idle |
| 4 | harness error: bad arguments, a dirty checkout or one that is not a checkout's top level, a candidate that skips a case, a child that crashed |

A control whose interval excludes 1 is flagged on its case (a per-checkout offset, below);
it enters the verdict through `dev`. Inside a CI job, the job's own `Runner.Worker` is an
ancestor of the harness and is not counted as a disturbance; another job's is (use
`--wait=gpu` to wait only for other GPU clients). The `ab.jl` parent moves itself to the
untimed CPUs (0-11,16-27), so it and the lock's keeper never run on the reserved cores.

It also prints the resolution: the largest control deviation from 1 and the largest control
interval half-width. Measured on the NucBox (pinned CPU 12, 8 rounds, machine idle;
P6.0bb, 2026-10-07, at bbc39f07 against 9efdf924, 16 CPU and 8 ROCm cases, no disturbed
run):

| backend | control ratios (paired), range | largest deviation | largest interval half-width | controls whose interval excludes 1 |
|---|---|---|---|---|
| cpu | 0.9899 – 1.0077 | 0.0101 | 0.0208 | 6 of 32 |
| rocm | 0.9774 – 1.0127 | 0.0226 | 0.0064 | 5 of 16 |

So two checkouts of one commit differ by up to ~1 % on the CPU and ~2.3 % on ROCm
(Merks 100² and Wortel), a per-checkout offset that pinning and seeding do not remove and
that the rounds' bootstrap interval does not cover. With tolerance 0.05 the pass margin of
these runs is therefore 1.0399 (CPU) and 1.0274 (ROCm); every candidate/base read below it.

The D-090 form `ab.jl <base> <candidate> <case> <sequential|checkerboard> [rounds]` (no
options) is kept for its frozen contract (`test/p6_0s_v7_tooling.jl`, L2): each checkout's
own `ab_one.jl` (unseeded), base then candidate, no control, the fastest run median per
side. Only that form is kept: the three-argument form, which used to mean Metal, is an
error, and `<case> metal [rounds]` runs the paired form.

### Device timings run to GPU completion (D-090)

On a device backend `step!` only enqueues kernels. Every device timing (Metal, ROCm) in `gate.jl`
and `ab_one.jl` is therefore `step!` followed by a wait for the device (`device_sync` in
`timed_step!`, `gate.jl`), and each sample's setup waits too, so no setup work is still in
flight when the clock starts. The wait is `KernelAbstractions.synchronize(backend)`, except
on ROCm: AMDGPU.jl's default synchronize spins briefly, then waits for a HIP host callback
through Julia's event loop, whose wake-up made a ROCm Graner–Glazier MCS read ~20, ~47 or
~2500 ns/site from run to run; its blocking form (`hipStreamSynchronize`) read ~43. The
benchmark wait therefore spins on `hipStreamQuery` until the stream is done (then calls the
blocking synchronize, which returns at once and raises kernel errors): 13.7 ns/site, the
same as a steady run of 2000 MCS. A device row is therefore the latency of one MCS
launched on an idle GPU and waited for, not throughput: a run of MCS without a synchronize
in between may overlap host and GPU work, which this timing excludes. Timing flags are
advisory: the gate only flags a slow row, and `ab.jl` decides it. CPU rows time
`step!` alone and must allocate nothing.
Before 2026-10-01 the Metal rows timed host enqueue only, so Graner–Glazier and Wortel read
far below their GPU cost; the Metal rows of `baseline.toml` were re-measured once then (the
CPU rows were left as they were). Metal A/B verdicts from before that date on those models
say nothing about GPU cost, and an `ab.jl` run against a base checkout older than D-090
compares enqueue time (base) with completion time (candidate).

### The machine lock (`tools/exclusive.sh`, D-090)

A FIFO ticket queue in front of the directory lock `/tmp/potts-exclusive.lock`. Each call
takes a numbered ticket in `/tmp/potts-exclusive.q`; the lowest ticket is next and must
still take the directory lock by `mkdir`, so it excludes holders of the earlier script
(a bare `mkdir` loop polling every 20 s) as well. Waiters poll about once a second, so a run
queued before an A/B gets the lock before the A/B's next round. Waiters touch their ticket
every poll and holders every minute, so a ticket untouched for 5 minutes (e.g. of a
SIGKILLed waiter) is removed; queue entries whose names are not numbers are ignored. The
lock keeps the earlier script's 3-hour stale rule, because that script never refreshes it.
The command's exit status is passed through, and the ticket and lock are removed on exit,
HUP, INT, QUIT, PIPE or TERM. During the transition a waiter of the earlier script (20 s
poll) can lose the lock repeatedly to queued waiters (1 s poll), but never overlaps them.
`test/exclusive_transition.jl` covers both scripts together and the queue's stale rules.

The legacy rows below were measured with the since-removed `reference/` pin (D-048).

## 2026-09-29, Apple M1 Pro, Julia 1.12.6, 8 threads (MCS = N attempts)

| run | first MCS | remake + first MCS | warm | ns/attempt |
|---|---|---|---|---|
| legacy Potts 427dc2e2, sequential 72², 320 MCS | — (build 5.9 s, solve 27.4 s incl. compile) | | | |
| sequential 72² Float64 | 0.19 s | 0.018 s | 6130 MCS/s | 31 (24.8 BenchmarkTools median) |
| checkerboard CPU 72² Float64 | 0.9 s | 0.02 s | 5690 MCS/s | 34 |
| checkerboard CPU 576² Float64 | 0.9 s | 0.02 s | 296 MCS/s | 10.2 |
| checkerboard Metal 72² Float32 | 3.1 s | 0.03 s | 4470 MCS/s | 43 (launch-bound) |
| checkerboard Metal 576² Float32 | 3.1 s | 0.03 s | 926 MCS/s | 3.25 |

The legacy environment's precompile alone took 491 s; the workspace's CorePotts 1.9 s.

### After audit group 1 and CPU `_launch` (2026-09-29, same machine, `-t auto` = 6 threads)

| run | first MCS | remake + first MCS | warm | ns/attempt |
|---|---|---|---|---|
| sequential 72² Float64 | 0.30 s | 0.020 s | 7207 MCS/s | 26.8 |
| checkerboard CPU 72² Float64 | 0.88 s | 0.021 s | 6652 MCS/s | 29.0 |
| checkerboard CPU 576² Float64 | 1.02 s | 0.023 s | 412 MCS/s | 7.3 |
| checkerboard Metal 72² Float32 | 3.2 s | 0.032 s | 5551 MCS/s | 34.8 |
| checkerboard Metal 576² Float32 (2000 MCS) | 3.5 s | 0.036 s | 956 MCS/s | 3.15 |

Warm throughput is at or above the table above everywhere. Metal 576² needs 2000 MCS to
settle (500 MCS read 785 MCS/s). A warm MCS of every published model allocates 0 bytes,
sequential and checkerboard, now gated in the QA group.

### Generated (symbolic) vs hand-written Graner–Glazier, warm MCS (2026-09-29)

`PottsModels.GranerGlazier` through `PottsProblem` vs the hand-written CorePotts port,
BenchmarkTools median ns per site per MCS, Apple M1 Pro:

| run | hand-written | generated |
|---|---|---|
| sequential 72² | 24.4 | 25.8 |
| sequential 288² | 24.9 | 26.3 |
| checkerboard CPU 72² | 26.4 | 28.9 |
| checkerboard CPU 288² | 19.1 | 17.4 |

The generated ΔH is one fused contact loop plus the expanded volume delta. The remaining
~6% on small lattices is within per-call overhead and has not been chased further.

### Time to first MCS per published model (fresh process, warm package cache, 2026-09-29)

`julia --project=lib/PottsModels/test /tmp/ttfx_models.jl <model>` (build = `PottsProblem`
from the `@potts_model` constructor, including `mtkcompile` and code generation):

| model | `using Potts, PottsModels` | build | first sequential MCS | first checkerboard MCS |
|---|---|---|---|---|
| Graner–Glazier 72² | 4.6 s | 2.9 s | 0.5 s | 0.7 s |
| Wortel Act 150² | 4.8 s | 3.0 s | 1.0 s | 0.7 s |
| Merks 100² | 4.8 s | 2.6 s | 1.0 s | 1.0 s |
| OpenVT monolayer | 4.8 s | 3.3 s | 2.1 s | 1.0 s |
| Akeeb invasion 99×60 | 4.6 s | 3.7 s | 2.2 s | 1.2 s |

Re-measured after audit group 1 and CPU `_launch` (same command):

| model | `using Potts, PottsModels` | build | first sequential MCS | first checkerboard MCS |
|---|---|---|---|---|
| Graner–Glazier 72² | 4.9–6.5 s | 1.8 s | 0.9 s | 1.0 s |
| Wortel Act 150² | 5.0 s | 1.6 s | 1.2 s | 1.0 s |
| Merks 100² | 4.9 s | 1.3 s | 1.1 s | 1.0 s |
| OpenVT monolayer | 4.9 s | 1.9 s | 2.8 s | 1.3 s |
| Akeeb invasion 99×60 | 5.1 s | 2.6 s | 2.9 s | 1.4 s |

Build dropped by 1.1–1.4 s: the Potts precompile workload now covers `generated_code` and
`PottsProblem`. The first sequential MCS rose by 0.1–0.7 s; the cause is not isolated (Graner, which has
no phases, rose too, so it is not only group 1's new snapshot phases). Build plus first MCS is equal or lower for
every model; all are well under the 15 s target. The 6.5 s `using` was the first process
after a rebuild.

Legacy Graner–Glazier: build 5.9 s, first 320-MCS solve 27.4 s (mostly compilation).
