# GPU host-transfer audit (P6.0v)

2026-10-01, ROADMAP P6.0v, D-085. The goal (user): every synchronize, host↔device copy or
host-side work during a Metal MCS is either unavoidable or removed. This document is the
audit and the measured baseline. The removals are P6.0v1–P6.0v3 (ROADMAP) plus the rows
proposed in §9. Line numbers are at `feat/p6-0v` round 2: 1554d56 + P6.0v + the approved
P6.0d (ee2331b), merged into this branch. The baseline numbers (§2, §7.1, §8) were measured
before that merge; P6.0d does not change them, since no gate model has frozen kinds.

**Status after the user's D-089 (2026-10-01).** On a GPU backend the lifecycle will be
planned and applied entirely on the device, with no trigger read-back, so a quiet MCS costs
0 / 0 / 0 B for every model. P6.0v1 builds this and re-freezes target (b). Until then, (b)
and the D-035 read-back are unchanged here. The pending P6.0d counts and `stats.lifecycle`
are then read only at the existing host reads: saves, the end of `solve!`, and `checkpoint`.
Rows P6.0v4, P6.0v5 and P6.0v7 are filed in the ROADMAP; P6.0v8 is folded into P6.0v3.

Machine: Apple M1 Pro, macOS 27, Metal.jl 1.10.0, Julia 1.12.6, single thread. Metal timings
on this machine flip between two power states (about 1.5–2×, D-053). Ratios measured in one
process are reliable; absolute numbers between processes are not.

## 1. Counters and method

`PottsStats` has three new `Int` fields, summed by `merge` and restored with checkpoints:

| field | counts |
|---|---|
| `syncs` | explicit `KernelAbstractions.synchronize` calls |
| `transfers` | host↔device array copies. One `Array(a)`, one crossing `copyto!`, and each device array leaf of an `Adapt.adapt(Array, …)` snapshot count as 1. |
| `transfer_bytes` | `sizeof` of the device array copied |

All of them go through one helper family in `lib/CorePotts/src/transfers.jl`: `_sync!`,
`_to_host`, `_copy!`, `_readback`, `_snapshot` and `_adapt_host` (a counting `Adapt`
adaptor). They all call one counter, `_count_transfer!`. On the CPU these helpers compile to
the old code: `_ondevice(::Array)` is a constant `false`, and `_sync!(stats, ::CPU)` adds
nothing. The warm-MCS zero-allocation tests, AllocCheck and JET pass unchanged. Phases
receive the counters through `_run_phase(phase, …, stats)`, which defaults to the public
callable `phase(st, p, ctx, key, mcs, backend)`. `HostPhase`, Potts' `_AdaptiveODE` and the
`_Gated` wrapper add methods. Callable without an integrator, they count into `nothing`.

Not counted:
- device→device copies (`CopyPhase`, the `FieldStep` double buffer) and device `fill!`;
- implicit waits inside `Array(a)` (a blocking copy is one transfer, not a sync);
- user code: `DiscreteCallback`s, the `Lifecycle(rebuild! = …)` host hook, and the body of a
  `HostPhase` (it runs on host copies; the copies around it are counted).

Measurements:
- `/tmp/p60v/baseline.jl`: counters per MCS, wall time per MCS with an uncounted sync after
  each MCS, throughput over 400 MCS with one final sync, and the cost of each lifecycle
  piece.
- `/tmp/p60v/probe2.jl`: wall time per MCS segment, with a sync after each segment.
- `/tmp/p60v/probe3.jl`: Metal.jl device→device `copyto!` and `fill!` against a KA kernel;
  Merks with `FieldStep`'s copy replaced by a kernel; Akeeb in steady state (timed after its
  first event MCS has compiled the event kernels).
- `Metal.@device_code_llvm` over `init` plus 3 MCS: every kernel module of each gate model
  (§8).

All five gate models run at gate size, Float32, `CheckerboardCPM`: Graner–Glazier 72,
Wortel Act 100, Merks 100, OpenVT monolayer 100 and Akeeb 99×60.

Regression tests:
- `test/transfer_counts.jl` (Metal; ordinary, not frozen) pins the exact current counts of a
  division event MCS (2 syncs, 18 transfers, 1098 B) and of a `HostPhase` MCS (1 sync, 11
  transfers, 656 B). P6.0v1 and P6.0v2 update its formulas.
- The frozen `p6_0v_transfer_counters.jl` pins the long-term quiet-MCS targets.
- `test/transfer_counts.jl` also checks, on Metal, that every GPU wait of a quiet MCS is a
  counted one: waits = `syncs + 2 × transfers` (§2.1). Merks is `@test_broken` until P6.0v3
  removes its uncounted waits.
  - The same identity holds on the division fixture's event MCS (38 waits) and on a
    `HostPhase` MCS. Until P6.0v1, this is the runtime backstop for raw copies on the event
    path.
  - A Metal.jl version other than 1.10.0 fails the test with a message instead of skipping
    it.
- `test/qa.jl` "no raw host transfer outside the counted helpers":
  - It scans `lib/CorePotts/src` and `src` (except `transfers.jl`) for raw
    `<Module>.synchronize(`, `Array(`/`Base.Array(`/`Array{…}(`, `Vector(`/`Vector{…}(`,
    `Adapt.adapt(Array`, `convert(Array`, `copyto!(` and `unsafe_copyto!(`, and
    compares the hits with a `file => count` allowlist that gives a reason for each entry:
    Lattice `==`/`hash` and host-mask conversions, `initial_state`, `_standard_frozen` and
    `_set_state_array!` on host values, `reinit!`, the
    `FieldStep`/`CopyPhase` device→device copies (until P6.0v3), and the setup layouts.
  - A new `Array(st.σ)`, `Base.Array(st.σ)` or `unsafe_copyto!(…)` in `run_lifecycle!`
    makes it fail (checked).
  - `collect` and `copy` are left to the runtime wait-identity test.
- `lib/CorePotts/test/phases.jl` (CPU) and `lib/CorePotts/test/gpu.jl` (Metal) test the
  helpers themselves:
  - exact bytes for each direction;
  - device→device copies not counted;
  - one transfer per snapshot leaf and for a domain mask;
  - `merge` and `_restore_stats!`.

## 2. Baseline: host traffic and launches per MCS on Metal

400 MCS after 5 warm MCS. These are counter averages per MCS. "Launches" is
`stats.launches`, which does not count device `fill!`s; see §8.1 for those.

| gate model | quiet MCS: syncs / transfers / bytes | event MCS (count): syncs / transfers / bytes | launches quiet / event | MCS average: syncs / transfers / bytes |
|---|---|---|---|---|
| Graner–Glazier 72 | 0 / 0 / 0 | none | 8 / – | 0 / 0 / 0 |
| Wortel Act 100 | 0 / 0 / 0 | none | 33 / – | 0 / 0 / 0 |
| Merks 100 | 0 / 0 / 0 | none | 14 / – | 0 / 0 / 0 |
| OpenVT monolayer 100 | 1 / 1 / 4 B | none in 400 MCS (τ = 1e6) | 10 / – | 1 / 1 / 4 B |
| Akeeb 99×60 | 1 / 1 / 4 B | 31 of 400: 2 / 22 / 136 764 B | 14 / 17 | 1.08 / 2.63 / 10 603 B |

This baseline already meets the quiet-MCS targets of the frozen acceptance:
- **Gate models without a lifecycle make no counted transfer and no explicit sync**, because
  `CheckerboardCPM` reads its status word only at a save. Merks still waits for the GPU
  6 times per MCS inside Metal.jl's device→device `copyto!`, which D-085 does not count; see
  below.
- **On a lifecycle model, the trigger readback is the only sync and the only transfer of a
  quiet MCS** (§6).

All the remaining host traffic is on event MCS:
- Akeeb moves 137 kB per event MCS in 22 transfers.
- The division fixture moves 1098 B in 18 transfers.
- A `HostPhase` MCS moves 656 B in 11 transfers.

Akeeb's 136 764 B per event MCS, itemised (the counters sum to exactly this):

| piece | transfers | bytes | scales as |
|---|---|---|---|
| event-count readback | 1 | 4 | O(1) |
| plan: `events`, `volume` down | 2 | 8 000 | O(cells) |
| plan: `daughter`, `removed`, `events` up | 3 | 9 000 | O(cells) |
| `_copy_columns!`: `kind`, `V_target`, `clock`, `rate` down and up | 8 | 32 000 | O(cells × quantities) |
| `generation` round trip | 2 | 8 000 | O(cells) |
| `rebuild_trackers!`: `σ` down | 1 | 23 760 | O(sites) |
| `rebuild_trackers!`: `volume`, `anchor`, `m1`, `m2` up | 4 | 52 000 | O(cells × trackers) |
| empty-daughter count: `volume` down again | 1 | 4 000 | O(cells) |

Wall time on Metal, ns per site per MCS:

| gate model | quiet MCS (sync after each MCS, median) | throughput (400 MCS, one sync) | gate baseline (`baseline.toml`) | CPU checkerboard (gate) |
|---|---|---|---|---|
| Graner–Glazier 72 | 150 | 34 | 18.9 | 27.2 |
| Wortel Act 100 | 269 | 81 | 44.3 | 14.9 |
| Merks 100 | 284 | 291 (60 with F2, §8.1) | 183.8 | 93.4 |
| OpenVT monolayer 100 | 113 | 131 | 74.2 | 15.0 |
| Akeeb 99×60 | 372 (steady-state event MCS: median 1479) | 539 | 185.8 | 46.5 |

**How to read the gate's Metal column.** `benchmark/gate.jl` times `step!` without a final
synchronize:
- For a model with no wait in its MCS (Graner–Glazier, Wortel), it measures the host's
  enqueue time. That is why Graner–Glazier reads 18.9 there but 34 in throughput mode.
- For a lifecycle model, the trigger readback waits for the whole MCS, so the gate measures
  full latency. So does Merks, through its waiting copies.

The two groups are not comparable. ROADMAP row P6.0v7 (§9) fixes this.

### 2.1 Implicit waits the counters do not show

**Hidden syncs.** Merks makes no transfer and no explicit sync,
yet its throughput equals its latency (291 against 284). Metal.jl's device→device
`copyto!` drains the queue twice: it calls `synchronize()` before the blit and waits for the
blit (`async = false`, `Metal/src/array.jl:415`, `memory.jl:88-122`). Each `FieldStep`
substep ends with such a copy (`fields.jl:139`), so Merks waits for the GPU 6 times per MCS.
Measured (§8.1 F2):
- one Metal `copyto!(dev, dev)` of 10 000 Float32 costs 225 µs;
- a KA copy kernel costs 9 µs to enqueue and 14 µs to complete;
- **replacing the copy with a kernel takes Merks from 306 to 60 ns/site/MCS (5.1×),
  faster than the CPU (93).**

D-085 counts only explicit `synchronize` calls and treats device→device copies as free. So
the counters read 0 / 0 / 0 for Merks, the frozen target (a) holds, and this cost is
invisible to them. **Under the user's standard these waits are syncs.** Metal.jl waits for
the GPU in three places the counters miss:
- device→device `copyto!`, twice per copy;
- `UInt8`/`Int8` `fill!` (a waiting blit);
- conversions of a device array to a host pointer (`unsafe_copyto!` on pointers).

All of them go to **P6.0v3**, which now also carries P6.0v8's rule: no Metal.jl
device→device `copyto!` in the step path, with every device copy going through a CorePotts
kernel helper. `CopyPhase` (`phases.jl:110-113`) has the same cost wherever generated
code publishes a double buffer (buffered site updates, several ODE groups). Device `fill!` of
`Int32`/`Float32` is a GPUArrays kernel and does not wait (8–11 µs); only `UInt8`/`Int8`
fills use a waiting blit, and none runs in the step path.

**Measured GPU waits per quiet MCS.** `Metal.wait_cmdbuf!` was wrapped with a test-only
counter, and the in-flight back-pressure of `wait_oldest_cleanup!` (the host running ahead
of a busy GPU, which is not a sync) was excluded. Each counted sync is 1 wait and each
counted transfer is 2, so with no hidden waits the identity is waits = `syncs + 2 × transfers`:

| gate model | waits per quiet MCS | `syncs + 2 × transfers` |
|---|---|---|
| Graner–Glazier 72 | 0 | 0 |
| Wortel Act 100 | 0 | 0 |
| Merks 100 | **6** | 0 |
| OpenVT monolayer 100 | 3 | 3 |
| Akeeb 99×60 | 3 | 3 |

The stronger P6.0v8 test is now in `test/transfer_counts.jl` (§1). It asserts the identity
on every gate model. Merks is `@test_broken` and turns into an unexpected pass, so a failing
reminder, when P6.0v3 reaches 0 waits.

## 3. `refresh_frozen!` (P6.0d, final `feat/p6-0d` ee2331b, merged here)

P6.0d recomputes the frozen-kind mobility mask after a lifecycle event.
- **Round 2 (42a6593, the version named in the ROADMAP row).**
  - Standard rule: a device fill, one kernel over all sites, then a blocking
    `copyto!(host, device)` of 8 B on every event MCS of a model with `[frozen]` kinds.
  - Custom rule: a full snapshot, a host `remake_frozen`, and the mask copied up.
- **Final (ee2331b).**
  - The standard-rule kernel writes its two counts into entries 2–3 of the lifecycle's
    3-entry `count` (host mirror `LifecycleCache.host`).
  - The trigger read-back stays the D-035 read: `_sync!` and then 4 B
    (`_copy!(pstats, cache.host, 1, cache.count, 1, nread)` with `nread = 1`). It reads
    12 B (`nread = 3`) only on the lifecycle MCS after a refresh, while its counts are
    pending.
  - `fill!(cache.count, 0)` is enqueued **after** the read.
  - `solve!` and `checkpoint` end with `_flush_counts!`, one 12 B read, and only when
    counts are pending.
  - A direct `refresh_frozen!` (`set_state!` on `kind`, `u_modified!`, `reinit!`) reads its
    counts at once: one 12 B transfer, outside the MCS.

| # | site (merged) | fires | moves | necessary | device-side replacement | row |
|---|---|---|---|---|---|---|
| R1 | `problem.jl:463-479` standard-rule `_refresh_frozen!`: `_launch(_frozen_body!)` | event MCS, `[frozen]` models only | O(sites) device pass, no transfer of its own | yes (the mask must follow kinds) | already on the device; one launch on event MCS only | keep (justified) |
| R2 | `lifecycle.jl:287-290` `_sync!` + `_copy!(…, nread)` | every lifecycle MCS | 4 B; 12 B on the lifecycle MCS after a refresh | 4 B per D-035 (until D-089) | D-089: no read-back on a GPU backend. The pending counts are read only at saves, the end of `solve!` and `checkpoint`. | **P6.0v1 (D-089)** |
| R3 | `problem.jl:420-427` `_flush_counts!`; direct `refresh_frozen!` (`:473`) | end of run, checkpoint, user writes | 12 B | yes (exact `stats.attempts`) | – | keep (outside the MCS) |
| R4 | `problem.jl:481-488` custom-rule `_refresh_frozen!`: `_sync!`, `_snapshot`, host `frozen_sites`, `_set_mobility!` (`lattice.jl`) up | event MCS of a custom-rule model (none published; Potts uses the standard rule) | O(sites + cells × quantities) down, O(sites) up | only the columns the rule reads | copy only the columns the rule declares | P6.0v2 |

All of these copies go through the counted helpers, as of the merge commit. With the merge,
the frozen target (b) still reads exactly 1 sync / 1 transfer / 4 B on OpenVT, Akeeb and the
division fixture (re-run on Metal).

## 4. `_AdaptiveODE` (`src/codegen.jl:591-649`)

This is the phase of `ode_solver = Adaptive(alg)`: a host SciML integrator per live cell
(or one for model scope), on every MCS. No gate model uses it.

| # | site | fires | moves | necessary | device-side replacement | row |
|---|---|---|---|---|---|---|
| A1 | `:595` `_sync!` | every MCS it runs | – | yes while the solve is on the host | – | P6.0v2 (stays with the host solve) |
| A2 | `:598` `_snapshot(stats, backend, st)` | every MCS | O(sites + cells × quantities): σ, every cell, site, model and history leaf | **no**: needs only the ODE columns, the columns its rates read, and `volume` | copy those columns only (the compiler knows the rate's reads) | **P6.0v2** |
| A3 | `:599` `_adapt_host(stats, p)` | every MCS | device arrays in `p` (tables), O(1) in practice | partly: only if a rate reads them | copy once at init; parameters are immutable within a run except through `set_parameter!` | P6.0v2 |
| A4 | `:600` `host_lattice(stats, ctx.lattice)` | every MCS on a masked lattice | O(sites) Bool | **no**: the domain mask never changes | cache the host lattice in the integrator once | P6.0v2 |
| A5 | `:621-641` host loop over cells, one adaptive solve each | every MCS | host O(cells) solves | yes for SciML's host solvers | a device adaptive ensemble kernel (DiffEqGPU `GPUTsit5` style) | proposed P6.0v5 (optional) |
| A6 | `:644-647` `_copy!` of `ph.outs` | every MCS | O(cells × ODE columns) up | yes while the solve is on the host (already column-only) | – | keep |

## 5. `HostPhase` (`lib/CorePotts/src/relationships.jl:222-235`) and the `@link` phases

A `HostPhase` runs on the host every `every` MCS. Potts generates one per `@link`/`@unlink`
rule (`src/codegen.jl:818-855`). No gate model has one.

| # | site | fires | moves | necessary | device-side replacement | row |
|---|---|---|---|---|---|---|
| H1 | `:227` `_sync!` | every `every` MCS | – | yes while the body runs on the host | – | P6.0v2 |
| H2 | `:228` `_snapshot` | every `every` MCS | O(sites + cells × quantities) down | **no**: the generated `@link` bodies read `σ`, `volume`, `kind`, `anchor`, `m1` (centroids) and the adjacency and payload columns | copy only the declared columns. `HostPhase` gains a `reads`/`writes` declaration; Potts fills it in. | **P6.0v2** |
| H3 | `:229` `host_lattice` | every `every` MCS on a masked lattice | O(sites) Bool | **no** (the mask is static) | cache once | P6.0v2 |
| H4 | `:230-232` `_copy!` of **every** cell column up | every `every` MCS | O(cells × quantities) | **no**: only the adjacency and payloads change | copy the written columns only | **P6.0v2** |
| H5 | generated `@link` body: `CorePotts.contact_graph(st.σ, …)` (`spatial.jl:98`) and loops over cells | every `every` MCS | host O(sites) work on the downloaded σ | yes while links are made on the host | device contact-graph kernel (site pairs → sort/unique), with link creation on the device | proposed P6.0v5 (optional; "rare by design") |

The `HostPhase` fixture of `test/transfer_counts.jl` (two cells; σ, `kind`, `volume`,
`generation`, `x`, `y`) costs 1 sync / 11 transfers / 656 B per MCS: σ plus 5 columns down,
then 5 columns up. With H2 and H4, a body that reads `x` and writes `y` moves 2 columns.

## 6. The lifecycle trigger readback (`lifecycle.jl:285-292`): the only sync on a quiet MCS

```julia
_launch(_trigger_body!, backend, cap, (…))                          # :285 trigger kernel
_sync!(pstats, backend)                                             # :287
_copy!(pstats, cache.host, 1, cache.count, 1, nread)                # :290 4 B (12 B while P6.0d counts pend)
fill!(cache.count, Int32(0))                                        # :291 device fill, after the read
cache.host[1] == 0 && return launches, false, true                  # :292
```

**Confirmed: this is the only sync and the only transfer of a quiet MCS.**
- By counters: a quiet MCS is exactly 1 / 1 / 4 B on OpenVT, Akeeb and the division fixture
  (frozen file, testset (b)), and 0 / 0 / 0 on Graner–Glazier, Wortel and Merks. Merks
  also has the uncounted waits inside Metal's device→device `copyto!` (§2; F2).
- By reading the step path (`problem.jl:355-394`), the rest of a quiet MCS makes no other
  host↔device copy:
  - `_color_order!` and `cache.buffer[]` are host values;
  - `stats.attempts` uses the host count `nmobile`;
  - `HistoryPush` checks shapes on the host;
  - `_check_status!` runs only at saves.

| # | site | fires | moves | necessary | device-side replacement | row |
|---|---|---|---|---|---|---|
| T1 | `:287` `_sync!` | every lifecycle MCS | – | today the host decides whether to run the event path (D-035; frozen target (b)) | D-089: plan and apply the lifecycle on the device; no host decision, no sync | **P6.0v1 (D-089)** |
| T2 | `:290` `_copy!` of `count` (4 B) | every lifecycle MCS | 4 B (12 B while P6.0d counts pend) | not under D-089 | D-089: no read-back. Counts and `stats.lifecycle` are read at saves, the end of `solve!` and `checkpoint`. Until then, a shared-storage `count` would cut the read from 150–220 µs to 0.3 µs (P6.0v4). | **P6.0v1 (D-089)**; P6.0v4 for the remaining host reads |
| T3 | `:291` `fill!(cache.count, 0)` (after the read since P6.0d) | every lifecycle MCS | device fill, an extra GPU command not in `stats.launches` | no | reset in the trigger kernel (double-buffered count indexed by MCS parity), or fold into the fused per-cell kernel (§8.1 F1) | P6.0v3 |

## 7. The lifecycle on an event MCS (`lifecycle.jl:279-413`)

### 7.1 What it costs: Akeeb on Metal

Akeeb runs at 185 ns/site on Metal in the gate against 47 on the CPU. The gate's minimum
is a quiet MCS, so it measures the quiet path; the event path comes on top of it in a run.

Steady state (`/tmp/p60v/probe3.jl`, 600 MCS from MCS 288, after the first event MCS has
compiled the event kernels):
- event MCS are 100 of 600 (17 %) but take **44 % of the wall time**;
- an event MCS costs 1479 ns/site (8.8 ms) median, 4× a quiet MCS;
- a quiet MCS costs 372 ns/site (2.2 ms) median.

If an event MCS cost no more than a quiet one, Akeeb on Metal would be about 33 % faster.

The first event MCS of a process also compiles the normal, partition and cell-rule kernels:
about 0.8 s, measured in `probe2.jl`. That one-time cost inflated the mean of the 400-MCS
`baseline.jl` run to 5663 ns/site per event MCS (median 1399) and its event share to 56 %.

Cost of each host piece on the live Akeeb device state (minimum of 20, µs):

| piece | µs |
|---|---|
| `rebuild_trackers!` (σ down, host O(sites) recompute, 4 columns up) | 1353 |
| full `_snapshot` (all leaves) | 2467 |
| every cell column down and up (9 columns, 18 transfers) | 3922 |
| one 4-byte private-storage readback (`Array(a)[1]`) | 151–222 (min–median) |
| the same scalar in shared storage, read after the sync | 0.3 |
| `synchronize` with an idle queue | 0.5 |

Each private-storage transfer costs about 200 µs on this machine, whatever its size: the
latency of a blit command buffer plus its wait. An event MCS makes 22 of them, about 4.4 ms
before any host work. That is what P6.0v1 removes.

Per-segment medians, µs (`/tmp/p60v/probe2.jl`, sync after each segment):

| gate model | sweep (+ `before_mcs`) | `after_mcs` phases | lifecycle (quiet) | `end_mcs` |
|---|---|---|---|---|
| Graner–Glazier 72 | 769 | 1 | – | 0 |
| Wortel Act 100 | 2277 | 250 | – | 0 |
| Merks 100 | 1513 | **1736** (`FieldStep`: 3 kernels + 3 waiting copies) | – | 0 |
| OpenVT monolayer 100 | 837 | 252 | **533** | 0 |
| Akeeb 99×60 | 1706 | 404 | **674** | 0 |

Each segment includes one wait for the GPU. On a quiet MCS the lifecycle segment (fill,
trigger kernel, sync and a 4 B private-storage readback) costs 533–674 µs. That is 33 % of
OpenVT's MCS and 24 % of Akeeb's. Under D-089 all of it goes (T1, T2, P6.0v1); only the
trigger kernel stays.

### 7.2 Entries

"Cells" means the capacity (Akeeb: 1000 slots). Every entry fires on event MCS only, unless
stated.

| # | site | moves | necessary | device-side replacement | row |
|---|---|---|---|---|---|
| L1 | `:295` `events = _to_host(cache.events)` | O(cells) Int32 | the **events** yes; the full array no | the trigger appends `(c, event)` to a compacted device list with an atomic counter; the host downloads `count` entries | P6.0v1 |
| L2 | `:298` `volume` down (free slots) | O(cells) | no | the device keeps a free-slot list, or a prefix scan over `volume == 0` assigns daughters | P6.0v1 |
| L3 | `:300` `cluster` down (`held`, cluster models) | O(cells) | no | device flag "id still named by a live member" | P6.0v1 |
| L4 | `:308` `cluster` down **again** | O(cells) | **no: duplicate of L3's copy** | reuse L3's host array (trivial, even before P6.0v1) | P6.0v1 |
| L5 | `:301-353` host plan loops over all slots (free list, cluster members, deferral) | host O(cells) | the sequential parts (cluster precedence, deferral order) yes | plain divisions and removals: device scan. Cluster divisions: host plan over the compacted O(events) list. | P6.0v1 |
| L6 | `:355-357` `daughter`, `removed`, `events` up | O(cells) | no | the device plan writes them in place, or the host uploads O(events) | P6.0v1 |
| L7 | `:362` `_cluster_planes!` (`compartments.jl:193-224`): σ, `cluster`, `generation`, `kind`, `volume`, `anchor`, `m1` down; host `init_moments` over all sites; `normals`, `bias` up | O(sites) + O(cells × 7) down, O(cells) up | the planes yes; host moments no | per-cluster moment reduction on the device (`CellReduce`-style), plane kernel per dividing root | P6.0v1 |
| L8 | `:360` `fill!(cache.bias, 0)` | device fill (extra command) | no | fold into the normal kernel | P6.0v1 |
| L9 | `:365`, `:370`, `:402` normal, partition and cell-rule kernels | device, 3 launches | yes | fuse normal + cell rule into one per-cell kernel before the partition (§8.1 F4) | P6.0v1 |
| L10 | `:375-383` `_copy_columns!` (`:416-427`) for every non-tracker cell column | **O(cells × quantities)**, 2 transfers per column (Akeeb: 8, 32 kB) | no | one device kernel over daughters copying every non-tracker column parent → daughter (static unroll over the state NamedTuple) | **P6.0v1** |
| L11 | `:384-386` `generation` round trip | O(cells), 2 transfers | no | same kernel (`generation[d] = generation[parent] + 1`) | P6.0v1 |
| L12 | `:388-397` `cluster` round trip | O(cells), 2 transfers | no | same kernel | P6.0v1 |
| L13 | `:400-401` `_lifecycle_links!` (`:486-498`): every adjacency down and up | O(cells × degree × relationships) | no | device kernel: `remove_incident!` for removed cells and daughters | P6.0v1 |
| L14 | `:406` `_fix_clusters!` (`compartments.jl:172-177`): `cluster`, **σ**, `kind` down; `cluster` up; host `_normalize_clusters!` | O(sites) + O(cells) | the re-rooting yes; host σ no | liveness from `volume` (exact after the device tracker update) rather than from σ; re-root kernel | P6.0v1 |
| L15 | `:407` `_rebuild_trackers!` (`:439-459`): **sync**, **σ down**, host O(sites) recompute of `volume`, `surface`, `anchor`/`m1`/`m2`; 4–5 columns up; cluster trackers (`compartments.jl:179-188`); host mask | **O(sites)** + O(cells × trackers), 1 sync | no | update trackers in the partition kernel: each moved site does the same atomic tracker deltas as an accepted copy (exact integer moments); the daughter's anchor starts as the parent's; removed cells are zeroed | **P6.0v1** |
| L16 | `:408` `lc.rebuild!` user host hook | user code (not counted) | – | Potts passes the no-op | justified (user hook, documented) |
| L17 | `:410-411` `volume` down again (empty daughters) | O(cells) | no | count empty daughters on the device in the tracker update; until then, reuse L15's host `volume` | P6.0v1 |

Under D-089, P6.0v1 plans and applies all of this on the device. An event MCS then has no
host transfer at all, except where a host-planned case remains (cluster divisions, if they
stay on the host), which moves O(events).

Its bytes are then independent of the lattice size and of the number of cell quantities
(the P6.0v1 acceptance).

## 8. Codegen quality on Metal

### 8.1 Kernel launches per MCS and fusion

| gate model | launches per quiet MCS | breakdown | uncounted device commands |
|---|---|---|---|
| Graner–Glazier 72 | 8 | 4 colors × (propose + commit) | – |
| Wortel Act 100 | 33 | 16 colors × 2 + `act` decay `SitePhase` | – |
| Merks 100 | 14 | 4 colors × 2 + `FieldStep` 3 substeps × (kernel + `copyto!` blit) | – |
| OpenVT monolayer 100 | 10 | 4 colors × 2 + `V_target` growth `CellPhase` + trigger | `fill!(count)` |
| Akeeb 99×60 | 14 (event 17) | 6 colors × 2 + `@after_mcs` `CellPhase` + trigger (+ normal, partition, cell rule) | `fill!(count)` (+ `fill!(bias)`) |

Throughput mode makes Graner–Glazier and Wortel launch-bound:
- Graner–Glazier: 34 ns/site × 5184 sites ≈ 176 µs per MCS, about 22 µs per launch;
- Wortel: 33 launches ≈ 810 µs per MCS.

Each removed launch saves about 20 µs per MCS on this machine.

| # | fusion | saves per MCS | legality | row |
|---|---|---|---|---|
| F1 | lifecycle models: the `after_mcs` `CellPhase`, the `fill!(count)` and the trigger kernel into one per-cell kernel | 2 commands (OpenVT 11 → 9, Akeeb 15 → 13) | the trigger of cell `c` must read only cell-local values the phase writes, plus values it does not write. The compiler knows both. Otherwise keep them apart. | P6.0v3 |
| F2 | `FieldStep` (`fields.jl:139`): replace Metal's waiting `copyto!(c, cn)` with a KA copy kernel (`_launch`), or ping-pong the field and its scratch | 2 hidden queue drains per substep (Merks: 6 per MCS). **Measured: Merks 306 → 60 ns/site/MCS with the kernel copy.** | exact (same values). A ping-pong also saves the copy kernel, but odd substep counts need a final copy. | **P6.0v3, first item** (small; can land alone) |
| F3 | `CopyPhase` (`phases.jl:110-113`): the same kernel copy, or swap buffers | 2 hidden drains per published array per MCS | exact. A swap needs a parity-indexed pair, because generated code reads `x__next` by name. | P6.0v3 |
| F4 | event MCS: normal + cell-rule kernels into one per-cell kernel before the partition | 1 launch per event MCS | `_cell_rule_body!` reads no σ-derived tracker that the partition changes (trackers are rebuilt afterwards) | P6.0v1 |
| F5 | propose + commit of a color, or several colors, in one kernel | – | **not legal.** Commit needs every proposal of the color (claims). Metal has no grid-wide barrier, and persistent-thread spin barriers have no forward-progress guarantee. The footprint fixes the color count (Wortel: stride 4 → 16 colors). | unavoidable (justified) |
| F6 | Wortel `act` decay `SitePhase` (every site, every MCS) | 1 launch | necessary under the model as written. A lazy decay (store the MCS of the last touch, decay on read) would remove the pass; that is a model reformulation, not a codegen fix. | not assigned (noted) |

### 8.2 Float64 in Float32 kernels

**None found.** All kernel modules of the five gate models (34 kernel definitions: propose,
commit, phases, trigger, normal, partition, cell rule, fills) contain no `double` type and no
`fpext`/`fptrunc` (`/tmp/p60v/out/llvm_*.ll`, scanned). Metal.jl rejects device Float64 at
compile time, so a leak would fail loudly.

A related 64-bit cost: the moment trackers `m1` and `m2` are `Int64` (exact integer moments,
`geometry.jl:53-54`). Every accepted copy of a model with moments (Merks, OpenVT, Akeeb) does
64-bit integer arithmetic, which Apple GPUs emulate. Int32 moments would be exact under
bounds that do not depend on the capacity: |offset| ≤ dims and `V·max(dims)² < 2^31`. Akeeb 99×60 at
V ≤ 100 is far inside them; the 500×300 production lattice at V up to 1e4 is not. This needs
a measured A/B before any change. Listed under P6.0v3 as "investigate".

### 8.3 Dynamic dispatch, allocations, boxed values, exception branches

- **No dynamic dispatch, allocation or boxing in device code.** Kernel modules contain no
  `jl_*`, `gc_pool`, `gpu_malloc` or `jl_box` calls (Metal would reject them too).
- **Exception branches.** All of them are compiled checked conversions or bounds checks that
  cannot fire in a valid run. They add a compare and branch, plus the signal path, in hot
  kernels.

| # | source | throw | kernels | fix | row |
|---|---|---|---|---|---|
| X1 | `lib/CorePotts/src/rng.jl:80` `draw`: `UInt32(mcs)`, `UInt32(entity)`, `UInt32(local_index)` | `InexactError` (checked trunc / sign) | propose, every phase that draws (2–3 per module) | `% UInt32` (wrapping; values are in range by construction) | P6.0v3 |
| X2 | `checkerboard.jl:81` `UInt32(j)` | `InexactError` | propose | `j % UInt32` | P6.0v3 |
| X3 | `checkerboard.jl:43` `_claim!`, `:78`; `lifecycle.jl:179` `_trigger_body!`: `Atomix.@atomic` on arrays | `BoundsError` | propose, commit, trigger | `@inbounds` with the bounds argument beside it (ids < capacity; claims sized by capacity) | P6.0v3 |
| X4 | Metal `setindex!` `convert` (`checked_trunc_sint`): Int64 values written into Int32 arrays (tracker and id writes) | `InexactError` | commit, cell phase (5 sites in Merks, OpenVT, Akeeb) | typed literals and `% Int32` at the writes | P6.0v3 |
| X5 | `drives.jl:175`, `:193`; `phases.jl:57` (`Int32(c)`); `lifecycle.jl:176` (`Int32(trigger(…))`) | `InexactError` | propose (connectivity), cell phases, trigger | `% Int32` | P6.0v3 |

### 8.4 Redundant per-MCS passes over all sites

| # | pass | gate models affected | verdict | row |
|---|---|---|---|---|
| P1 | P6.0t: the start-of-after integral refresh, and observed-only integrals refreshed in `end_mcs` | none (no gate model has integrals) | waste wherever integrals exist (one `CellReduce` over all sites each) | P6.0t (P6.0v3 absorbs it if not done first) |
| P2 | `_rebuild_trackers!` host O(sites) recompute (L15) | Akeeb, OpenVT, the division fixture (event MCS) | redundant: the partition kernel knows every moved site | P6.0v1 |
| P3 | `_fix_clusters!` and `_cluster_planes!` σ downloads and host passes (L7, L14) | cluster models (event MCS) | redundant | P6.0v1 |
| P4 | P6.0d `_frozen_body!` over all sites (R1) | `[frozen]` models (event MCS) | acceptable: one device pass per event MCS | keep |
| P5 | Wortel `act` decay (F6), Merks field substeps | Wortel, Merks | required by the models | keep |

**Merks is slower on Metal than on the CPU** (291 ns/site in throughput against 93), and
the cause is not GPU work. Its `after_mcs` segment (the field step, 1736 µs) costs more than
its sweep (1513 µs), because each of the 3 substeps ends with a waiting Metal `copyto!`.
With a kernel copy it runs at 60 ns/site (F2).

## 9. Proposed rows (status after D-089)

- **P6.0v4: shared-storage scalars for host reads on unified memory.** Filed in the ROADMAP.
  - Change: allocate the device buffers the host reads in `Metal.SharedStorage` and read
    them with a load after the sync instead of `Array(a)`. Under D-089 these are the
    status word, the lifecycle and P6.0d counts read at saves, `solve!` end and `checkpoint`,
    and any O(events) list a host-planned case needs.
  - Measured: 150–220 µs → 0.3 µs per read.
  - Each read is still counted as 1 transfer.
- **P6.0v5 (optional) device-resident host phases.** Filed in the ROADMAP.
  - Adaptive ODEs through a device adaptive ensemble kernel.
  - `@link`/`@unlink` through a device contact graph (A5, H5).
- **P6.0v6 → D-089.** The user chose the device-side form: no trigger read-back on a GPU
  backend. It is built by P6.0v1, which re-freezes target (b) to 0 / 0 / 0.
- **P6.0v7 (tooling) the gate measures GPU completion.** Filed in the ROADMAP (§2).
- **P6.0v8 → folded into P6.0v3.**
  - The rule: no Metal.jl device→device `copyto!` or `UInt8`/`Int8` `fill!` in the step
    path.
  - The test: waits = `syncs + 2 × transfers` per quiet MCS, already in
    `test/transfer_counts.jl` with Merks `@test_broken`.

## 10. Assignment summary

| row | entries |
|---|---|
| P6.0v1 (with D-089) | T1, T2, R2; L1–L15, L17; F4; P2, P3 |
| P6.0v2 | A1–A4; H1–H4; R4 |
| P6.0v3 (with P6.0v8) | F2 first (measured 5.1× on Merks), F3 and the other implicit waits (§2.1); T3; F1; X1–X5; Int64-moment investigation (§8.2); P6.0t if still open |
| P6.0v4 (ROADMAP) | the host reads that remain under D-089 (status word; counts at saves, `solve!` end, `checkpoint`) |
| P6.0v5 (ROADMAP, optional) | A5, H5 |
| P6.0v7 (ROADMAP) | gate semantics (§2) |
| unavoidable or kept (justified) | F5 (no grid barrier); A6 (column-only already); R1, R3; L16 (user hook); P4, P5; outside the MCS: saves and `integ.u` (`problem.jl:331-334`: sync and snapshot, the user asked for the state), `_check_status!` at saves (`:348-353`, 4 B), `checkpoint` (`checkpoint.jl:26-31`), `reinit!` (`:63`, setup; the counters are reset after it), `set_state!` (`problem.jl:667-673`, 1 sync and 1 upload per user write, plus P6.0d's refresh on `kind`), model-scope `getindex(st, ::StateIndex)` (`problem.jl:637-640`, a user read through `_to_host(nothing, …)`, not counted), `_standard_frozen` on host states (problem construction, `remake`, `frozen_sites`), `init` uploads, `src/layouts.jl:241,419` and `src/problem.jl:419` (setup, host), `Lattice` `==`/`hash` (`lattice.jl:79-80`, host utility) |

## 11. Status after P6.0v1 (D-089, D-096)

The lifecycle runs on the device on every GPU backend (`lib/CorePotts/src/lifecycle_device.jl`);
the CPU keeps the host plan of §6–7 unchanged.

- **Quiet lifecycle MCS:** 0 syncs / 0 transfers / 0 B and no Metal wait (was 1 / 1 / 4 B
  and two waits: T1, T2, R2). T3 is gone with it (no `fill!` of the count: the event flag is
  double-buffered by round parity and reset by the planner).
- **Event MCS:** 0 / 0 / 0 for every event kind, cluster divisions and link updates
  included (was (2, 18, 1098 B) on the 16×8 division fixture, O(sites + cells ×
  quantities)): L1–L15 and L17 are device kernels.
  - Plan: one workgroup of 256 items; daughter ids by prefix scans over the slots (no
    atomics-order dependence); clusters by the D-035 greedy pass only when capacity runs out.
  - Trackers: the partition kernel accumulates each daughter's volume and moment sums in
    `Int32` scratch about the parent's anchor (exact while the parent's own second moments
    fit in `Int32`, far above any cell size in use; the planner checks it and a larger cell
    raises an error at the next read point); surfaces change only for parents and
    daughters (one site kernel); cluster trackers are recounted on event rounds only.
  - Cluster planes: the root's work item sums its members' exact moments (O(capacity) per
    dividing cluster, on event rounds only).
- **Launches:** a quiet lifecycle MCS enqueues 5 launches (trigger, plan, partition,
  cells, finalize), +1 with a surface tracker, +2–4 with clusters, +2 with frozen kinds;
  every work item after the trigger returns at once on a quiet round.
- **Read points:** `stats.lifecycle`, `stats.attempts` (P6.0d) and `stats.refreshes` are
  folded at `current_state` (saves, `integ.u`, `checkpoint`), the end of `solve!`, a
  direct `refresh_frozen!` and `reinit!`: one transfer of 24 B, plus 24 B for models with
  frozen kinds. The deferral warning is emitted there.
- **Kept on the host:** a `Lifecycle` with a `rebuild!` hook (L16) or a custom
  `remake_frozen` rule (R4) is planned on the host as before, because the hook is host code.
