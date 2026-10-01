# GPU host-transfer audit (P6.0v)

2026-10-01, ROADMAP P6.0v, D-085. The goal (user): every synchronize, host↔device copy or
host-side work during a Metal MCS is either unavoidable or removed. This document is the
audit and the measured baseline. The removals are P6.0v1–P6.0v3 (ROADMAP) plus the rows
proposed in §9. Line numbers are at `feat/p6-0v` (1554d56 + P6.0v). The P6.0d mask refresh
is audited at `feat/p6-0d` 87a6e5b (round 3), which merges first (§3).

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

The two groups are not comparable. Proposed row P6.0v7 (§9) fixes this.

**Hidden syncs the counters do not show.** Merks makes no transfer and no explicit sync,
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
invisible to them. `CopyPhase` (`phases.jl:110-113`) has the same cost wherever generated
code publishes a double buffer (buffered site updates, several ODE groups). Device `fill!` of
`Int32`/`Float32` is a GPUArrays kernel and does not wait (8–11 µs); only `UInt8`/`Int8`
fills use a waiting blit, and none runs in the step path.

## 3. `refresh_frozen!` (P6.0d, `feat/p6-0d` 87a6e5b)

P6.0d recomputes the frozen-kind mobility mask after a lifecycle event. Three versions:

- **Round 2 (42a6593, the version named in the ROADMAP row).**
  - Standard rule: a device fill, one kernel over all sites, then a blocking
    `copyto!(host, device)` of 8 B on every event MCS of a model with `[frozen]` kinds.
  - Custom rule: a full `_snapshot`, a host `remake_frozen`, and the mask copied up.
- **Round 3 (87a6e5b, merging before P6.0v).**
  - The standard-rule kernel writes its two counts into entries 2–3 of the lifecycle's
    `count`, which grows to 3 `Int32` with a host mirror `LifecycleCache.host`.
  - The counts travel with the next lifecycle readback, so a refresh after an event MCS has
    no transfer of its own.
  - `solve!` ends with `_flush_counts!`: one 12 B read, only when counts are pending.
  - A direct `refresh_frozen!` (`set_state!` on `kind`, `u_modified!`, `reinit!`) reads its
    counts at once: one 12 B transfer, outside the MCS.

| # | site (87a6e5b) | fires | moves | necessary | device-side replacement | row |
|---|---|---|---|---|---|---|
| R1 | `problem.jl` `_refresh_frozen!(…, kinds::Tuple, defer)`: `_launch(_frozen_body!)` | event MCS, `[frozen]` models only | O(sites) device pass, no transfer | yes (the mask must follow kinds) | already on the device. It could visit only the sites of cells whose kind changed, but it runs on event MCS only and costs one launch. | keep (justified) |
| R2 | `lifecycle.jl` `run_lifecycle!`: `copyto!(cache.host, cache.count)` | **every lifecycle MCS** | **12 B** (3 × Int32) | 4 B yes (D-035); the other 8 B only for `[frozen]` models | size `count` by need: 1 entry when `frozen_varies` is false, 3 otherwise | **merge (see below)** |
| R3 | `_flush_counts!` at `solve!` end, and direct `refresh_frozen!` | end of run; user writes | 12 B | yes (exact `stats.attempts`) | – | keep (outside the MCS) |
| R4 | `_refresh_frozen!(…, ::Nothing, …)` (custom rule): `synchronize`, `_snapshot`, host `frozen_sites`, `copyto!(m.frozen, …)` | event MCS of a custom-rule model (none published; Potts uses the standard rule) | O(sites + cells × quantities) down, O(sites) up | only `σ` and `kind` are read by the standard shape of a rule | copy only the columns the rule declares | P6.0v2 |

**Merge note for the coordinator (frozen target (b)).** At 87a6e5b the quiet-MCS readback is
`copyto!(cache.host, cache.count)`, 12 B, with no explicit `synchronize` before it. Merged
naively into P6.0v's counting, a quiet lifecycle MCS reads 0 syncs / 1 transfer / 12 B
(implicit wait), while the frozen file asserts exactly 1 / 1 / 4 B for OpenVT, Akeeb and the
division fixture (none of which has frozen kinds). The reconciliation that keeps both
decisions:
- route the readback through `_sync!(pstats, backend)` then `_copy!(pstats, cache.host, cache.count)`;
- allocate `count` with 1 entry when the model's mask does not vary and 3 when it does.

Then a quiet MCS is 1 / 1 / 4 B without frozen kinds and 1 / 1 / 12 B with them. That is
still O(1), and no gate model has frozen kinds. The other P6.0d copies must use the counted
helpers at merge: `_flush_counts!`, the direct `refresh_frozen!` and the R4 snapshot.

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

## 6. The lifecycle trigger readback (`lifecycle.jl:277-281`): the only sync on a quiet MCS

```julia
fill!(cache.count, Int32(0))                                     # :277 device fill
_launch(_trigger_body!, backend, cap, (…))                      # :278 trigger kernel
_sync!(pstats, backend)                                         # :280
_readback(pstats, cache.count) == 0 && return launches          # :281 4 B, Array(count)[1]
```

**Confirmed: this is the only sync and the only transfer of a quiet MCS.**
- By counters: a quiet MCS is exactly 1 / 1 / 4 B on OpenVT, Akeeb and the division fixture
  (frozen file, testset (b)), and 0 / 0 / 0 on Graner–Glazier, Wortel and Merks. Merks
  also has the uncounted waits inside Metal's device→device `copyto!` (§2; F2).
- By reading the step path (`problem.jl:282-311`), the rest of a quiet MCS makes no other
  host↔device copy:
  - `_color_order!` and `cache.buffer[]` are host values;
  - `stats.attempts` uses the host count `nmobile`;
  - `HistoryPush` checks shapes on the host;
  - `_check_status!` runs only at saves.

| # | site | fires | moves | necessary | device-side replacement | row |
|---|---|---|---|---|---|---|
| T1 | `:280` `_sync!` | every lifecycle MCS | – | yes: the host decides whether to run the event path (D-035; frozen target (b)) | sync-free deferred readback (proposed P6.0v6, needs a decision) | justified (D-035) |
| T2 | `:281` `_readback` (`Array(count)[1]`) | every lifecycle MCS | 4 B | the value yes; the **copy** no | allocate `count` (and the other host-read scalars) in shared storage on unified-memory devices. The read becomes a load after the sync: 0.3 µs instead of 150–220 µs (measured, §7). Still counted as 1 transfer (the frozen target is unchanged). | proposed **P6.0v4** |
| T3 | `:277` `fill!(cache.count, 0)` | every lifecycle MCS | device fill, an extra GPU command not in `stats.launches` | no | reset in the trigger kernel (double-buffered count indexed by MCS parity), or fold into the fused per-cell kernel (§8.1 F1) | P6.0v3 |

## 7. The lifecycle on an event MCS (`lifecycle.jl:273-402`)

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
OpenVT's MCS and 24 % of Akeeb's: the sync is needed (D-035), but the readback round trip of
about 200 µs is not (T2, P6.0v4).

### 7.2 Entries

"Cells" means the capacity (Akeeb: 1000 slots). Every entry fires on event MCS only, unless
stated.

| # | site | moves | necessary | device-side replacement | row |
|---|---|---|---|---|---|
| L1 | `:284` `events = _to_host(cache.events)` | O(cells) Int32 | the **events** yes; the full array no | the trigger appends `(c, event)` to a compacted device list with an atomic counter; the host downloads `count` entries | P6.0v1 |
| L2 | `:287` `volume` down (free slots) | O(cells) | no | the device keeps a free-slot list, or a prefix scan over `volume == 0` assigns daughters | P6.0v1 |
| L3 | `:289` `cluster` down (`held`, cluster models) | O(cells) | no | device flag "id still named by a live member" | P6.0v1 |
| L4 | `:297` `cluster` down **again** | O(cells) | **no: duplicate of L3's copy** | reuse L3's host array (trivial, even before P6.0v1) | P6.0v1 |
| L5 | `:290-342` host plan loops over all slots (free list, cluster members, deferral) | host O(cells) | the sequential parts (cluster precedence, deferral order) yes | plain divisions and removals: device scan. Cluster divisions: host plan over the compacted O(events) list. | P6.0v1 |
| L6 | `:344-346` `daughter`, `removed`, `events` up | O(cells) | no | the device plan writes them in place, or the host uploads O(events) | P6.0v1 |
| L7 | `:351` `_cluster_planes!` (`compartments.jl:193-224`): σ, `cluster`, `generation`, `kind`, `volume`, `anchor`, `m1` down; host `init_moments` over all sites; `normals`, `bias` up | O(sites) + O(cells × 7) down, O(cells) up | the planes yes; host moments no | per-cluster moment reduction on the device (`CellReduce`-style), plane kernel per dividing root | P6.0v1 |
| L8 | `:349` `fill!(cache.bias, 0)` | device fill (extra command) | no | fold into the normal kernel | P6.0v1 |
| L9 | `:354`, `:359`, `:391` normal, partition and cell-rule kernels | device, 3 launches | yes | fuse normal + cell rule into one per-cell kernel before the partition (§8.1 F4) | P6.0v1 |
| L10 | `:364-372` `_copy_columns!` (`:404-415`) for every non-tracker cell column | **O(cells × quantities)**, 2 transfers per column (Akeeb: 8, 32 kB) | no | one device kernel over daughters copying every non-tracker column parent → daughter (static unroll over the state NamedTuple) | **P6.0v1** |
| L11 | `:373-375` `generation` round trip | O(cells), 2 transfers | no | same kernel (`generation[d] = generation[parent] + 1`) | P6.0v1 |
| L12 | `:377-386` `cluster` round trip | O(cells), 2 transfers | no | same kernel | P6.0v1 |
| L13 | `:389-390` `_lifecycle_links!` (`:474-486`): every adjacency down and up | O(cells × degree × relationships) | no | device kernel: `remove_incident!` for removed cells and daughters | P6.0v1 |
| L14 | `:395` `_fix_clusters!` (`compartments.jl:172-177`): `cluster`, **σ**, `kind` down; `cluster` up; host `_normalize_clusters!` | O(sites) + O(cells) | the re-rooting yes; host σ no | liveness from `volume` (exact after the device tracker update) rather than from σ; re-root kernel | P6.0v1 |
| L15 | `:396` `_rebuild_trackers!` (`:428-448`): **sync**, **σ down**, host O(sites) recompute of `volume`, `surface`, `anchor`/`m1`/`m2`; 4–5 columns up; cluster trackers (`compartments.jl:179-188`); host mask | **O(sites)** + O(cells × trackers), 1 sync | no | update trackers in the partition kernel: each moved site does the same atomic tracker deltas as an accepted copy (exact integer moments); the daughter's anchor starts as the parent's; removed cells are zeroed | **P6.0v1** |
| L16 | `:397` `lc.rebuild!` user host hook | user code (not counted) | – | Potts passes the no-op | justified (user hook, documented) |
| L17 | `:399-400` `volume` down again (empty daughters) | O(cells) | no | count empty daughters on the device in the tracker update; until then, reuse L15's host `volume` | P6.0v1 |

After P6.0v1, an event MCS costs:
- the count readback;
- one O(events) download of the compacted events, and one O(events) upload for the
  host-planned cluster cases.

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

## 9. Proposed rows

- **P6.0v4 Shared-storage scalars for host reads on unified memory.**
  - Change: allocate the device buffers the host reads every MCS or every event MCS in
    `Metal.SharedStorage` when the backend has unified memory, and read them with a load
    after the sync instead of `Array(a)`. These buffers are the lifecycle `count`, the
    status word, P6.0d's counts and the compacted event list of P6.0v1.
  - Measured: 150–220 µs → 0.3 µs per read.
  - The counters keep counting each read as 1 transfer, so frozen target (b) is unchanged.
  - Accept: a quiet lifecycle MCS on Metal is faster by at least the measured readback
    latency in `ab.jl` (Akeeb, OpenVT); results unchanged.
- **P6.0v5 (optional, low priority) Device-resident host phases.**
  - Adaptive ODEs through a device adaptive ensemble kernel (DiffEqGPU style).
  - `@link`/`@unlink` through a device contact graph (A5, H5).
  - P6.0v2 makes both cheap; this row removes the per-MCS sync as well.
- **P6.0v6 (needs a decision; amends D-035 and frozen target (b)) Sync-free quiet MCS.**
  - After P6.0v1 the whole event path can run on the device (compacted event list, device
    plan for plain divisions and removals), so the host need not read the count every MCS.
  - Read it lazily, every k MCS or at saves, and run the event kernels unconditionally: they
    are no-ops with zero events.
  - This removes the last sync of a quiet MCS (T1). Measured cost of that sync: Akeeb quiet
    MCS is latency-bound (median 2.2 ms per MCS with the sync, against a throughput mode
    that keeps the queue full).
  - Cluster divisions would still need a host plan. They would be deferred to the next read,
    which changes when they happen unless the plan moves to the device.
- **P6.0v7 (tooling) The gate measures GPU completion.**
  - `benchmark/gate.jl` should time `step!` plus `synchronize` (or N MCS plus one sync)
    on Metal, so that sync-free and lifecycle models are measured alike (§2).
  - Rebaseline Metal once.
- **P6.0v8 (rule, with P6.0v3) No Metal.jl `copyto!` between device arrays in the step path.**
  - Route every device→device copy through one CorePotts helper that launches a KA copy
    kernel (`FieldStep`, `CopyPhase`, and any later one).
  - Add a test that fails if a device→device `copyto!` or a `UInt8`/`Int8` `fill!` appears in
    a Metal MCS. For example, count them through the helper and grep the step path for raw
    `copyto!` in QA.
  - D-085's counters cannot see these waits, so without a rule they come back.

The ROADMAP row says the implementation is "split into P6.0v1–P6.0v4" but defines only v1–v3.
This audit proposes v4 as above.

## 10. Assignment summary

| row | entries |
|---|---|
| P6.0v1 | L1–L15, L17; F4; P2, P3; R2's sizing (at the P6.0d merge) |
| P6.0v2 | A1–A4; H1–H4; R4 |
| P6.0v3 | F2 first (measured 5.1× on Merks), F3; T3; F1; X1–X5; Int64-moment investigation (§8.2); P6.0t if still open |
| P6.0v4 (proposed) | T2, and the readback halves of L1 and R2 |
| P6.0v5 (proposed, optional) | A5, H5 |
| P6.0v6 (proposed, needs decision) | T1 |
| P6.0v7 (proposed) | gate semantics (§2) |
| P6.0v8 (proposed rule) | no Metal.jl device→device `copyto!` in the step path (guards F2 and F3) |
| unavoidable or kept (justified) | T1 under D-035; F5 (no grid barrier); A6 (column-only already); R1, R3; L16 (user hook); P4, P5; outside the MCS: saves and `integ.u` (`problem.jl:258-261`: sync and snapshot, the user asked for the state), `_check_status!` at saves (`:275-280`, 4 B), `checkpoint` (`checkpoint.jl:26-30`), `reinit!` (`:62`, setup; the counters are reset after it), `set_state!` (`problem.jl:471-475`, 1 sync and 1 upload per user write), `init` uploads, `src/layouts.jl:241,419` and `src/problem.jl:419` (setup, host), `Lattice` `==`/`hash` (`lattice.jl:79-80`, host utility) |
