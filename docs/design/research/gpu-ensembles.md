# GPU ensembles for `SequentialCPM` and `CheckerboardCPM`

> **RESEARCH — not a decision.** 2026-10-06. Nothing in `src/`, `lib/`, `benchmark/` or
> DECISIONS changes. Nothing was run: no benchmark, no test suite and no GPU code (D-157
> forbids heavy compute on the Mac, and this study is read-only). Each number below is either
> **measured** (with its machine, backend and source) or an **estimate** (with its
> assumptions). Estimates name the machine they predict for, usually "the PC": Ryzen AI Max+ 395
> (16C/32T, Zen 5), Radeon 8060S iGPU (gfx1151, RDNA 3.5, 40 CUs), ROCm 7.2.1, AMDGPU.jl.
>
> D-157 (backend-neutral device testing, PC compute, core pinning) is in DECISIONS.md
> (committed a881ba46, after this study was written). GE0b is covered by ROADMAP P6.0bg.

## 0. Summary

**Question.** Can Potts.jl run large ensembles on the GPU for both of its algorithms?

**Short answer.**

1. **`CheckerboardCPM`: yes, at low cost.** Make the replicate an extra dimension of every
   launch: one launch per colour per MCS covers all replicates (design C-c, §2.3). This needs
   no codegen change. The generated `delta_H`/`commit!` bodies run unchanged on a per-replicate
   *slice* of a batched state. Trajectory `i` of a batch can reproduce `solve(remake(prob;
   replica = …))` bit for bit on the same backend and scalar type, except where a model uses
   order-dependent float atomics (§4).
2. **`SequentialCPM`: yes, but only in two forms that keep its exact dynamics.**
   - **S-a, one replicate per work-item.** It is exact and simple. It pays off only for tiny
     lattices with 10³–10⁵ replicates, which is the UQ/inference regime.
   - **S-b, one replicate per workgroup with speculative windows.** The workgroup evaluates W
     consecutive attempts in parallel. It commits the prefix that no accepted earlier attempt
     could have affected. The dependency test is the checkerboard's footprint-and-claims
     oracle. It is exact (the same Markov chain realisation as S-a), but speculative: its
     payoff depends on a measurable conflict rate.

   Any other GPU scheme (fine checkerboards, Sultan-style subsection sweeps) is a **different
   algorithm**, not `SequentialCPM`.
3. **Payoff on the PC is modest for today's workloads.** The 16-core CPU running 24-thread
   `EnsembleThreads` is a strong baseline. Today's measured GPU per-site cost (M1 Pro Metal)
   predicts that a saturated gfx1151 checkerboard batch is only **about 1–3× faster** than
   the CPU ensemble (estimate, §6). Large wins (5–30×) appear only where an **exact
   null-region skip** (§2.5, item GE3) removes most of the sweep:
   - growth from one cell (the OpenVT monolayer G9 sweeps);
   - one cell in a large 3D box (the Fortuna scan).
4. **The binding constraint is fidelity, not hardware.** Every reproduction so far runs
   `SequentialCPM`:
   - Akeeb: `lib/PottsModels/reproductions/10_akeeb.jl:290`;
   - sorting: `reproductions/data/09/full-2026-10-05/page_meta.toml`;
   - the OpenVT chain calibration, which sets T_Potts: `reproductions/data/15/calibration-2026-10-05/meta.toml`.

   A checkerboard ensemble helps those reproductions only with a documented deviation and a
   re-validation, a maintainer call (§8). S-b is the only route that keeps sequential
   fidelity at GPU scale.

**Recommended path.**

1. Measure first (GE0), including a CPU-only conflict census that predicts S-b's efficiency.
2. Then build batched checkerboard ensembles (GE1, GE2), the exact null-region skip (GE3) and
   a CPU+GPU split (GE7).
3. S-a (GE4) is cheap and doubles as the oracle for S-b.
4. S-b (GE5) and a per-replicate persistent megakernel (GE6) are research items behind
   explicit go/no-go gates.

## 1. What the code does today

### 1.1 The two sweeps

- **`SequentialCPM`.** `sequential_mcs!` (`lib/CorePotts/src/sequential.jl:7-42`) is a host
  loop of `nsite` attempts. Attempt `k` draws `(rt, rd, ra)` from one Philox call at address
  `(mcs, k, STREAM_SEQUENTIAL_TARGET)` (`:16`). It then picks:
  - the target, `mobile_site(mob, bounded(rt, nsite) + 1)` (`:17`);
  - a direction (`:19-20`);
  - and runs `constraint`, `delta_H`, `temperature` and Metropolis/Barker (`:28-34`).

  An accepted attempt writes `σ[t]` and calls `commit!` (`:36-37`). Two details matter for a
  device port:
  - The track sum is a `Float64` (`:14`, `:35`), and `Float64` is banned on the device.
  - The mobile-site list exists on the host only (`lattice.jl:371-373`, `:419-421`).

  `_init` rejects a device backend (`problem.jl:292-293`), per D-009 and INTERNALS §1.10.
- **`CheckerboardCPM`.** `checkerboard_mcs!` (`checkerboard.jl:227-260`) shuffles the colours
  on the host from the Philox key (`_color_order!`, `:262-271`). Each colour then gets two
  launches:
  - `propose_body!` (`:63-113`): an addressed draw at `(mcs, t, STREAM_PROPOSAL)`, ΔH,
    acceptance, then claims by `atomic max` of a priority `won = (random high bits) | j`.
  - `commit_body!` (`:115-148`): it commits if the copy won every claim, and clears the next
    colour's claim buffer.

  Scratch is `prio::UInt32[maxsites]`, `source::Int[maxsites]`, `2 × claim::UInt32[capacity]`
  and a 1-word `status` (`:191-207`). The 2²⁴ limit on a colour class comes from the
  priority's low bits (`:196-199`).

### 1.2 The generated functions are state-shape-agnostic

Codegen writes linear-index reads such as `st.σ[sn]`, `st.cell.volume[c]` and
`st.cell.m1[d, c]` (`src/codegen.jl:168-247`). Parameters are read from `p`. Every piece of
the model is a `drop_expr`'d RGF, so it is isbits (`src/codegen.jl:5-10`).

**Consequence.** Wrap each state array in a view that adds a per-replicate offset. The same
generated bodies then run on replicate `r` with no regeneration and no type that encodes
model content. D-046 holds: the wrapper type is generic.

### 1.3 Everything between sweeps is already a kernel, or already isolated

- **Phases.** `SitePhase`, `CellPhase`, `ModelPhase`, `FieldStep`, `CopyPhase` and
  `HistoryPush` all go through `_launch(body, backend, n, args)` (`phases.jl:42-50`,
  `fields.jl:172`). So one batched `_launch` method batches them all.
- **Device lifecycle (D-089, D-096).** It is a fixed kernel sequence (`lifecycle_device.jl:1-25`):
  - the planner is a single workgroup with `@localmem` and `@synchronize` (`_plan_kernel!`,
    `:456`);
  - the "fused" form runs the whole lifecycle in one workgroup (`_fused_kernel!`, `:961`).

  A workgroup-per-replicate grid is therefore a natural batched form.
- **Host-only pieces.** These cannot batch without per-replicate host copies:
  - `HostPhase` (`relationships.jl:252-305`; generated for `@link` rules, `src/codegen.jl:1211`);
  - `_AdaptiveODE` (`src/codegen.jl:874-953`);
  - the D-035 host lifecycle planner (`lifecycle.jl:311-444`, which uses a `Dict` at `:339`);
  - host `DiscreteCallback`s (`problem.jl:340-346`).
- **Ensembles today.** `EnsembleProblem` maps trajectory `i` to
  `remake(prob′; replica = prob.replica + i, repeat = ctx.repeat − 1)` (`problem.jl:696-733`).
  On a device the default is `EnsembleSerial()`, one queue (`:720-723`). So a device ensemble
  today is R back-to-back solo runs.

### 1.4 Measured anchors

All measured on an Apple M1 Pro. These are the only GPU measurements in the repository.

| quantity | value | source |
|---|---|---|
| sequential CPU, gate models | Graner–Glazier (GG) 72²: 24.8; Akeeb 99×60: 47.2; OpenVT reference 100²: 19.55 ns/site·MCS (1 thread) | `benchmark/baseline.toml` |
| checkerboard Metal 576² (GG) | 3.15 ns/site·MCS, warm | `benchmark/README.md` (audit-group-1 table) |
| checkerboard Metal 72² (GG) | 34.8 ns/site·MCS (launch-bound) | same |
| Metal small lattice, gate | Akeeb 99×60: 123.5; GG 72²: 86.3 ns/site·MCS, timed to completion | `benchmark/baseline.toml`, `README.md` (D-090) |
| launch cost | about 20 µs per launch, GG launch-bound | `research/gpu-host-transfer-audit.md:393-397` |
| sorting FULL (P6.1f) | 10 replicates × 3.2·10⁵ MCS × 347², `SequentialCPM`, 6 threads: 5052 s | `reproductions/data/09/full-2026-10-05/` |
| OpenVT chain calibration (P6.15b) | 100 seeds × λ ∈ {1, 2, 3, 5} (11-chain) + 100 (21-chain), 4 threads: 11.2 s of simulation | `reproductions/data/15/calibration-2026-10-05/` |

**What the 576² row implies.** On M1 Pro Metal, 3.15 ns/site·MCS is about 1.04 ms per MCS
for 331 776 sites. About 0.16 ms of that is the 8 launches. The rest is roughly 7000
lane-cycles per site (2048 lanes × 1.3 GHz).

The DRAM traffic is about 20 GB/s, an order of magnitude under the bus. So today's
checkerboard kernel is **latency- and occupancy-bound, not bandwidth-bound**. This matters
twice:
- batching replicates removes launch overhead but not this per-site cost;
- the kernel itself probably has 3–10× headroom (estimate), which would help single runs as
  much as ensembles.

## 2. Parallelisation mappings

Notation: R replicates, N sites per replicate, n_c colours (4 in 2D at stride 2, 8 in 3D,
27 in 3D at stride 3).

### 2.1 Which mappings keep `SequentialCPM` exact

`SequentialCPM`'s dynamics are a specific Markov chain. Attempt `k` of MCS `m` is a pure
function of the key, `(m, k)` and the state left by attempts `1…k−1`. A GPU scheme "remains
`SequentialCPM`" if it realises the same chain law. It is bit-exact against another device
run if it also evaluates attempts in that order, against that state.

| mapping | exact `SequentialCPM`? | why |
|---|---|---|
| (a) one replicate per work-item | **yes, bit-identical** to the same loop on the same backend and scalar type | the work-item runs `sequential_mcs!`'s body verbatim on its slice |
| (b) one replicate per workgroup, speculative windows | **yes, bit-identical to (a)** | §2.2: only attempts provably independent of earlier accepted ones in the window commit; the rest re-run |
| (c) replicate as an array dimension, batched launch | for sequential, this *is* (a) at the launch level | — |
| (d1) fine checkerboard inside a replicate | **no**: that is `CheckerboardCPM` (accept-then-claim, colour order) | INTERNALS §1.5: "approximate parallel dynamic" |
| (d2) Sultan et al. subsections: large blocks, random-site sequential inside each, frequent switching | **no**: a third algorithm. It is closer to sequential in local update statistics (their claim), but blocks advance in lock-step | §7 |
| (d3) "synchronous relaxation" (Lubachevsky / Shim–Amar), iterating windows to a fixed point | exact, but it is S-b with a worse conflict rule | §7 |

### 2.2 `SequentialCPM` designs

**S-a: one replicate per work-item.**
- **Kernel.** `ndrange = R`. Item `r` slices the state (§3.1) and runs the attempt loop for
  attempts `k₀…k₁` of the current MCS.
- **Launch chunking.** Launches are cut into attempt chunks (for example 2¹⁶ attempts). Two
  reasons:
  - a 1400² MCS is 2·10⁶ dependent attempts per item, a multi-second kernel, which risks
    device timeouts;
  - the host can interleave phases.

  Chunking is free: attempts are addressed by index.
- **Required changes.**
  - A device mobile-site list per replicate. A prefix-scan compaction runs when the frozen
    mask changes: on the D-089 lifecycle path, `lattice.jl:392-421`. Today the device keeps
    only the mask (`:373`), and `_device_planned` excludes `SequentialCPM` for this reason
    (`problem.jl:495-508`).
  - The `Float64` track accumulator becomes a per-replicate `T` accumulator, folded into
    `stats.accepted_ΔH::Float64` at host read points, as checkerboard does (`_fold_track!`).
  - Accepted counts and status become per-replicate device words.
- **Performance.** No coalescing: each replicate hits different random sites. Branch
  divergence is severe: `a == b` null attempts, rejections and accepts differ per lane.
  Throughput needs ≥ 10⁴ concurrent items to hide latency (40 CUs × 32 lanes × 8–16 waves,
  an estimate). So it pays only when R ≳ 10⁴. **Use:** tiny lattices in inference loops, and
  as the oracle for S-b.

**S-b: one replicate per workgroup, speculative windows (exact).**

*The window loop.* A workgroup of W lanes (64–256) owns replicate `r` and repeats:

1. Lane `j` evaluates attempt `k + j` against the state at window start. The Philox addresses
   are independent of the state, so all W draws are known in advance. Each lane records a
   descriptor: target `t`, source `s`, `old`/`new`, the claim set `f.claims`, the read set
   `f.reads`, and accepted/rejected/null.
2. **Dependency.** Attempt `j` depends on an *accepted* attempt `i < j` in the window iff
   either holds:
   - (spatial) `‖x_j − x_i‖_∞ < s` on the periodic metric, where `s = r_read + r_write + 1`
     is the checkerboard stride (`model.jl:101-106`);
   - (cell) `{old_i, new_i} ∪ claims_i` intersects `{old_j, new_j} ∪ claims_j ∪ reads_j`.

   This is exactly the independence that checkerboard colours plus claims guarantee
   (INTERNALS §1.5 "Why this is correct"), applied in sequential order.
3. `c` is the first dependent attempt: a workgroup prefix-min over lanes, with the accepted
   descriptors in LDS.
4. Every accepted attempt before `c` commits in parallel. They are pairwise independent by
   construction, so no atomics are needed on their cells. Attempts before `c` that were
   rejected or null are final.
5. The next window starts at attempt `c`.

*Exactness.* Attempt `j` reads only its footprint and its claim/read cells. If no earlier
accepted attempt in the window wrote any of them, its evaluation against the window-start
state equals its evaluation against the true sequential state. The result is the same
decisions, and the same floats, as S-a.

*Where it must fall back to W = 1:*
- terms with unbounded footprint (already rejected for checkerboard at `init`,
  `problem.jl:357-382`);
- any `commit!` write to model-scope state that `delta_H` reads, for example a
  global-energy or population reduction kept incrementally;
- cluster quantities not covered by `cluster_claims` (D-036).

Codegen has to emit this as a flag (§8).

*Expected efficiency* (estimate; GE0 measures it on the CPU first). Let p_acc be the fraction
of attempts accepted and q the probability that a later attempt depends on a given accepted
one. The cumulative hazard is about `p_acc · q · j² / 2`, so the run length is about
`√(2 / (p_acc q))`.
- With ~10⁴ cells over 2·10⁶ sites (OpenVT growth), q ≈ 4/N_cells + footprint/N ≈ 4·10⁻⁴.
  With p_acc ≈ 0.05, the run length is about 300. **A window of 256 commits almost entirely.**
- With 11–21 cells (the chain), q is about 0.2–0.4 and the run length about 10. Efficiency
  is poor.
- With about 500 cells (Akeeb at start), the run length is about 70.

### 2.3 `CheckerboardCPM` designs

**C-c: replicate as an extra launch dimension (recommended first).**
- **Launches.** Per colour slot `k`, `propose!` and `commit!` launch over `ndrange =
  (maxsites, R)`. Index `j` runs fastest, so each replicate keeps the solo coalescing pattern.
- **Colour order.** Replicate `r` processes colour `order[k, r]`. A tiny `ndrange = R` kernel
  fills `order` per MCS with the same Fisher–Yates draws as `_color_order!`
  (`checkerboard.jl:262-271`), so nothing is uploaded per MCS. Work-items with
  `j > ncolorsites(color_r)` exit; in 2D with even dimensions all colours have the same size.
- **Buffers.** Claims, `prio`, `source` and `status` gain a replicate dimension.
- **Launch count.** It stays `2·n_c` plus the phases. It is independent of R, which removes
  the launch-bound regime of small lattices (the 72² and 99×60 Metal rows of §1.4).
- **Phases and lifecycle.** Phases batch through one `_launch` method. The device lifecycle
  batches with `group index = replicate` (§3.3).

**C-b: one replicate per workgroup, persistent (research).** One workgroup sweeps its
replicate's colours with `@synchronize` between colours and runs K MCS per launch:
- claims go into LDS when capacity allows;
- the per-MCS phases are called as `body(i, args…)` loops over lanes;
- the fused lifecycle (`lifecycle_device.jl:961`) is already this shape.

Launch overhead becomes O(1/K). The lattice must be small: ≤ ~10⁵ sites so the sweep per
lane stays short, and tiny lattices could also tile σ into LDS. Bit-identical to C-c: same
claims (atomic max is order-free), same colour order, same bodies. Risks: register pressure,
because the fused kernel already hits Metal's 384-thread limit (`lifecycle_device.jl:27-31`),
and KA's CPU backend restrictions on `@synchronize` in loops (§8).

**C-a: one replicate per work-item.** This would be a serial checkerboard. It is pointless:
it combines S-a's divergence with checkerboard's approximation. Rejected.

### 2.4 Hybrids

- **Heterogeneous split (GE7).** Run a fraction of the ensemble with `EnsembleThreads` on the
  CPU and the rest batched on the GPU, as DiffEqGPU's `EnsembleGPUArray(…, cpu_offload)`
  does. On this APU the two are comparable (§6), so the split is worth up to about 1.5–2×
  over the better of the two.
  - Caveat: both draw on one 256 GB/s LPDDR5X bus. The checkerboard batch uses ~10–40 GB/s
    (estimate from §1.4), and cache-resident CPU replicates use little DRAM, so contention is
    expected to be small except for the 1400² runs.
- **Interim, no new kernels.** Run `EnsembleThreads()` *with a device backend*, so each Julia
  task has its own stream: AMDGPU.jl gives each task its own HIP stream (to verify). Solo runs
  then overlap on the GPU. `__solve` picks `EnsembleSerial` on devices today
  (`problem.jl:720-723`), but the three-argument call accepts `EnsembleThreads()` explicitly.
  This is the cheapest experiment (GE0, case K0).

### 2.5 Exact null-region skip

Not an ensemble feature, but it multiplies every design.

- **Checkerboard.** A target `t` whose whole proposal neighbourhood is medium has `a == b`:
  the proposal does nothing, and its draw is address-keyed, so skipping it consumes nothing.
  Keep a per-replicate bounding box of non-medium sites, padded by the proposal radius. It
  expands on commit by atomic min/max (conservatively, never shrinking between rebuilds) and
  is rebuilt at sync points. Enumerating only the colour sites inside the box is then
  **bit-identical**, provided `j` (the colour-local index used in the priority) and `idbits`
  keep their full-lattice values (`checkerboard.jl:88`, `:197`).
- **Sequential.** An attempt whose drawn target falls outside the box is null without
  touching σ. That saves the random cache miss, which dominates large-lattice sequential
  cost. This is exact as well.
- Phases and fields still run on the whole lattice. Periodic axes need wrap-around boxes, or
  the skip is disabled once the box wraps.

This differs from `BoundarySite` proposals (P6.4b, spec 15 G9), which change the proposal
law.

## 3. State layout

### 3.1 Batched state

- **Layout.** **Replicate-major**: every state array gains a trailing dimension R, so
  `σ::Array{Int32, N+1}` has size `(dims…, R)` and a cell column has size `(…, capacity, R)`.
  - Each replicate is contiguous. Copy-out of one trajectory is one block.
  - S-b and C-b (workgroup per replicate) get locality.
  - C-c keeps solo coalescing because `j` is the fastest index.
  - An interleaved layout (`σ[r, x, y]`) would coalesce C-c fully, but it is wrong for S-a,
    S-b and C-b. It is left as a late experiment for tiny lattices under C-c only.
- **`ReplicaSlice`.** A generic leaf type `ReplicaSlice{T, N, A} <: AbstractArray{T, N}`
  holds the parent array, `r` and the solo `dims`:
  - `getindex(a, i::Int) = parent[offset + i]` and the Cartesian forms;
  - `size`, `length`, `eltype` and `axes` as solo.

  Inside a kernel, `_slice(st::CPMState, r)` builds `CPMState(_slice(σ, r), map(x -> _slice(x,
  r), st.cell), …)`. That is Base `map` over a NamedTuple, not package recursion, the same
  pattern as `with_capacity` (`lifecycle.jl:508`). The generated `st.σ[sn]` then reads
  replicate `r`. No model-content type is introduced (D-046).
- **Model scope.** 1-element model arrays become `(1, R)`, and the `#status` word with them
  (`rng.jl:117-121`). History rings become `(depth·n, R)`.
- **Parameters.**
  - Seed-only ensembles share one `p`, passed once and selected by type.
  - Sweeps (Akeeb's 121 (J_LF, λ) points, OpenVT β/γ) use `ps::Vector{P}` on the device with
    `p_r = ps[r]`. This requires isbits `P`. Today's `PottsParameters` and NamedTuples of
    `SMatrix`/scalars qualify (D-012, D-046).
- **Keys.** `keys::Vector{RNGKey}`: 8 bytes per replicate.
- **Context.** `ctx` (lattice, relations, spacing) is shared. A mobility mask that follows
  the state becomes per replicate (`MaskMobility.frozen` sliced).

### 3.2 Ragged cell populations

- **Capacity** is the maximum required over the batch. Free slots have volume 0, and every
  cell kernel already skips them (`lifecycle.jl:14-15`).
- **Growth past capacity** defers as today (D-035 deferral, counted per replicate). Batched
  runs should require a sufficient `capacity` up front (OpenVT: 10⁴ + margin). Batched host
  re-growth is possible at a sync point because types do not change, but it is not worth
  building first.
- **Per-replicate cell counts** live in a device vector. Cell kernels launch
  `capacity × R` and exit on free slots. Growth runs waste lanes early; that costs little
  next to the site sweeps.

### 3.3 Lifecycle in a batch

The D-089 device lifecycle maps one-to-one:
- the trigger and per-cell stages launch `(capacity, R)`;
- the planner launches R workgroups of `PLAN_WG` (`lifecycle_device.jl:34`) with group index
  `= r`;
- scratch (`_device_scratch`, `:72-79`) gains R;
- the fold buffers `acc` and `mask` (Int64; Metal supports 64-bit integers, only 64-bit
  atomics are missing) become `(·, R)`.

The host planner (D-035 `Dict`, `lifecycle.jl:339`) and `rebuild!` hooks cannot batch. A
batched solve rejects them with an error that names the CPU route.

### 3.4 Memory per replicate

Estimates assume Int32 σ, Float32 fields and ~20 four-byte cell columns. Checkerboard scratch
is `prio` + `source` per colour class (`source` is `Int`, 8 B, `checkerboard.jl:202`).

| workload | lattice (sites) | cells (capacity) | per replicate | ensemble | fits where |
|---|---|---|---|---|---|
| OpenVT chain (spec 15 §4.2, P1/P7) | 150×5 = 750 / 250×5 = 1250 | 11 / 21 | ~10–20 KB | 400 runs ≈ 8 MB | the 32 MB GPU MALL; LDS per workgroup |
| sorting (09, P6.1f/P6.1g) | 347² = 120 409 | ~10³ | ~1–1.5 MB | 20 runs ≈ 30 MB; 200 ≈ 0.3 GB | MALL for ≤ ~25 |
| Akeeb (10) | 500×300 = 1.5·10⁵ | ~2.2·10³ | ~1.5–3 MB | 1210 runs ≈ 2–4 GB | DRAM |
| OpenVT growth (15, G9) | ~1400² = 1.96·10⁶ | 1.2·10⁴ | ~15–25 MB | 150 runs ≈ 2–4 GB | DRAM |
| Fortuna (14a), 3D | (8–14R)²×2.1R; R = 15, L = 10R: 7.2·10⁵ (up to 3.3·10⁶ at R = 20) | 1 cell, 3 compartments | ~20–60 MB (field + scratch) | 840 runs ≈ 17–50 GB | must batch ~200 at a time |
| Jiang 2005 (06), 3D | UNSPECIFIED (spec 06 §2.1); 200³ = 8·10⁶ to 490³ = 1.2·10⁸ | 10⁴–10⁵ | ~60 MB to ~1 GB | ~10 runs | DRAM; at 512³ a colour class reaches the 2²⁴ priority limit |

On the APU, the GPU-allocatable share (VRAM carve-out plus GTT) must be checked on the PC
before sizing batches: "62 GB visible" is the CPU view (risk R3).

## 4. RNG and reproducibility

- **Keys.** The batch computes `keys[r] = RNGKey(seed_r, replica_r, repeat_r)` on the host,
  exactly as `_ReplicaProbFunc` derives them (`problem.jl:728-733`). Every draw keeps its
  address:
  - `(mcs, k, STREAM_SEQUENTIAL_TARGET)` for sequential;
  - `(mcs, t, STREAM_PROPOSAL)` for checkerboard;
  - `(mcs, i, STREAM_COLOR_ORDER)` for the colour order;
  - cell-addressed streams with generation (`rng.jl:78-94`).

  The batch index never enters an address, so replicate compaction (§5.3) changes nothing.
- **Bit-identity, same backend and scalar type.** Trajectory `i` of a batch equals
  `solve(remake(prob; replica = …), alg; backend)`, provided both run the same body functions
  and the model has **no order-dependent float atomics**. Today these are:
  - cluster surfaces (`compartments.jl:150-151`);
  - spatial measures (`spatial.jl:179, 196`);
  - the device-lifecycle surface update (`lifecycle_device.jl:602-603`).

  Those models get statistical agreement only, and so do repeated solo runs of them, which
  D-029 already accepts. Integer atomics (volumes, claims, counts) are order-free.

  Compilers could in principle contract floating-point operations differently when a body
  is inlined into a different kernel. Julia emits no `contract` flags without `@fastmath` or
  `muladd`, but each backend must be checked by test (GE1/GE2 acceptance).
- **S-b against S-a** is bit-identical by construction (§2.2). It is the oracle for S-b.
- **Bit-identity against the CPU is impossible** in general, and not wanted (D-029):
  - the default scalar type is `Float32` on every backend, `Float64` only where declared and
    supported (INTERNALS §1.10);
  - the device `exp`/`log` differ from Base's;
  - checkerboard is a different algorithm from the CPU reference.
- **The statistical replacement** (D-048: ordinary tests, oracles, negative controls):
  1. **Two-sample tests** on per-replicate observables at fixed MCS (energy proxy, volume
     histogram, heterotypic boundary fraction, cell count). Use Kolmogorov–Smirnov or
     Anderson–Darling with ≥ 16 seeds per arm, as the INTERNALS §4 table already prescribes
     for checkerboard vs sequential and CPU vs GPU.
  2. **Coupled-pair tests.** Device and CPU runs at one key share every random number, so
     their trajectories stay close for an initial stretch. A paired-difference test on early
     observables has far lower variance than an unpaired one, which detects device bugs with
     few seeds. Report the divergence time as a diagnostic, never as a guarantee.
  3. **A negative control.** A perturbed T (×1.2) or J must be detected by the same tests.
  4. **Exact invariants per replicate** after N MCS: trackers recomputed from σ, volumes sum
     to occupied sites, no orphan sites (the existing GPU-group checks, `test/gpu.jl:30-38`).

## 5. Host phases between sweeps

### 5.1 What batches and what does not

| piece | batched? | how |
|---|---|---|
| `SitePhase`, `CellPhase`, `ModelPhase`, `FieldStep`, `CopyPhase`, `HistoryPush`, `FieldClamp` | yes | one `_launch(body, ::Batched, n, args)` method: `ndrange = (n, R)`, then `body(i, _slice.(args, r)...)` |
| device lifecycle (D-089) | yes | §3.3 |
| standard frozen-mask refresh | yes | per-replicate counters; S-a and S-b also need device compaction of the mobile list |
| `HostPhase`, `_AdaptiveODE`, host lifecycle planner, `rebuild!` | **no** (v1) | rejected at `init` of a batched solve; message names `EnsembleThreads` |
| host `DiscreteCallback` conditions | **no** (v1) | replaced by device stop predicates (§5.3); `saveat` stays |

### 5.2 Saving and output

- **`saveat`** times are common to the batch, so a save is one synchronisation and one copy.
  - Each trajectory's `PottsSolution` is built from its contiguous slice.
  - A `save_idxs`-like selection (for example σ, `kind` and `volume` only) bounds host
    memory: Akeeb's 1210 runs × 5 saves of σ alone is about 3.6 GB.
  - On the APU, host-visible device buffers could avoid the copy (to check in AMDGPU.jl).
- **`output_func(sol_i, ctx_i)`** runs on the host per trajectory after each batch, unchanged.
  `rerun = true` is unsupported in a batch: such trajectories run again in a follow-up batch,
  or the solve errors.
- **`reduction(u, batch, I)`** matches the batch structure exactly. SciMLBase already applies
  it per `batch_size` chunk.
- **Device observables (GE8, later).** Per-replicate reductions at save times write a
  preallocated `(n_obs, R, n_saves)` buffer, with no state copy. This matters for Akeeb-scale
  sweeps and the UQ direction.

### 5.3 Termination and status per replicate

- **Status.** The status word becomes `status[r]`: checkerboard `cache.status` and model
  `#status` (`rng.jl:117-146`). A failure sets `alive[r] = 0`, records `t_fail[r]` and gives
  that trajectory `ReturnCode.Failure`. The others continue.
- **Stop predicates.** A device `stop_when(st, p, ctx, mcs) -> Bool` runs per replicate in an
  `ndrange = R` kernel after the MCS, and writes `alive[r]` and `t_stop[r]`.
  - The OpenVT stop "end of the first MCS with N ≥ 10⁴" (spec 15 C15, G11) becomes a
    model-scope cell count (a `ModelPhase` or reduction) plus that predicate.
  - Today G11 uses a host `DiscreteCallback` plus `terminate!` (ROADMAP P6.15c), which does
    not batch.
- **Dead replicates.** Kernels exit early for dead replicates. The host polls
  `count(alive)` every K MCS (one small read; D-089 allows reads off the quiet MCS). When
  fewer than half are alive, it compacts: live slices are copied to the front and `keys`/`ps`
  permuted. This is exact, because addresses never include the slot.
- **Uneven run lengths.** OpenVT runs near 20× last about 2·10⁵ MCS while uninhibited runs
  stop near 10⁴ MCS (spec 15 §3.5, G9). A batch therefore decays quickly. Mitigations:
  - group the sweep by expected stop time;
  - refill compacted slots from a queue of pending trajectories. The refilled replicate
    starts at its own MCS 0 while others are at MCS m. This needs **per-replicate `mcs`**,
    which the addresses support (`mcs` is a kernel argument today; make it `mcs[r]`).
    Refill is the single most effective throughput fix for termination-skewed sweeps.

## 6. Performance model

### 6.1 Assumptions

Every number in §6 is an estimate. None was measured on the PC.

- **A1.** The CPU per-thread sequential cost on Zen 5 is 0.8–1.2× the M1 Pro single-thread
  gate value when the replicate is cache-resident (§1.4).
- **A2.**
  - 24 threads on 16 cores ≈ 16–19 single-thread equivalents when each replicate's state
    fits its share of L2/L3 (64 MB L3 total, ≈ 2.7 MB per thread).
  - Above that, random-site attempts become DRAM-latency-bound: per-thread cost × 1.5–3.
- **A3.** A saturated batched checkerboard on gfx1151 costs **1.0–2.1 ns/site·MCS**. This is
  M1 Pro Metal 576² (3.15, §1.4) divided by 1.5–3 for the 8060S's larger and faster shader
  array (2560 vs 2048 lanes, ~2.9 vs ~1.3 GHz) and caches (2 MB L2, 32 MB MALL near 1 TB/s per
  chipsandcheese). It is held back by the same latency-bound kernel.
- **A4.** One kernel launch costs 10–25 µs on ROCm/AMDGPU.jl (Metal measured ~20 µs, §1.4).
- **A5.** Saturation needs ~2·10⁴ concurrent work-items per launch. 50% launch efficiency
  needs R·N ≳ 10⁵ sites per batch in 2D, and < 10% launch overhead needs R·N ≳ 10⁶
  (`2·n_c·τ_launch / c_site` with A3 and A4).
- **A6.**
  - S-a: 0.5–3 ns/attempt aggregate at R ≥ 10⁴ (latency hidden by occupancy; divergence ~2×).
  - S-b: bounded below by DRAM traffic when the batch exceeds the 32 MB MALL, at ~150–300 B
    per non-null attempt and ~200 GB/s achievable, giving 0.6–1.5 ns/attempt aggregate.
    Above that, it is bounded by window efficiency (§2.2).

A batched sweep costs per MCS

```
t_MCS(R) ≈ n_launch · τ_launch + R · N · c_site / η(R · N / n_c)
```

with η the occupancy efficiency (→ 1 above A5's threshold). The 24-thread CPU ensemble costs
`R · N · c_cpu / P_eff` with `P_eff` = 16–19.

**Crossover.** The GPU batch beats the CPU ensemble when R·N ≳ 10⁵–10⁶ sites per batch *and*
`c_site < c_cpu / P_eff` (cache-resident: ≈ 1.0–1.5 ns; DRAM-bound: ≈ 1.6–4 ns). At A3 the
inequality holds only by 1–3×.

| lattice | R needed for the crossover |
|---|---|
| 150×5 chain | ≥ 150–1500 |
| 72² | ≥ 20–200 |
| 500×300 | ≥ 1–7 |
| 1400² | 1 |

### 6.2 Regimes

| regime | bound by | consequence |
|---|---|---|
| CPU sequential, replicate fits L2/L3 | compute | the strong baseline: ≈ 1–1.5 ns/site·MCS aggregate on the PC |
| CPU sequential, ≫ L3 (1400², 3D) | DRAM latency (one random miss per attempt) | 1.6–4 ns aggregate; the GPU's memory-level parallelism helps here |
| GPU checkerboard, small R·N | launch latency (§1.4: GG 72², Akeeb 99×60 on Metal) | fixed by C-c batching or C-b |
| GPU checkerboard, saturated | latency and occupancy inside the kernel (≈ 7000 lane-cycles/site on M1 Pro) | batching cannot fix it; kernel work (fewer registers, LDS tiles, `Int32` `source`) can |
| GPU S-a | latency, divergence | needs R ≥ 10⁴ |
| GPU S-b, batch ≫ MALL | DRAM bandwidth (random lines) | still ≥ the CPU's latency-bound rate on large lattices |

### 6.3 Per-workload estimates

Wall times are for the whole ensemble on the PC.
- CPU-24: `EnsembleThreads`, 24 threads, `SequentialCPM` as the reproductions run it.
- C-c: batched `CheckerboardCPM` on gfx1151, which is a **different algorithm** (§8 R2).
- S-a and S-b: device `SequentialCPM`.

All are estimates under A1–A6 unless marked measured.

| workload | site-attempts | CPU-24 (est.) | C-c (est.) | S-a / S-b (est.) | verdict |
|---|---|---|---|---|---|
| **OpenVT chain** calibration (P6.15b): 100 × 4 λ × 11-chain (2.1–7·T, + 100 burn-in) + 100 × 21-chain | 5.7·10⁸ | **measured** 11.2 s on 4 threads (M1 Pro, CPU); est. 2–4 s on the PC | dominated by JIT and setup; < 1× | S-a needs R ≥ 10⁴; S-b run length ≈ 10 (11–21 cells) | **stay on CPU.** Revisit only for inference loops of ≥ 10⁴ chain runs, where S-a/C-b could give 2–4× |
| **Sorting** P6.1g: ≥ 20 replicates × 3.2·10⁵ MCS × 347² | 7.7·10¹¹ | wall = one replicate per thread: 3.85·10¹⁰ × 50–80 ns ≈ **0.5–0.9 h** (per-thread cost from P6.1f, measured: 66–79 ns per attempt-thread, M1 Pro) | 7.7·10¹¹ × 1.0–2.1 ns ≈ 0.2–0.45 h → **1.5–4×**, but a different algorithm on exactly the late-coarsening question V-PRE5 asks | S-a hopeless at R = 20; S-b 20 workgroups underfill 40 CUs, 0.3–1× | **stay on CPU** for the record; C-c only as a high-n screen (for example 200 replicates) |
| **Akeeb** FULL: 1210 × 701 × 1.5·10⁵ | 1.27·10¹¹ | 1.27·10¹¹ × 47 ns × (0.8–1.2) / (16–19) ≈ **4–8 min** (spec 10 §5.3: 1.7 CPU-h on M1 Pro) | 130–270 s → **1–3×** | S-a: R = 1210 is too few, < 1×; S-b ~0.5–2× (run length ~70) | small absolute gain; not worth a deviation |
| **OpenVT growth** G9: 10⁷–10⁸ MCS·runs on ~1400² | 2·10¹³–2·10¹⁴ | DRAM-bound 1.6–3.8 ns aggregate → **9–21 h / 90–210 h** | 1.0–2.1 ns → 5–12 h / 55–115 h (**1.5–3×**). With GE3, about 2–5× more for growth from one cell (time-weighted occupied fraction 10–40%) → **3–15×** | S-b (W = 256, run length ~300) at the DRAM floor 0.6–1.5 ns → **2–5×, keeping `SequentialCPM`** (GE3's sequential skip adds to it) | **the workload that justifies the work.** Either C-c + GE3 with a re-calibrated T (deviation), or S-b if GE0's census is good |
| **Fortuna** 14a scan: 840 runs (10 seeds × 3 R × 4 φ_F × 7 λ, spec 14 :135) × 10⁵ MCS × ~7·10⁵ | ~6·10¹³ | null-dominated (one cell in a large box): ~1–2 ns aggregate → **16–33 h** | 27 colours at stride 3 would be launch-heavy solo; C-c amortises. 0.7–2 ns → 11–33 h (~1–1.5×). With GE3 (the cell fills ~1–5% of the box): **5–30×** | S-b on one cell: every accepted copy shares the cell, so q ≈ 1 and W ≈ 1; no gain | C-c + GE3, with the algorithm deviation; or CPU + GE3's sequential skip (exact, CPU-only, ~3–10× est.) |
| **Jiang 2005** 3D, ~10 replicates | lattice unspecified | 10 replicates use 10 threads: wall = one replicate at 40–80 ns/site·MCS (3D, DRAM) | all 10 batched at 1–2 ns/site·MCS → **2–8×** wall; the gain is intra-replicate parallelism, not batching | S-b: depends on cell count (10⁴–10⁵ cells → long windows) | the GPU helps through checkerboard per replicate; batching is incidental. Memory caps R at ~10–40 |

**Two observations.**
1. The cheapest large win in the table, GE3's exact null-region skip, is not a GPU feature.
   Its sequential form also speeds up the CPU reference runs of growth and single-cell 3D
   models.
2. At A3, the GPU is roughly at parity with a 24-thread Zen 5 for cache-resident 2D work. If
   GE0 shows the gfx1151 checkerboard kernel can reach ~0.3–0.5 ns/site·MCS (≈ 1000–2000
   lane-cycles per site), every C-c row improves by another 3–5×. That kernel-efficiency
   work is shared with single runs and should be judged as such.

### 6.4 Prototype benchmark plan (to run later on the PC)

Run under `tools/exclusive.sh`. Time device runs to completion (D-090: `step!` plus
`KernelAbstractions.synchronize`). Pause the CI runner, or record the contention (it shares
the cores). Label every row with machine and backend (D-157).

| id | kernel | cases | measure |
|---|---|---|---|
| **K0** | none new: `solve(ens, CheckerboardCPM(), EnsembleThreads(); backend = ROCBackend())` vs `EnsembleSerial` vs CPU `EnsembleThreads` | GG 72² × R ∈ {1, 8, 32}; Akeeb 500×300 × R ∈ {1, 8} | aggregate ns/site·MCS; whether streams overlap (rocprof timeline) |
| **K1** | a hand-written C-c batched propose/commit (GG `CPMFunction` from the CorePotts test fixtures; `ReplicaSlice`; device colour order) | (i) GG 72² × R ∈ {1, 16, 128, 1024}; (ii) a 500×300 GG-like lattice × R ∈ {1, 8, 64}; (iii) 1400² × R ∈ {1, 4} | ns/site·MCS aggregate; launches per MCS; VGPR count and occupancy (`AMDGPU.@device_code_gcn`, rocprof); achieved DRAM GB/s; lane-cycles per site; the same cases on CPU-24 sequential and checkerboard; bit-identity of trajectory `i` vs solo on ROCm |
| **K2** | S-a: `sequential_mcs!`'s body per work-item, chunked | chain 150×5 × R ∈ {256, 4096, 32 768} | ns/attempt aggregate vs CPU-24; divergence (active-lane fraction) |
| **K3** (CPU only, no GPU) | the **conflict census**: instrumented host `SequentialCPM` reports, per window of W ∈ {32, 64, 256} attempts, the first dependent attempt under §2.2's rule | chain 150×5, GG 347², Akeeb 500×300, OpenVT growth snapshots at 10³ and 10⁴ cells, Fortuna | mean committed run length and its distribution per model. **It decides GE5 before any GPU code exists** |

The go/no-go numbers for each item are in §9.

## 7. Prior art and what transfers

- **Tapia & D'Souza 2011**, "Parallelizing the Cellular Potts Model on graphics processing
  units", *Comput. Phys. Commun.* 182(4):857–865 (https://hgpu.org/?p=4841). They used fine
  checkerboards with atomic locks, data-parallel memory allocation for cell division, up to
  256³ lattices and > 10⁶ cells, about 80× over serial. **Transfers:** claims via atomics (we
  already use `atomic max` priorities), and on-device allocation for division (D-089 already
  does it with prefix scans). They give no ensemble treatment.
- **Sultan, Devi, Mueller & Textor 2023**, "A parallelized cellular Potts model that enables
  simulations at tissue scale" (arXiv:2312.09317, https://arxiv.org/abs/2312.09317).
  - Their scheme: large subsections, random-site sequential within each, frequent switching
    of the active set.
  - They show that small checkerboard areas or infrequent switching "alter the waiting time
    distribution" and change sorting, chemotaxis and collective motion.
  - Implementation: shared-memory caching of cell ids to reject internal copies quickly;
    interleaved 64-bit atomics for size and centroid sums.
  - About 3500× vs serial in 2D on a Titan V.

  **Transfers:**
  1. Their statistical warning supports keeping `SequentialCPM` as the fidelity reference
     and treating a checkerboard ensemble as a deviation that needs revalidation (§8 R2).
  2. LDS tiling of σ is a concrete fix for our latency-bound kernel (§1.4).
  3. Their subsection scheme is a candidate third algorithm (d2), out of scope here.
- **Yu & Yang 2014**, an OpenCL cross-platform CPM. Found by title only in a search, not
  verified, with no URL. It is the only vendor-neutral precedent found.
- **Block, Virnau & Preis 2010**, multi-GPU multi-spin Ising
  (https://arxiv.org/abs/1007.3726), and **Weigel 2012**, "Performance potential for
  simulating spin models on GPU", *J. Comput. Phys.* 231:3064 (https://arxiv.org/abs/1101.1427).
  Both tailor checkerboard sweeps to GPU memory: shared-memory tiles and coalesced
  sublattice layouts. Weigel also runs many replicas (parallel tempering) on one GPU.
  **Transfers:** the tile and layout lessons for K1; replica parallelism as the first axis
  when a single lattice cannot fill the device.
- **Fang et al. 2014**, parallel tempering of the 3D Edwards–Anderson model with compact
  asynchronous multispin coding (https://arxiv.org/abs/1311.5582). Their levels of
  parallelism are disorder realisations, then temperature replicas, then spins. Packing
  replicas into bits is specific to binary spins and does not transfer to Potts ids. The
  priority order does: **replicas first** for small systems.
- **Anderson, Jankowski, Grubb, Engel & Glotzer 2013**, massively parallel hard-particle MC on
  GPUs with checkerboard cells and detailed balance, *J. Comput. Phys.* 254:27
  (https://arxiv.org/abs/1211.1646). It shows a checkerboard can be made to satisfy detailed
  balance with randomised cell offsets and orderings. That is relevant to how `CheckerboardCPM`
  documents its approximation, and suggests a cheap improvement: a random colour-grid shift
  per MCS.
- **Shim & Amar 2005**: the synchronous sublattice algorithm
  (https://arxiv.org/abs/cond-mat/0406379) and the synchronous relaxation algorithm
  (https://arxiv.org/abs/cond-mat/0406540) for parallel KMC. Sublattice is (d1) in spirit;
  synchronous relaxation is exact by iteration and is the ancestor of S-b. S-b replaces
  iteration with a dependency oracle that the compiler provides through footprints and claims.
- **Brockwell 2006** (pre-fetching) and **Angelino et al. 2014**, "Accelerating MCMC via
  parallel predictive prefetching" (https://arxiv.org/abs/1403.7265). Speculative evaluation
  of future MH steps exploits the fact that rejection is the likely branch. S-b is
  predictive prefetching with a CPM-specific locality structure: most attempts are null or
  rejected *and* far apart, so the speculation is mostly right.
- **DiffEqGPU** (Utkarsh et al. 2024, *CMAME*, https://arxiv.org/abs/2304.06835; docs
  https://docs.sciml.ai/DiffEqGPU/dev/manual/choosing_ensembler/).
  - `EnsembleGPUArray` batches the state array across trajectories and runs a stock solver.
    It is flexible, but has more launches and synchronisations; it maps to our C-c.
  - `EnsembleGPUKernel` runs one trajectory per thread with the whole solver in the kernel,
    with fewer launches but restricted problems (isbits, out-of-place); it maps to S-a/C-b.

  **Lessons:**
  1. Ship the batched-array form first and the per-trajectory kernel later. Their docs say
     to prefer the kernel form when it applies.
  2. Require isbits parameters per trajectory.
  3. Provide `cpu_offload` (our GE7).
  4. Keep `batch_size` for memory.
  5. Implement through SciMLBase's ensemble `__solve` so `output_func`, `reduction`,
     `trajectories` and `batch_size` keep their meaning.
- **Other CPM tools (not verified here).** CompuCell3D's GPU support covers PDE solvers, not
  the Potts sweep. Morpheus parallelises the sweep on the CPU (Sultan et al.'s survey
  describes it as non-subsection-based). Artistoo runs in JavaScript. None offers GPU
  ensembles; this would be distinctive.
- **The hardware.** Strix Halo has 256-bit LPDDR5X-8000 (256 GB/s shared by CPU and GPU) and
  a 32 MB memory-side cache delivering about 1 TB/s to the GPU
  (https://chipsandcheese.com/p/strix-halos-memory-subsystem-tackling,
  https://chipsandcheese.com/p/evaluating-the-infinity-cache-in). This is why per-replicate
  states under ~25 KB × 1000, or ~1 MB × 30, behave very differently from 1400² batches.

## 8. Risks and code-rule conflicts

### 8.1 Risks

- **R1, payoff.** At today's kernel efficiency the GPU is at about 1–3× of the CPU ensemble
  (§6). Building GE2 before GE0 risks a large subsystem for little gain. Mitigation: GE0
  gates everything.
- **R2, fidelity.** Every reproduction and the OpenVT calibration use `SequentialCPM` (§0).
  - A checkerboard G9 sweep needs T_Potts recalibrated under `CheckerboardCPM`. The
    calibration is cheap (§6.3 row 1), but it is a deviation-table row and a maintainer
    decision.
  - Sorting's open V-PRE5 question is about dynamics, so a checkerboard ensemble cannot
    settle it.
- **R3, the APU.**
  - CPU and GPU share 256 GB/s, and GE7 can make them contend.
  - The GPU's allocatable memory (carve-out plus GTT) may be well under 62 GB.
  - The PC is also a CI runner (shared cores).
- **R4, register pressure.** The fused lifecycle already hits Metal's per-pipeline thread
  limit (`lifecycle_device.jl:27-31`). C-b and S-b put ΔH, commit, phases and lifecycle in
  one kernel, and occupancy follows the worst part. The staged fallback pattern of D-096
  should be kept.
- **R5, KernelAbstractions.**
  - `@synchronize` inside loops (needed by C-b and S-b) is not supported by KA's CPU backend
    as far as this study knows (to verify). These kernels would then be GPU-only and
    untestable in the CPU suites, which the "every kernel runs on `CPU()`" practice assumes.
  - `@localmem` sizes must be compile-time constants.
  - Metal threadgroup memory is 32 KB and Metal has no 64-bit atomics.
- **R6, float atomics** limit bit-identity (§4).
- **R7, the 2²⁴ priority limit** per colour class (`checkerboard.jl:196-199`) caps Jiang-2005
  lattices near 512³ at stride 2. This is independent of batching.
- **R8, long kernels.** S-a on large lattices must chunk attempts, or device watchdogs
  (desktop GPUs) and queue starvation follow.
- **R9, homogeneity.** A batch needs one `typeof(f)`, one lattice, one state type and one
  capacity. A `prob_func` that changes structure cannot batch. Akeeb's `run_prob` rebuilds
  problems per run, which still batches if the RGF types coincide (same code gives the same
  RGF type). Mitigation: group by type, or error with the reason.
- **R10, test matrix.** The GPU group is Metal-only (`lib/CorePotts/test/gpu.jl:1-3`;
  `Metal` in `test/Project.toml`), and D-157 defers Metal. A ROCm GPU group (AMDGPU in the
  test project, `COREPOTTS_GPU=rocm`) is a prerequisite of GE1.
- **R11, minor.** `source::Int` (8 B) per colour site (`checkerboard.jl:202`) and Int64 index
  arithmetic cost registers and bandwidth. Storing `dir::UInt8` instead is an easy C-c win.

### 8.2 Conflicts with the code rules (INTERNALS §5, CLAUDE.md)

| rule | status |
|---|---|
| no `@generated`, no recursion over heterogeneous tuples | `_slice` uses Base `map` on tuples and NamedTuples (as `with_capacity` does); no package recursion. OK |
| CorePotts types must not encode model content (D-046) | `ReplicaSlice`, `BatchedState`, `EnsembleBatched` are generic. OK |
| `@inline` only on leaf primitives | `_slice` and `ReplicaSlice` indexing are leaves. OK |
| no `throw` in kernels | per-replicate status words. OK |
| `::F where {F}` pass-through | applies to the batched `_launch` and the new kernels. Must be reviewed |
| no `Float64` on the device | S-a/S-b must replace the `Float64` track (`sequential.jl:14, 35`). The `Int64` lifecycle fold stays legal. Must be done |
| warm MCS allocates nothing (AUTONOMY §5) | batched host code per MCS (colour-order kernel, alive poll) must not allocate. Gate it |
| D-009 / INTERNALS §1.10 "Sequential requires `CPU()`" | **S-a/S-b amend D-009.** This needs a D-entry (proposed wording: "SequentialCPM may run on a device as an ensemble mapping; single runs stay host-only by default") |

### 8.3 MTK and the maintainer's stop rule

- **GE1–GE4 and GE7** live entirely in CorePotts. They need nothing from the symbolic layer,
  so P6.0be (the full-MTK-native design) is untouched.
- **GE5 (S-b) needs two pieces of codegen metadata:**
  - whether `commit!` writes model-scope state that `delta_H` reads;
  - whether any term's dependency is not captured by footprint plus claims plus reads.

  That is codegen-path work, and the stop rule ("stop and ask on major MTK friction or major
  slowdown") applies.
- **Device stop predicates (§5.3) interact with P6.0be's event story.** If P6.0be routes
  `@discrete_events` through MTK callbacks evaluated on the host, batched termination needs
  a lowering of those conditions to device predicates. If that lowering fights MTK's
  callback model, stop and ask.
- **Gate tripwire.** Routing `_launch` through a new dispatch must leave single-run kernels
  unchanged: same inlining, zero allocations, gate within tolerance on CPU and on
  ROCm/Metal. Any regression traced to the batching hooks means stop and ask, not absorb.

## 9. Recommendation: phased items

The items follow ROADMAP style. "Gate" means the go/no-go threshold. Every timing names
machine and backend.

### Phase 0: cheap and decisive (do first)

- **GE0 Measurement baseline and conflict census** (no product code).
  - Scope: K0–K3 of §6.4 on the PC.
  - Also measure CPU-24 aggregate ns/site·MCS for the gate models plus Akeeb 500×300 and
    OpenVT 1400².
  - Accept: a table of measured numbers with machine and backend, committed under
    `benchmark/`, and the K3 run-length distributions per model.
  - Gate:
    - GE2 proceeds if K1 shows a saturated C-c batch ≥ 1.3× CPU-24 on a 500×300 batch, or
      if K1's lane-cycles per site point to a clear kernel fix.
    - GE5 proceeds only if K3's mean run length at W = 256 is ≥ 64 on OpenVT growth
      snapshots.
- **GE0b ROCm GPU test group.** Add AMDGPU to the GPU test environment and select it with
  `COREPOTTS_GPU=rocm`. Port `test/gpu.jl`'s Metal checks. Accept: the group passes on
  gfx1151, and the no-`double` IR check stands in for Metal (D-157).

### Phase 1: cheap to moderate, the expected payoff

- **GE1 Batched state and `EnsembleBatched`, with a CPU reference.**
  - Scope:
    - `ReplicaSlice`/`BatchedState`; per-replicate `keys`, `ps`, `status` and `alive`;
    - stacking from `prob_func`, with type-homogeneity checks and clear errors;
    - `SciMLBase.__solve(::EnsembleProblem, ::CPMAlgorithm, ::EnsembleBatched; trajectories,
      batch_size, saveat, save_idxs)`, keeping `output_func`/`reduction` semantics;
    - rejection of host phases.
  - `EnsembleThreads` stays the CPU default.
  - Accept:
    - on the KA CPU backend, trajectory `i` of a batch equals the solo
      `solve(remake(prob; replica = …))` bit for bit, for GG, a field model and a lifecycle
      model without float atomics;
    - the warm batched MCS allocates nothing;
    - `detect_ambiguities` stays clean;
    - no gate case changes.
- **GE2 Batched `CheckerboardCPM` on the device (C-c).**
  - Scope:
    - `ndrange = (maxsites, R)` propose/commit;
    - a device colour-order kernel;
    - per-replicate claims;
    - the batched `_launch`;
    - the batched D-089 lifecycle (planner group = replicate);
    - device stop predicates, alive polling, compaction, and refill with per-replicate `mcs`.
  - Accept:
    - on ROCm, batched vs solo is bit-identical for ≥ 3 gate models;
    - KS/AD agreement with CPU checkerboard on ≥ 16 seeds, plus a detected negative control;
    - a quiet MCS has zero host transfers;
    - aggregate throughput at R·N ≥ 10⁶ is within 20% of a solo saturated lattice of equal
      size.
  - Gate: ≥ 1.3× CPU-24 on the Akeeb-size batch and the OpenVT-size batch (measured, PC). If
    not met, stop and report.
- **GE3 Exact null-region skip, both algorithms, single runs too.**
  - Scope: per-replicate bounding boxes of non-medium sites; checkerboard colour enumeration
    restricted, keeping `j`/`idbits`; sequential targets outside the box skipped without a σ
    read; periodic wrap handling.
  - Accept: bit-identical trajectories with and without the skip (CPU and ROCm) on GG,
    OpenVT growth and a periodic case; the speedup measured on OpenVT growth and a
    Fortuna-like single cell.
  - Gate: none (exact); the gate cases must not regress.
- **GE7 Heterogeneous split.** `EnsembleBatched(backend; cpu_offload = f)` runs fraction `f`
  through `EnsembleThreads`. Accept: the combined throughput on Akeeb-size and chain-size
  batches is measured, with `f` chosen by a one-batch calibration.

### Phase 2: moderate, exact sequential on the device

- **GE4 Device `SequentialCPM`, one replicate per work-item (S-a).**
  - Scope: chunked attempt ranges, a device mobile-site list with compaction, `T` track
    accumulators, per-replicate accepted counts and status.
  - Accept:
    - S-a on the KA CPU backend is bit-identical to the host `sequential_mcs!` in the same
      scalar type, wherever the `exp`/`log` implementations agree. Otherwise, coupled-pair
      tests apply (§4);
    - KS/AD agreement with the host on ≥ 16 seeds, plus a negative control.
  - Needs a D-entry amending D-009.
  - Payoff: niche (tiny lattices, ≥ 10⁴ runs), but S-a is GE5's oracle.

### Phase 3: speculative (only behind GE0's gate)

- **GE5 Speculative-window exact `SequentialCPM` (S-b).**
  - Scope: one workgroup per replicate; the §2.2 dependency oracle from
    footprint/claims/reads; parallel commit of the independent prefix; codegen flags for the
    W = 1 fallbacks (stop rule applies).
  - Accept:
    - bit-identical to GE4 on ROCm for every gate model and the OpenVT model;
    - measured window efficiency within 20% of K3's census;
    - ≥ 1.5× CPU-24 on an OpenVT 1400² ensemble (measured, PC), else stop.
- **GE6 Persistent per-replicate checkerboard (C-b)** for lattices ≤ 10⁵ sites: K MCS per
  launch, with phases and the fused lifecycle in-kernel and the staged fallback kept.
  - Accept: bit-identical to GE2; ≥ 3× GE2 on R × 150×5 and R × 72² batches.
  - Gate: only if an inference/UQ workload of ≥ 10⁴ small runs is on the roadmap.
- **GE8 Device observables.** Per-replicate save-time reductions into `(n_obs, R, n_saves)`,
  with SII access. Accept: values equal the host observables computed on copied states.

### Not recommended now

- **An interleaved replicate layout:** only after GE2 data shows coalescing is the
  bottleneck.
- **C-a, a serial checkerboard per thread.**
- **A Sultan-style block-sequential algorithm.** It is a new algorithm. It would need its own
  spec, a D-entry and statistical validation; revisit it for single huge lattices, not for
  ensembles.
- **Moving reproductions to `CheckerboardCPM` for speed** without a per-model deviation row
  and a re-run of the affected targets. That is the maintainer's call (R2).

**Cheap and high-payoff:** GE0, GE0b, GE3 (helps the CPU too), GE1 + GE2 for checkerboard
sweeps, and GE7. **Speculative:** GE5 (the only route to fidelity-preserving GPU ensembles),
GE6 and GE8.
