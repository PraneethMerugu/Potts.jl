# Progress log


## 2026-09-29 — Phase 1 start (commit 7b0a81b)

- **M1.1 done.** Root workspace (`Potts` + `lib/LocalMath` + `lib/CorePotts` and their test
  projects), one gitignored Manifest, `CLAUDE.md`. A clean clone instantiates and
  precompiles in 9 s (CorePotts 1.9 s).
- **M1.2 done.** LocalMath subtree, nested `[workspace]` removed; 1947/1947 tests pass in the
  workspace (`GROUP=LocalMath`, 2 min 19 s).
- **M1.3 imported, not built.** MakiePotts subtree is in `lib/MakiePotts`, outside the
  workspace until M2.10 (it depends on the legacy Potts API).
- **M1.4 mostly done.** CorePotts is rewritten from FusedCPM against INTERNALS §1: 7763/7763
  tests pass in 5 s. `DEIntegrator{Alg,false,S,Int}` subtyping works. Still open: JET/AllocCheck
  gates.
- **Bugs found and fixed while testing:**
  - `shift`, `coordinates` and `color_site` boxed a captured variable reassigned inside an
    `ntuple` closure, costing 157 KB per MCS. The rule is now in CLAUDE.md.
  - The checkerboard colour vector was abstractly typed (`Vector{Color}`), so every launch
    dispatched dynamically.
  - Claim-buffer parity reset to buffer 1 every MCS. With an odd colour count the first
    colour used an uncleared buffer, which silently caused spurious claim losses. A
    regression test now covers it.
  - `Metropolis()` stored a Float64 offset, which is invalid IR on Metal. The default is
    now exact `0`, and float offsets are stored as Float32 on non-CPU backends
    (`_device_law`).
- **Warm throughput**, Graner–Glazier 256², 8 threads, M1 Pro:

  | Algorithm | Backend | MCS/s | ns/attempt | alloc/MCS |
  |---|---|---|---|---|
  | Sequential | CPU | 450 | 33.8 | 0 |
  | Checkerboard | CPU | 620 | 24.6 | 57–60 KB (KA launches) |
  | Checkerboard | Metal (Float32) | 1670 | 9.1 | 58 KB, launch-bound at this size |

- **Next:** M1.4 JET/AllocCheck gates, M1.4b transition-matrix oracle, M1.5 benchmark suite
  and `reference/` environment (CI parts deferred: local only).

## 2026-09-29 — M1.4 gates and M1.4b oracle

- **QA gates** (`lib/CorePotts/test/qa.jl`, skip with `COREPOTTS_QA=false`): JET `@test_opt` is
  clean on `sequential_mcs!`, `checkerboard_mcs!` and both `step!`s; AllocCheck finds no
  allocations in `sequential_mcs!` or a hand-written ΔH. `init` is deliberately not gated:
  resolving a relation fixes K at run time, a one-time function barrier.
- **Exact oracle** (`lib/CorePotts/test/oracle.jl`):
  - A self-contained re-derivation of both algorithms' stated semantics (random-site
    attempts; colour classes, uniform colour order, pre-colour proposals, claim
    resolution by uniform priorities). It propagates the exact state distribution on a
    closed 3×2 lattice for 2 MCS.
  - Scored against 40k seeds with pooled χ² as a Wilson–Hilferty z: sequential z = 0.00,
    checkerboard z = −0.76, and a T = 5 mutant against exact T = 4 gives z = 11.9.
- **Preflight found a latent race.** `CPMFunction` defaults to `Footprint(read = 1)`, so a
  wider contact relation (e.g. `NeighborOrder(3)`, radius 2) would have run the checkerboard
  at stride 2. `init` now rejects a declared read radius smaller than the proposal/contact
  radius. The symbolic compiler (M3) must derive the footprint itself.

## 2026-09-29 — M1.5 (local parts)

- **Benchmarks.** `benchmark/` is a workspace member: `graner.jl` (fresh-process TTFX and warm
  throughput), `benchmarks.jl` (BenchmarkTools `SUITE`), and the Graner baseline data with
  provenance. The results table is in `benchmark/README.md`.
  - Sequential 72²: 0.19 s to the first MCS, 0.018 s remake plus first MCS, 25–31 ns/attempt.
  - Legacy: 1.9 µs/attempt at 16 attempts/site and 62–67 s cold compile.
  - Metal 576²: 3.25 ns/attempt.
- **CPU launch fix.** A multithreaded KA CPU launch of a ~1300-site colour cost ~120 µs of
  task spawn and sync. 8 threads ran 6× slower than 1 thread at 72². CPU workgroups are now
  sized from an 8192-site grain: small colours run inline as one workgroup, large colours
  get one workgroup per thread.
- **Manifest.** Adding Metal re-resolved the workspace Manifest (GPUArraysCore
  0.2.1 → 0.2.0). All groups still pass.
- **Reference stack (D-021).** `reference/Project.toml` pins the five legacy repos by full
  SHA via `[sources]` URLs, with a committed Manifest. It is not a workspace member. Run
  it with `GROUP=Reference`, which is not part of `All`. Legacy `SequentialCPM` at
  427dc2e2 allows only `AttemptsPerSite(1)`, so its MCS equals ours.
- **First legacy parity look.** Graner 72², 320 MCS, heterotypic fraction of cell–cell
  Moore bonds over 8 seeds:
  - legacy: 0.342 (0.327–0.358)
  - new: 0.346 (0.308–0.387)
  - The difference, 0.004, is within one standard error (~0.01).
  - The new code's contact convention (unordered pairs, ΔH as in legacy) is confirmed:
    doubling J moves the result away from legacy, to 0.389.
  - Formal KS parity is M2.1. Legacy used `ForbidExtinction`; the new core has no
    extinction policy yet (no cell vanished in these runs at λ = 1, V0 = 40).
- **Performance note for M2/M3.** Sequential runs at ~25–31 ns/attempt against FusedCPM's
  ~20. The hand-written ΔH resolves kinds through a closure per neighbour. Generated code
  (M3) should hoist the old/new kind lookups.

## 2026-09-29 — M2.1 (commit 0864882)

- **Relations.** `Weighted(spec, w)` stores per-offset `Float32` weights, which are
  device-safe. Unweighted relations use weight `Int32(1)`, so counts stay integers.
  `CPMProblem(...; relations = (; surface = ...))` exposes named relations as `ctx.<name>`.
  Preflight checks every relation's radius against the footprint and rejects a surface
  relation that includes the origin.
- **Primitives.** `surface_change` (δ for the old and new cells only, accumulated in the
  tracker's type), `surface_delta`, `commit_surface!`, `recompute_surface`, `site_delta`.
  `contact_delta` handles weights and takes any relation.
- **Tracker precision.** Weighted Float32 surface trackers hit rounding errors near 1e-5
  relative in ΔH, and would drift over long runs. The tracker type is the user's choice
  (`recompute_surface(...; T = Float64)` on CPU); Float32 stays available for Metal.
- **Tests.** Brute-force ΔH with contact + volume + surface over weighted and unweighted
  relations, in 2D and 3D with mixed boundaries. Trackers are checked against brute force
  after every copy and after full sequential and checkerboard runs (rtol 1e-12).
- **Parity (D-022).** The `Potts` test group compares against committed legacy samples
  (`reference/data/graner_parity.tsv`, 16 seeds from `reference/sample_graner.jl`,
  16 s/seed). All KS D values are below the α≈0.001 critical value 0.69:

  | observable | D | t |
  |---|---|---|
  | hetero fraction | 0.25 | −0.09 |
  | edge bonds | 0.44 | 2.36 |
  | cell bonds | 0.13 | 0.53 |

  Edge bonds was re-checked with 64 new seeds: 560.2 ± 1.0 against legacy 562.6 ± 2.3,
  t ≈ 1, so it was chance.
- **Deferred.** Per-axis spacing moves to M2.2/M2.4, where moments and fields consume it.
  A Float64 field in `Lattice` would be invalid on Metal.

## 2026-09-29 — M2.2 (commit 6e525c1)

- **Moments** (`geometry.jl`). Each cell has an integer anchor and exact `Int64` sums of
  minimum-image offsets (ties at +n/2 resolve to +, per the adjudication). When the mean
  offset reaches ±2 the anchor re-centres inside `commit_moments!`, shifting the sums
  exactly; this is safe because the cell is claimed.
  - No drift, and no Float32 precision loss on Metal: floats appear only in the final
    division.
  - Valid while cells span less than half of each periodic axis.
- **Queries.** `centroid` (wrapped), `centroid_shift` (δcentroid for drives),
  `covariance`, `principal_moments` (closed-form 2×2 and 3×3), and `shape` with the
  CompuCell3D descriptors of AUTHORING §12.4 (major/minor length, semiaxes, elongation,
  eccentricity, orientation).
- **Site trackers** (`trackers.jl`). Site sums work for any additive isbits type
  (`SVector` for structured owner sums). Site minima are exact on gain; a cell that loses
  its minimum-holding site is marked `stale` (its value is a lower bound) until
  `recompute_site_min!` at a sync point.
- **Tests.**
  - Trackers match brute-force unwrapped geometry after sequential and checkerboard runs
    in 2D and 3D, with every cell straddling seams.
  - Analytic box shapes in 2D and 3D; `centroid_shift` equals the committed change.
  - Site-sum and site-minimum invariants.
- **GPU group** (`COREPOTTS_GPU=metal`, 86 checks). Surface, volume and moment trackers are
  exact on Metal. CPU/Metal statistical parity: t = −0.49 on 12 + 12 seeds.

## 2026-09-29 — M2.3 and D-033 (commit 6fd6998)

- **D-033.** Measured LocalMath against plain KA on one 5-point Laplacian at 256²:

  | | first execution | warm |
  |---|---|---|
  | LocalMath | 8.2 s | 1.77 ms |
  | plain KA | 0.16 s | 0.31 ms |

  CorePotts phases are therefore generated KA kernels, and CorePotts does not depend on
  LocalMath. LocalMath stays as an optional stage runtime, wrapped as a phase. INTERNALS
  §3 is amended.
- **Phases** (`phases.jl`). The protocol is `phase(st, p, ctx, key, mcs, backend)`,
  enqueued without host sync, with launches counted in `stats`. Built-in kinds:
  `SitePhase`, `CellPhase`, `CopyPhase` (double-buffer publish), and `HistoryPush` (ring
  buffers; `history_slot(depth, mcs, lag)`). `Phases(before_mcs, after_mcs)` lives in
  `CPMFunction.phases`.
  - State paths are compile-time `Part{A,B}` accessors, one pair per phase. A
    heterogeneous tuple of pairs defeated inference ("failed to optimize due to
    recursion").
- **State.** `CPMState` gains `history`. `initial_state` validates site shapes, the cell
  last dimension and 1-element model arrays. `clear_on_copy!` provides the
  accepted-copy affect.
- **Bugs fixed:**
  - Saved states aliased the live state on CPU, because `Adapt.adapt(Array, ::Array)` is
    the identity. `current_state` now deep-copies on CPU. Snapshot regression tests added.
  - Kernels received the whole `CPMFunction`, which is not isbits once phases or a
    symbolic `sys` are present. They now receive `DeviceFunctions` (the five
    per-proposal functions).
- **Tests.**
  - The Jacobi site update equals a host reference exactly, under both algorithms.
  - Phase randomness is address-keyed, and equal to host draws.
  - Cell-phase growth, history lags, and the clear-on-copy age invariants (checked with a
    per-site copy counter).
  - Metal phases ≈ CPU. JET is clean on `step!` with phases.

## 2026-09-29 — M2.4 (commit 8f0ac2d)

- **Fields** (`fields.jl`). `laplacian` and `gradient` are second-order and take per-axis
  spacing: periodic axes wrap, closed axes are zero-flux (mirror). `owner_kind` is the
  secretion helper.
  - `FieldStep(field => scratch, rate; dt, substeps)` is an explicit Euler phase with
    double-buffered publication after every substep. `stable_substeps` gives the CFL
    count.
  - Per-axis spacing arrives: `CPMProblem(...; spacing)` → `ctx.spacing`, typed by the
    user (Float32 for Metal).
- **Tests.**
  - A Fourier mode decays by exactly the discrete factor (rtol 1e-10), including
    anisotropic spacing.
  - Mass is conserved on periodic and closed lattices (rtol 1e-12).
  - Substeps are equivalent to smaller dt; secretion–decay reaches the analytic total mass;
    the gradient and Laplacian of a ramp are exact.
  - Metal ≈ CPU.
- **Moved.** Merks parity moves to M2.5, where it needs chemotaxis.
