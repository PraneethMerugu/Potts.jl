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

## 2026-09-29 — M2.5 and M2.6 (commit 785ef32)

- **Drives** (`drives.jl`): `is_extension`/`is_retraction` (legacy definition: medium to
  cell), `chemotaxis_delta`, `act_mean`/`act_delta` (owner-filtered, plain or legacy
  shifted GM, D-034). `CPMFunction(...; bias)` adds to log α (`ΔH_eff = ΔH − T·bias`), and
  `FieldStep(...; lower)` provides the legacy clip at 0.
- **Constraints:**
  - `locally_connected`: N-D, a bitmask flood fill over the 3ᴺ−1 Moore neighbourhood.
  - `merks_connectivity`: the exact legacy rule.
  - `forbid_extinction`.
- **Tests.**
  - `locally_connected` agrees with an independent flood fill on thousands of random
    neighbourhoods in 2D and 3D.
  - Cells stay globally face-connected under hot dynamics with the constraint (both
    algorithms, 2D and 3D) and fragment without it.
  - Bias is identical to −T·b in ΔH; forbid_extinction; Act means.
- **Legacy parity** (`reference/sample_models.jl` → `reference/data/{merks,wortel}_parity.tsv`,
  64 seeds, saved MCS 2–40). Ported as `test/parity/models.jl` (the hand-written oracle
  for M3's codegen). KS per MCS and observable: Merks 15/15, Wortel 9/9.
  - The first Merks run failed (volume 11.4 against 7.8). The bisection isolated
    connectivity, and legacy CorePotts treats out-of-domain neighbours as medium (D-034).

## 2026-09-29 — M2.7 (commit 48a43bc)

- **Frozen sites.** `CPMProblem(...; frozen = mask)` builds `ctx.mobility`: `AllMobile()` by
  default (zero cost), otherwise `MaskMobility` (device mask plus mobile index list).
  Frozen sites are never targets or sources, and N counts mobile sites; they still count
  in contact energies (adjudication §2).
- **Queries** (`spatial.jl`). `is_boundary_site`, weighted `count_neighbors`, and the
  `CellReduce` phase (atomic per-cell +/max/min of any site expression). Float max/min
  use a CAS loop, since UnsafeAtomics has no float max. This covers owner sums, means,
  predicate counts and structured sums.
- **Contact graph.** `contact_graph` (host CSR: neighbours plus interface measure, medium
  separate) with `neighbors(g, c)` and `contact(g, c, n)`, as in CompuCell3D's
  NeighborTracker.
- **Field BCs.** `laplacian`/`gradient` take `bc = ((low, high), …)` per closed face:
  zero flux, or a cell-centred Dirichlet value (ghost = 2v − c).
- **Tests.** Frozen invariants and attempt counts under both algorithms; predicates;
  reductions against the host, including empty-cell identities; the contact graph
  against brute force (2.5k checks); Dirichlet walls reach the exact linear profile.
  Metal covers frozen sites and reductions (163 GPU checks).

## 2026-09-29 — M2.8 (commit 1c84438)

- **Lifecycle** (`lifecycle.jl`, D-035).
  - `Lifecycle(trigger; normal, kind, divide!, every)`, where the trigger returns
    `EVENT_DIVIDE/REMOVE/TRANSITION`.
  - Division plane through the centroid: `AlongMinorAxis{T}`, `AlongMajorAxis{T}`,
    `RandomPlane{T}` (float-typed, so Float32 on Metal), or any vector. Principal axes
    use closed forms in 2D and 3D.
  - Daughters take free ids lowest-first, with generation + 1 on reuse. Every non-tracker
    cell quantity is copied from the parent, then the `divide!` rule runs (e.g. a
    conservative split).
  - Removal sends sites to the medium. Transitions set kinds. Exhausted capacity defers
    the event and counts it. `with_capacity` preallocates slots.
  - Trackers (volume, surface, moments) are rebuilt exactly via `rebuild_trackers!`.
- **Bug fixed.** `init_moments` anchored cells at a corner, so a cell longer than half a
  periodic axis was wrapped (a 12-long box on 20 had centroid 6.8 instead of 8.5).
  Anchors are now the per-axis circular mean.
- **Tests.**
  - Exact halves for 2D across both seams and for a 3D box.
  - Removal/transition, id reuse + generation + copy + rule, deferral.
  - A growth → division run keeps every tracker exact (both algorithms).
  - Metal division (169 GPU checks).
- **Parity.** OpenVT monolayer, a scheduled division against legacy
  (`reference/sample_openvt.jl`), 18/18 KS checks. Legacy `AtMCS(1)` means the boundary
  after the first MCS (our `mcs == 0`).

## 2026-09-29 — M2.9 (commit 69b0cfd)

- **Link store** (`relationships.jl`). Links are fixed-degree padded adjacency
  (`st.cell.links`, `maxdeg × capacity`) plus `link_<name>` payload matrices, chosen over
  a CSR that would need rebuilding. They are GPU-friendly and grow with capacity.
  `add_link!`/`remove_link!`/`remove_incident!`/`linked`/`link_count` are symmetric.
- **Energies.** `link_delta` gives ΔH over links incident to old/new from `centroid_shift`
  (the old–new link counted once), with periodic-safe `centroid_distance`.
  `link_claims(cell, prop, Val(D))` supplies checkerboard claims for partners. Exact, but
  about 2× slower relaxation per MCS; omitting it is the user's stale-read trade.
- **Rules.** `HostPhase(f!; every)` is a synchronizing host phase for rule-based link
  creation, removal and retuning (e.g. from `contact_graph`).
- **Lifecycle policies.** Daughters start unlinked (link data is excluded from the default
  Copy); removed cells drop incident links (RemoveIncident).
- **Tests.** Bookkeeping; `link_delta` against brute-force centroid distances (200
  proposals, including linked old–new pairs, across seams); a spring relaxes to
  equilibrium (13.2 with checkerboard + claims against sequential's 13.1); the
  host-rule and lifecycle policies (347 checks).

## 2026-09-29 — M2.10 (commit bd713f5)

- **Checkpoints** (`checkpoint.jl`). `checkpoint(integ)` captures state, MCS, key and
  stats; `save_checkpoint`/`load_checkpoint` use Serialization (Julia-only, D-032 spirit).
  `init(prob, alg; checkpoint)` refuses a checkpoint whose model fingerprint differs.
  `reinit!` restores state and stats in place. Continuation is exact: N MCS equals
  k MCS, checkpoint, reload, N − k MCS, bit for bit, for both algorithms (RNG is
  address-keyed, so no stream state needs saving).
- **Saved states.** Snapshots are deep copies on CPU (they previously aliased the live
  state). Accessors `ownership`, `cell_kinds`, `cell_generations`, `volumes`.
- **MakiePotts** (also closes M1.3) now depends on CorePotts only: `renderframe` for
  `CPMState` and `PottsSolution` (frozen medium sites render as obstacles, spacing from
  the problem). Workspace member with its own test project; GROUP=MakiePotts in the root
  dispatcher. All MakiePotts suites pass, including Aqua and the fresh-process load orders.
- **Full run.** GROUP=All green (4 min 43 s wall); Metal 169/169.

## 2026-09-29 — M2.11 (commit f67f82c)

- **Device contact table** (`spatial.jl`). `empty_contacts(maxdeg, n)` + `ContactPhase(:rel)`
  rebuild a fixed-degree neighbour table on the device (atomic CAS row insertion, atomic
  measure sums); `contact_slot`/`contact_measure` query it from device code. A full row
  increments `contact_overflow[c]` instead of throwing. Matches the host CSR
  `contact_graph` for weighted and unweighted relations (CPU and Metal).
- **Metal group** (260 checks, `GROUP=GPU` in the root dispatcher, opt-in):
  - Act + chemotaxis + `locally_connected` + extinction veto + bias: trackers exact, every
    cell stays connected, chemotactic drift agrees with CPU. An 8-seed run gave
    t = 2.4, so it was re-checked offline with 32 seeds: CPU 0.0360, Metal 0.0350,
    t = 0.33 (sequential 0.042; the checkerboard rate differs, as expected).
  - Merks connectivity with Barker acceptance (volume statistics agree).
  - 3D `NeighborOrder(2)` contact and surface: surface/volume/moments exact.
  - Links with `link_claims` (spring relaxes to rest length), `HostPhase` link rules,
    the contact table.
  - Checkpoint continuation is bit-exact on the device (the Metal run is reproducible).

## 2026-09-29 — M2.10a (commit cf898ab)

- **Compartments** (`compartments.jl`, D-036). `st.cell.cluster` + `init_clusters`,
  `same_cluster`/`cluster_of`, atomic cluster volume/surface trackers with deltas
  (`cluster_volume_delta`, `cluster_surface_change/delta`), `cluster_claims`.
  `Lifecycle(…; clusters = true)` divides a cluster as a unit along one plane through the
  cluster centroid (host plane from cluster moments; the partition kernel gains a
  per-cell `bias` = (member centroid − cluster centroid)·n). Lifecycle events re-root
  clusters; `with_capacity` makes free slots their own cluster.
- **Tests** (684 CPU + 5 Metal):
  - Cluster deltas equal brute-force energy differences on 400 random proposals, and
    trackers stay exact after commit.
  - Nucleus/cytoplasm cells under both algorithms: the nuclei's interface with their own
    cytoplasm is 0.97 (sequential) and 0.99 (checkerboard), against 0.85 for a neutral
    internal J.
  - The cluster divides as a unit (68/12 | 68/12, daughters form cluster 3, rules run per
    member). Non-cluster division keeps the daughter in its cluster; root removal
    re-roots the cluster.
  - On Metal: trackers exact with claims; cluster division.
- **Test-design note.** Without an extinction veto the nuclei vanish (λ = 1 volume cost
  is below the contact savings); the test model forbids extinction.
- Phase 2 is complete. Next: Phase 3 (the Potts symbolic front end).

## 2026-09-29 — M3 slice 1: symbolic front end (commit 1027300)

- **Pipeline.** `@potts_model` → `PottsSystem` → `mtkcompile` (`CompiledPottsSystem`) →
  `PottsProblem(csys, op, tspan; T)` → `CorePotts.CPMProblem` with
  RuntimeGeneratedFunctions (`drop_expr`'d). Design choices are in D-037.
- **Supported so far.**
  - Energies: `cells(kinds) => E(volume, surface, kind, cell vars)`,
    `contacts[(rel)] => E(kind, kind′, owner, owner′, weight)`, `sites => E(owner, kind, …)`.
  - `@drive copy => …`; `@constraint` (expressions, `connectivity(k; rule)`,
    `no_extinction`); `@on_copy`; `@after_mcs`/`@before_mcs` (site and cell, `Every(n)`,
    scratch buffers when neighbours of an updated variable are read).
  - `@equations`: field PDEs with `Δ`, auto substeps from the Δ coefficient; per-cell
    ODEs by explicit Euler. `@divide` (principal/major/random/fixed plane, `x => value` or
    `Split()`). `@relations`.
  - Folds over relations (`sum, prod, mean, geomean, geomean_shifted, minimum, maximum,
    count, any, all`); kind-indexed parameters; `total_energy`, `energy_change`;
    `expression = Val(true)`.
- **Verification** (`test/symbolic.jl`, `test/parity/symbolic_models.jl`).
  - Graner, Wortel Act, Merks and OpenVT authored in the AUTHORING surface. Their
    generated ΔH, constraints and commits equal the hand-written oracle ports on
    ~1200 proposals each, and 15-MCS trajectories are bit-identical.
  - The energy self-check is exact (0.0).
  - Legacy KS parity passes through the symbolic problems (Graner 7/7, Merks 15/15,
    Wortel 9/9, OpenVT 18/18).
  - Symbolic Graner on Metal (`T = Float32`) agrees with CPU (t = 0.19); symbolic
    Wortel/Merks/OpenVT run on Metal with exact trackers.
- **Performance.** Generated Graner ΔH is identical to the hand-written one: one loop
  plus the closed-form volume delta. Symbolic Wortel runs at about 1.6× the hand-written
  time (a generic gather vs the specialised `act_mean`). First problem build is 0.2–1.3 s
  (Symbolics derivation plus RGF compile); rebuilds are about 1–50 ms and reuse the
  compiled code.
- **Bugs found.**
  - `gensym` names made every rebuild a new function type (18 s of recompiles in the
    parity tests). Fixed; now tested.
  - Extinct cells were dropped from `total_energy`. Fixed (D-037).
  - `ownership` name clash with CorePotts; the accessor is reused as the key.
- **Next** (remaining M3.1–M3.4):
  - `PottsParameters` + SII (`getu`, `setp`, `remake(prob; p = [λ => 2])`).
  - `@sweep` law propagation; model-scope variables; `@observed`; composition
    (`compose`/`extend`) on `ModelingToolkitBase.AbstractSystem`.
  - Relationships (`@relationship`, `edges`) and compartments in the surface.
  - Units; diagnostics with source locations.
  - Symbolic GPU tests in the GPU group.

## 2026-09-29 — M3 slice 2 (commits b22ad35 … fe139fe)

- **Acceptance law.** `CPMFunction(…; acceptance)` holds the model's law; algorithms
  default to `acceptance = nothing` (the model's, else Metropolis). `@sweep` propagates.
- **remake.** `remake(prob; p = [λ => 3.0])` and `remake(prob; u0 = [ownership => σ, …])`
  go through CorePotts hooks. The parameter type is kept, so nothing recompiles.
- **Relationships in the surface.** `@relationship`, `x(edge)` payloads,
  `edges(rel) => E(a, b, distance, …)` (`link_delta` + automatic `link_claims`), and
  `@link`/`@unlink … when = …, every = n` (host phases over the contact graph); initial
  links come from the operating point.
- **Observed and SII.**
  - Model variables `x(model)` with population folds over `cells(k)`/`sites`, run as
    `ModelPhase` (a single work item; also on Metal).
  - `@observed`; `sol[x]` for any quantity or expression via SII on `PottsModelInfo`;
    `getp`; `observe`.
  - `PottsParameters` (D-012) is an isbits NamedTuple wrapper.
- **QA** (`test/qa.jl`): the generated Graner/Wortel/Merks/OpenVT `step!` is JET-clean;
  a warm sequential MCS allocates 0 bytes; Aqua is clean. This found and fixed one
  runtime dispatch in the lifecycle daughter copy.
- **GPU** (`POTTS_GPU=metal`, part of `GROUP=GPU`): the symbolic models with
  `T = Float32` run with exact trackers. Graner H agrees with CPU (29380 vs 29389),
  springs relax, and model phases run.
- **TTFX** (PrecompileTools workload), fresh process, warm cache: `using Potts` 4.6 s,
  build 1.5 s (was 4.5 s), first solve 0.5 s, so build + first MCS is 7.2 s against the
  15 s gate.
- **Code review** (a subagent over `src/`) found 10 issues, all fixed with regression
  tests (commit 5809718):
  - Four were wrong physics without an error: unmirrored cell variables in contact
    terms; volume/surface allowed outside cell terms; the surface δ fused twice;
    division rules not gated by kind.
  - `@on_copy x[new]` wrote `x[0]`.
  - Float64 leaked into Float32 code.
  - Macro hygiene: indexed assignment, eager ternary/`&&`, and generators over
    non-relations.
  - Parameter keyword overrides did not work.
  - A gather counter made the generated code non-deterministic.

## 2026-09-29 — M3 slice 3: temperature by kind, library one-liners, frozen kinds

- `@sweep Metropolis(; temperature = Tk[kind], combine = min)`: when the temperature
  depends on the cell, it is evaluated for the new and old cells and combined. If one side
  is the medium, only the other cell's value is used.
- The library one-liners `Volume(kinds...; target, strength)`, `Surface`, `Adhesion(J)`
  and `Chemotaxis(c; strength, kinds, extension_only)` expand to the explicit terms. A
  Graner model written with them has the same ΔH on every tested proposal.
- `@kinds medium wall[frozen] cell`: sites of frozen kinds go into CorePotts' `frozen`
  mask, so walls and obstacles never move.
- Tests: every Potts suite (with QA/Aqua) and CorePotts (9021) pass.

## 2026-09-29 — M3 slice 4: compartments in the authoring surface (D-036)

- **Builtins:** `cluster`, which can be indexed (`cluster[owner] == cluster[owner′]` for
  internal contact energies), plus `cluster_volume` and `cluster_surface`.
  - Cell updates, division conditions and observed quantities can read the cell's cluster
    trackers.
  - Cell, contact, site and edge energies cannot: those trackers change when other
    members copy, and this is checked.
- **Energy domain** `clusters(kinds...)`, filtered by the kind of the root. ΔH is derived
  like cell terms, over the clusters of old and new, and is zero within a cluster. Cluster
  surface change comes from `cluster_surface_change`. `total_energy` sums over the roots.
- **Operating point** `cluster => ids`, with any ids; equal ids form one cluster. `cluster`
  is exported like `kind`.
- **Checkerboard claims** cover the clusters of old and new, together with any link
  claims.
- **Division:** `@divide clusters(k) when = …` gives `Lifecycle(clusters = true)`. State
  rules apply to every member, gated by the root's kind. A model cannot mix cell and
  cluster divisions.
- **Tests:**
  - The symbolic nucleus/cytoplasm model equals the hand-written CorePotts model
    (ΔH < 1e-9 on 400 proposals), and the energy self-check is exact.
  - Trackers stay exact through runs.
  - A cluster division yields 18 two-kind clusters, and mass is split per member.
  - JET/AllocCheck QA is clean.
  - On Metal, the trackers are exact.
- A JET finding fixed in CorePotts: `recompute_surface` with a `T` keyword dispatched at
  run time in the lifecycle tracker rebuild. It now goes through positional
  `::Type{T}` helpers.

## 2026-09-29 — SciML ensembles/callbacks; review of slices 3–4

- **Ensembles:** `EnsembleProblem(prob::CPMProblem)` makes trajectory `i` equal to
  `remake(prob; replica = prob.replica + i)` (Philox streams, D-005).
  - This holds with any scheduler and reuses one compiled model.
  - A user `prob_func` is applied first. If it leaves the seed and replica alone,
    trajectories still get distinct replicas.
  - `PottsStats` merge.
- **Callbacks:** `solve(…; callback = DiscreteCallback | CallbackSet)` checks callbacks at
  each MCS boundary, after the lifecycle and before saving.
  - `condition(u, t, integ)` and `affect!` see the live state and may replace `integ.p`
    (for example with `remake(prob; p = [:T => 0.0]).p`).
  - `initialize` and `finalize` run.
  - Continuous callbacks are rejected.
  - The SciML names are re-exported, as solver packages do.
- **Code review** (a subagent over `6c05049..61bbd02`) found 5 issues, all fixed with
  regression tests:
  1. **Wrong physics, no error:** a dead cluster root's id was handed to a daughter,
     merging two clusters. Lifecycle planning now never frees ids that still name a
     cluster.
  2. **Wrong physics, no error:** re-rooting could change a cluster's root kind, switching
     `clusters(k)` terms off. Roots are now stable (they change only when the root dies,
     then to a member of the same kind). At init, the root is chosen among the kinds that
     name clusters, whatever the numbering.
  3. `remake(prob; u0)` kept the old frozen mask. A new CorePotts hook, `remake_frozen`,
     recomputes it.
  4. Population folds over cells read the outer cell's cluster trackers.
  5. `uses_clusters` missed division conditions, division rules and observed quantities.
- **Also fixed:** a macro parse bug. `when = …, along = (1.0, 0.0)` with no trailing rule
  splatted the tuple into state rules.

## 2026-09-29 — Irregular lattice domains (M2.1b, first half)

- **CorePotts.** `Lattice(dims; boundary, domain = mask | x -> Bool)` gives a
  `Lattice{N, M}` with an optional mask.
  - `shift` reports a pair as outside if either site is outside the domain. This is
    symmetric, so brute-force sums over all sites agree with per-copy deltas. Contacts,
    surfaces, gathers, proposals and field stencils (zero flux) therefore all stop at the
    domain edge with no changes to their code.
  - `CPMProblem` freezes out-of-domain sites and requires them to be medium.
  - Field steps and site phases leave out-of-domain sites untouched.
  - The mask moves to the device with the context. Host code (tracker rebuilds, cluster
    planes, `HostPhase`) uses `host_lattice`.
- **Surface:** `@lattice Lattice(dims; domain = …)`. The mask is evaluated once into the
  `LatticeSpec`.
- **Tests:**
  - A disk domain on CPU (sequential and checkerboard) and on Metal (checkerboard, field,
    division with a host tracker rebuild).
  - ΔH equals the brute-force energy difference on every edge-adjacent proposal.
  - Diffusion conserves mass inside the domain and never touches outside sites.
  - The symbolic `DiskSorting` model has an exact energy self-check.
- Hexagonal geometry remains.

## 2026-09-29 — M3 slice 5: composition

- `extend(sys, base)` (a method of MTK's `extend`) and the `@extend a, b = base = Base(…)`
  section, as in MTK:
  - Names are bound through `Potts.lookup`.
  - Terms and rules accumulate base first. Same-named parameters and variables are
    redeclared by the extension.
  - Lattice, sweep and kinds are inherited when not declared.
  - The base's kinds must be a prefix of the extension's, because expressions refer to
    kinds by number.
- `sol[:name]` / `getu(sol, :name)` resolve variables, observed quantities and builtins
  by name.
- **Tests:**
  - A chemotactic extension of the Graner model has the base's exact energy change and an
    exact self-check.
  - An extension adds a frozen wall kind with a wider contact table and overrides a base
    parameter.
- MTK-style `compose` (namespaced subsystems) applies to ODE components and is part of
  M4.1.

## 2026-09-29 — M3 slice 6: diagnostics with source locations

- `@potts_model` records where each energy, drive, constraint, update, equation,
  division, link rule and observed quantity was written (`PottsSystem.sources`; merged by
  `extend`).
- `mtkcompile` validates each statement on its own and lowers it once in the scope it
  will run in. Errors that used to appear only while building a problem now appear at
  compile time.
  - Every error is re-raised with the statement and its location, for example
    `site variable x needs a site: write x[target] … in @energy cells(1) => x at model.jl:12`.
  - Descriptions are built only when reporting, because printing symbolic expressions is
    slow.
- **TTFX:** `using` 4.4 s, construction 0.65–0.9 s, `mtkcompile` 0.01 s, problem build
  1.5 s, first solve 0.74 s. Total 7.6 s against the 15 s gate.
  - `@extend` plumbing is emitted only for models that use it; it had added 0.45 s to
    every model's first construction.

## 2026-09-29 — PottsModels package (M4.2 started; M3.3 parity from its sources)

- `lib/PottsModels` is a new workspace package (`GROUP=PottsModels`). It contains:
  - `GranerGlazier`, `WortelAct`, `MerksVasculogenesis` and `OpenVTMonolayer` as
    documented `@potts_model` sources, with citations.
  - `graner_glazier_state(scale)`. The legacy pre-equilibrated data moved from
    `benchmark/data` to `lib/PottsModels/data`.
- `@potts_model` supports docstrings (`Base.@__doc__`).
- The root parity tests (legacy KS parity and exact equality with the hand-written ports)
  now build their problems from the PottsModels sources.
- The package's own tests: every model builds and runs, has an exact energy self-check,
  and passes Aqua.

## 2026-09-29 — M4.1 slice 1: MTK components per cell (D-038)

- `@components [cells(k)] name = sys`:
  - Component unknowns become cell variables and parameters become model parameters,
    unless coupled with `@equations name.p ~ cell expression`.
  - Observed equations are substituted, and `t` maps to the builtin `time`.
  - Explicit ODEs join the cell ODEs, gated by kind.
- All cell ODEs advance in one generated kernel with the sweep's `ode_solver`
  (`ExplicitEuler` or `RK4`, with substeps).
- A component's RHS reads the model's cell quantities through couplings. The model reads
  component state as `name.x` in energies, division conditions and rules, updates and
  observed quantities.
- `@components clock = clock` resolves the right-hand side to the caller's global.
- **Tests:**
  - Euler and RK4 match their exact discrete solutions to 1e-12.
  - The coupled clock is exact and resets on division.
  - Kind scoping, `remake` of component parameters, and `sol[:decay₊y_c]`.
  - JET QA of the component kernel, and Float32 RK4 on Metal.

## 2026-09-29 — 3D through the authoring surface; generated-code benchmark

- The `Sorting3D` test model runs on a 24³ lattice. It has:
  - a ball domain;
  - `NeighborOrder(2)` contacts (18 neighbours) and a surface energy;
  - a chemotaxis drive on a 3D field;
  - division along the principal axis with mass split.
- Its energy self-check is exact. Sequential and checkerboard runs keep exact volume and
  surface trackers, and nothing leaves the domain.
- Generated vs hand-written Graner–Glazier is recorded in `benchmark/README.md`: within
  6% at 72² and equal or faster at 288².
- Kind filters naming every cell kind are dropped at compile time.

## 2026-09-29 — Review of domains → components; registered functions

- **Code review** (a subagent over `6e2480a..7d44a45`) found 7 issues, all fixed with
  regression tests:
  1. **Wrong results, no error:** `@components other = clock` read and coupled the wrong
     component. Systems are now renamed to their binding.
  2. **Wrong results, no error:** couplings on component unknowns were silently dropped.
     Only component parameters can be coupled; anything else is an error.
  3. Kind tables were never checked against the number of kinds, so an extension adding
     kinds read out of bounds. `PottsProblem` and `remake` now require
     `length(kinds)` entries per axis.
  4. Fingerprints of models with domains changed on every rebuild, so checkpoints were
     rejected. `LatticeSpec` now has content-based `==`/`hash`, and fingerprints hash the
     core lattice.
  5. Site populations counted out-of-domain sites.
  6. Component values without defaults silently became 0. They must now be given in the
     operating point.
  7. Dirichlet face values were applied at interior domain edges. The edge is now zero
     flux.
  - **Also fixed:** couplings may read other components' state.
- Operating points accept names (`:λ`, `Symbol("clock₊τ") => …`), as `remake` does.
- **User-registered functions** (`@register_symbolic hill(x, K)` in the user's module)
  work in generated code, because function objects are interpolated as values. This
  makes MTK's `eval_module` unnecessary here.
  - One fix was needed: `expand` rebuilt the arguments of opaque functions, stripping
    Potts metadata. Cell-term deltas now expand over placeholders.

## 2026-09-29 — `rand()` in models; Akeeb leader/follower invasion

- **`rand()` in model bodies.** It is a symbolic draw with one stream per occurrence, numbered
  deterministically. It lowers to `uniform(T, draw(key, mcs, entity, stream))` in
  functions that receive the RNG key (MCS phases, the lifecycle trigger, division rules).
  Anywhere else it is an error, with a remedy.
  - Tests: draws are identical under sequential and checkerboard sweeps, fresh every MCS
    and for every site, roughly uniform, and change with the seed.
- **`PottsModels.AkeebInvasion`**, with `akeeb_state` and `akeeb_contacts`, ported from
  `SCDPotts/scripts/run_akeeb_proliferative.jl` (spec in `research/akeeb_*`).
  - The per-cell target volume grows by `rate` up to `V_max`.
  - The integer mitotic clock is an `@after_mcs` update.
  - Division happens when `clock > 75 + 50·rand()` and `volume > 20`, on a random plane,
    with `V_target` split and clocks reset.
  - Chemotaxis applies when the source or target cell is a leader, on the static cue
    `y − 1`.
  - Connectivity is enforced and extinction is forbidden.
  - The 99×60 slab has 308 cells (77 leaders), as in the SCDPotts MTK-bridge check.
    200 MCS take 2.4 s including compilation. Divisions occur with PP = 0.5 and none with
    PP = 0, as in the legacy audit.
  - Statistical parity against the SCDPotts runner: see the entry below (Merks rule).

## 2026-09-29 — PIFF import/export (M4.4, first half)

- `CorePotts.read_piff(io_or_path, dims) -> (labels, kind names, PIFF ids)` and
  `write_piff(io_or_path, labels, kinds; medium, ids)` handle CompuCell3D's initial
  format in 2D and 3D.
  - Coordinates are 0-based and boxes inclusive. Cells may span several lines, and medium
    lines are optional.
  - Errors are reported for boxes outside the lattice, overlaps, one cell with two types,
    and z ≠ 0 in 2D.
- Kind names can go straight into an operating point (`kind => Symbol.(kinds)`).
- MorpheusML import is pending: it needs a pure-Julia XML parser (Julia-only
  dependencies).

## 2026-09-29 — Centroid and displacement builtins (persistent motility)

- `centroid(k)` (cell scope) and `displacement(c, k)` (proposal scope) are building
  blocks for persistent or directed motion instead of a special-cased polarity feature.
  They lower to `CorePotts.centroid` and `CorePotts.centroid_shift` on the exact moment
  trackers, which are switched on whenever either name appears.
  - Misuse is an error with a remedy: `centroid` outside a cell scope, `displacement`
    outside a copy scope.
  - Observed quantities that use `centroid` are per cell.
- Tests:
  - The centroid matches the brute-force mean.
  - `displacement` matches the brute-force before/after difference, both when a site is
    added and when one is removed, and is zero for other cells.
  - A persistent walker (EMA polarity, μ = 1000) travels more than twice as far as an
    unbiased one over 60 MCS.
  - The model is JET-clean and allocation-free (QA list), and runs in Float32 on Metal
    with trackers matching the host recompute.
- Note: with an EMA polarity, μ must be large (hundreds or more), because the per-copy
  displacement is about 1/V.

## 2026-09-29 — Symbolic setters (M3.4)

- Declared state variables (cell, site, field, model) are now SymbolicIndexingInterface
  variables, indexed by `CorePotts.StateIndex(scope, name)`.
  - `integ[:px] = v`, `setu(integ, :px)(integ, v)` and `getu` all work. Built-ins such
    as `volume`, and expressions, stay read-only observed quantities.
  - Writes go to the live state, including device memory. `integ.u` is a host snapshot,
    so SciMLBase's default setter, which writes to `state_values(integ)`, would have lost
    them silently.
  - An array value must be the same size; a number fills the array.
- `integ.ps[:μ] = v` and `setp(integ, :μ)(integ, v)` swap in a new `PottsParameters` of
  the same isbits type. Nothing recompiles and there is no device upload.
  - `setp` on a problem is an error that points to `remake`.
  - `integ.ps` had been hidden by `PottsIntegrator`'s `getproperty`; it is restored.
- `getu`, `setu`, `getp` and `setp` are re-exported.
- Tests on CPU and Metal cover parameters, cell and model variables, size errors, and
  read-only built-ins.

## 2026-09-29 — Review 3 (42d448f..HEAD) and Akeeb parity

- Review findings, all fixed with regressions:
  1. **Out-of-range axes.** An axis beyond the lattice dimension in `displacement` or
     `centroid` read garbage and crashed with SIGILL. Axes are now checked at
     `mtkcompile`, and the `@inbounds` is removed.
  2. **`centroid` in energies.** It was silently ignored: its ΔH was always 0. It is now
     rejected, with a pointer to `displacement` in a `@drive`.
  3. **Empty cell slots.** `centroid` gave NaN for free slots; it now returns 0.
  4. **`rand()` in `@observed`.** It passed `mtkcompile` and failed on the first query.
     It is now rejected at compile time with a specific message.
- Not a bug: the reviewer flagged that PIFF accepts a cell box over an earlier medium
  box. That is intended, because CompuCell3D files list a whole-lattice Medium box first.
- **Akeeb parity** (`test/parity/akeeb.jl`, now in the Potts group; about 7 s):
  - Legacy reference: 8 SCDPotts seeds on the 99×60 lattice for 400 MCS, sampled with
    `reference/sample_akeeb.jl` into `reference/data/akeeb_parity.tsv`. Metrics are
    taken at MCS 200 and 400 (`reference/akeeb_metrics.jl`).
  - The new model is run for 16 seeds, and each metric must pass a Welch t test
    with |t| < 4.
  - The first comparison failed on connected components (t ≈ 5.6). The port used the
    default local connectivity rule, but legacy `LocalConnectivity` is the Merks (2006)
    ring rule.
  - With `rule = :merks`, every metric agrees (|t| ≤ 1.6). Divisions agreed under both
    rules.
  - Runtime: legacy takes about 80 s per seed, the new model about 0.2 s per seed.

## 2026-09-29 — History lags `Pre(x, k)` (M3.4)

- The DSL's `Pre` is now `Potts._pre`. `Pre(x)` is still MTK's `Pre`; `Pre(x, k ≥ 2)`
  becomes a registered `history_lag(x, k)`.
- Lowering: lower `x` as usual, then point its `st.site.x` / `st.model.x` reads at
  `_LagView(st.history.x, mcs, k)`. That is an isbits linear view of the ring slot
  `CorePotts.history_slot(depth, mcs, k)`, so kernels are unchanged apart from one offset.
- Ring depths come from the model's statements (`_history_depths`). `_initial_state`
  builds `history_buffer`s. `_phases` appends one `HistoryPush` per lagged variable as
  the last after-MCS phase.
- Semantics are checked exactly: lags of a counter and of a site array over 8 MCS,
  including the initial-value fill.
- The model is JET-clean and allocation-free (QA list), and runs in Float32 on Metal.
- Rejected with a remedy: lags of cell variables (rings do not follow capacity growth or
  division; chain `Pre`), and lags in energies (no clock) and `@observed` (the saved-state
  clock would be off by one).

## 2026-09-29 — Per-cell site reductions `integral(x)` (M3.4)

- `integral(x)` is a cell-scope sum of a site expression over the cell's sites.
  - Each distinct `x` gets a cell array `integral_<hash>`, filled by
    `CorePotts.CellReduce` (atomic adds; GPU-safe).
  - The reduce runs first in the after-MCS phases, first in the before-MCS phases when
    they read it, and once on the host at problem construction.
- Recompute versus maintain: `commit_site_sum!` is exact only if site values change
  solely through copies. Updates, fields and on-copy writes break that, so the compiler
  always recomputes at the boundary. That is one pass over the sites, and it keeps
  energies and drives free of the term, which is why they reject it.
- Observed-scope detection treats `integral(…)` as a cell quantity, whatever site
  variables it sums.
- Tests:
  - Exact against brute force after every MCS, under sequential and checkerboard sweeps.
  - Mean and count forms; `integral(1) == volume`.
  - Valid at t0; energies and drives rejected.
  - QA list; Metal Float32.

## 2026-09-29 — Units (M3.1)

- `[unit = …]` is now an option on `@parameters` (scalars and kind tables) and
  `@variables`, stored as MTK `VariableUnit` metadata.
- `mtkcompile` calls `_check_units(sys)`. It is a no-op, implemented by the weak
  extension `PottsDynamicQuantitiesExt`, which uses MTK's DynamicQuantities unit
  inference (MTK's choice, not Unitful as D-015 had it).
  - Rules for Potts operations: `at`/`at2`/`Pre`/lags/`integral`/`Δ` keep their
    argument's unit. `centroid`, `displacement` and `rand` are unitless. Folds follow
    their op. `&`/`|`/`!` need dimensionless arguments.
  - Checks: every term of H shares one unit; each update and division rule matches its
    variable; conditions and constraints are dimensionless; equations and observed
    quantities are consistent.
- Errors name the statement and the conflicting units.
- `using Potts` is unaffected. DynamicQuantities is a weak dependency and is in the test
  project.

## 2026-09-29 — Vector quantities; review 4 (3bef008..HEAD)

- **Vector quantities (`8788419`).**
  - `@variables p(cell)[1:n]` and `@parameters d[1:n]` declare scalar components
    `p_1…p_n`, tagged `vector`/`index`, and bind `p` as a `QuantityVector`.
  - `p[i]` is a component, `p[new]` is the vector at a cell, and `Pre(p)` is
    component-wise.
  - `p ~ rhs` in updates and equations is rewritten by the macro to `Potts._eq`,
    component-wise. Symbolics' `~` does not take vectors, and defining it for
    `Vector{Num}` would be type piracy.
  - Also available: `dot`, `norm`, `normalize` (zero-safe), `centroid()`,
    `displacement(c)`, per-component division rules, and operating-point / `remake`
    expansion (`:p => M`, `:d => [..]`, `Model(; d = [..])`).
  - A vector-authored persistent walker reproduces the scalar model's trajectory
    exactly.
- **Review 4 findings, all fixed with regressions:**
  - **Units error handler.** `DimensionError` fields are `q1`/`q2`; the handler read
    `x`/`y` and crashed.
  - **Units false positives.** Literal zeros in `ifelse`/`max`/`min` failed published
    patterns. They now take the other branch's unit, and `ifelse` conditions are still
    checked.
  - **Stale integrals.** Integrals were stale in saved and observed states, after
    division, and after `remake`. CorePotts `Phases` gained `end_mcs` (run after the
    lifecycle) and `at_init` (run when an integrator is created). Integrals refresh in
    both, and additionally after the sweep when after-MCS statements read them. Observed
    integrals are recomputed from the queried state. The construction-time fill is gone.
  - **`Pre(x, 1)`.** It used MTK `Pre`, the live value, while `k ≥ 2` read the ring, so
    the lag sequence skipped a step. All `Pre(x, k)` now read the ring.
  - **History timing.** History pushes moved to `end_mcs`, after the lifecycle.

## 2026-09-29 — Compound assignments, single writers, structural replacement (M3.4)

- **Macro.** `_combine_compound` folds the `+=`, `-=`, `*=` and `/=` writes to each
  target in an update block into one `x ~ Pre(x) op …`. Mixing `~` with compound writes,
  or additive with multiplicative ones, is an error at macro expansion.
- **Lowering.** MTK's `Pre` distributes into function arguments (`at(Pre(x), i)`);
  `_lower_at` now looks through it.
- **Compile.** Two updates of the same target in one phase and cadence are an error.
  Before, this was a silent race.
- **`extend`.** An extension's update, equation or observed quantity replaces the base's
  for the same target or name. This is the explicit structural replacement from the
  legacy G04 plan.
- Tests cover compound counters (model, cell vector, on-copy site), replacement through
  `@extend`, and the error cases.

## 2026-09-29 — Model-scope ODEs and model components (M4.1)

- `CompiledPottsSystem.model_odes`: equations on model variables, which used to be
  rejected as "not supported yet".
- `_model_ode_expr` runs the same Euler/RK4 steps as the cell ODEs, in a `ModelPhase`.
  The step generator is now shared (`_ode_locals`, `_ode_steps`).
- `@components model name = sys`: `ComponentSpec.domain` is a `CellDomain` or `:model`.
  Unknowns become model variables. Couplings go to model-scope expressions.
- A model variable with no initial value is an error that asks for it in the operating
  point.
- Tests:
  - Exact RK4 discrete factor for `D(a) ~ -a/2`.
  - A pharmacokinetic component dosed by the live-cell count matches the analytic
    solution, under sequential and checkerboard sweeps.
  - Metal Float32; QA list.

## 2026-09-29 — Adaptive host ODE integration (M4.1, D-038's deferred `ODEComponent`)

- `Adaptive(alg; kwargs...)` is an `ode_solver`. `_adaptive_phase` builds an in-place
  SciML right-hand side `f!(du, u, (st, p, ctx, mcs, c), t)` from the same lowered
  rates, and `_AdaptiveODE` keeps one integrator.
  - The integrator is created on the first call. After that, each call does `reinit!`,
    sets `p` and runs `solve!` to `t + dt`, per live cell or once for the model.
  - On CPU the state is aliased. On GPU it is copied to the host and the ODE arrays are
    copied back.
- Potts now depends directly on SciMLBase, KernelAbstractions and Adapt, which were
  already in the Manifest. The algorithms come from the user, so there is no new
  dependency.
- **Lowering fix.** Float functions cast their arguments with `_tofloat(T, x)`, which
  converts only integers. The old `T(x)` broke the dual numbers of implicit solvers'
  Jacobians. The Float32/Metal "never touch Float64" tests still pass.
- **`time` is now bound in the DSL preamble.** Before, `cos(time)` resolved to
  `Base.time`.
- Tests:
  - Tsit5 and Rodas5P on a decaying cell ODE, a stiff forced cell ODE and a model ODE
    with a population input, all against analytic solutions, under sequential and
    checkerboard sweeps.
  - `remake`; Metal Float32.

## 2026-09-29 — Hexagonal lattices (M2.1b)

- CorePotts:
  - `Lattice{N, M, G}` gained a `geometry` of `Square()` or `Hexagonal()`. The old
    constructors default to `Square`.
  - `embed` and `embed_covariance` apply the linear axial-to-Cartesian map.
    `centroid_position` is the Cartesian centroid.
  - The integer moment trackers, `min_image`, checkerboard colouring and periodic
    wrapping are unchanged: the hex neighbours are a subset of Moore(1) in axial
    coordinates.
  - The embedding is applied in shape, principal axes, the division partition (offset ·
    normal), the cluster division bias, and `_periodic_norm` (link distances).
  - Relations per geometry: `Hex(k)`; Moore/VonNeumann mean Hex on hex lattices;
    Euclidean `Ball`/`NeighborOrder` shells, ordered by embedded distance.
  - `laplacian`/`gradient` dispatch on geometry to 6-point stencils. The explicit
    stability bound is unchanged.
- Potts: `LatticeSpec.geometry`; `Lattice(dims; geometry = Hexagonal())` in `@lattice`.
  `centroid(k)` and `displacement(c, k)` are Cartesian.
- Tests:
  - CorePotts: counts, unit distances, exact Δ on a quadratic and ∇ on a linear field,
    a hex disc (61 sites) with exact centroid and elongation 1, an axial box that is
    elongated, and division of an ellipse separated along x.
  - Potts: a hex sorting model with a diffusing field, under sequential and checkerboard
    sweeps. Trackers match recomputes, field mass is conserved, and centroids are
    Cartesian. Metal Float32.
- Not done: MakiePotts renders hex states on the sheared array, without hexagon glyphs.

## 2026-09-29 — Review 5 (8788419^..HEAD)

All findings are fixed and have regression tests.

1. **Ensemble threads shared one integrator.** `EnsembleThreads` crashed on the shared
   `_AdaptiveODE` integrator.
   - Integrators are now cached per trajectory, keyed by the identity of the live state
     array. The reference is held weakly (`objectid` + `WeakRef`, with dead entries pruned)
     and the cache is guarded by a lock.
   - A first attempt with `WeakKeyDict` hashed the array by content. That meant scalar
     indexing on Metal, and on CPU the key changed every MCS.
2. **Parameter-tuple type change.** The cached integrator is rebuilt when the type
   changes (another proposal, relation set or backend).
3. **Silent solver failures.** A failed adaptive solve is now an error naming the MCS and
   cell. `reinit!` uses `reset_dt = true`.
4. **Replacement vs cadence.** Replacement and the single-writer check now share one
   `(phase, target, every)` key.
5. **Nested `@extend` counters.** The gather/draw numbering is reset only by the
   outermost model constructor (`_NESTING`), and `_nested` restores the outer lattice
   dimension. Base and outer `rand()` streams no longer collide.
6. **`reinit!` and integrals.** `reinit!` now runs the `at_init` phases, so integrals are
   valid again.
7. **Flat vector operating points.** A flat numeric vector for a vector variable is the
   vector itself for every entry, with a clear error on a length mismatch.

Timing: the Potts Metal group takes about 1 min. The same group under `julia -t 4` took
12 min (host-thread contention with Metal), so GPU tests run single-threaded.

## 2026-09-29 — D-040: LocalMath removed from the monorepo

- `git rm -r lib/LocalMath` (about 2.1 MB).
- The workspace entries `lib/LocalMath` and `lib/LocalMath/test` are removed and the
  Manifest re-resolves with no LocalMath.
- `GROUP=LocalMath` is removed from `test/runtests.jl` and CLAUDE.md.
- INTERNALS: the overview no longer shows LocalMath, and §3 is marked historical.
- ROADMAP: M5.1 is withdrawn.
- `reference/` still pins LocalMath by URL for the legacy oracle stack (D-021).
- `lib/MakiePotts/.github/workflows/ci.yml` and its CONTRIBUTING/AGENTS files are inherited
  and inert, and still describe the old multi-repo workflow. The monorepo has no CI yet
  (local-only).
- `GROUP=All` (CorePotts, MakiePotts, Potts, PottsModels) passes.

## 2026-09-29 — Full audit (docs/design/AUDIT.md)

Five read-only reviews (CorePotts, front end, codegen, SciML/units, docs/models/Makie); all
HIGH items re-run independently. ~90 findings with stable IDs `A-xx`, a hex section (user's
three items plus torus min-image, Weighted/domain axial inputs, PIFF, Makie), a 3D-hex plan
(prism first, FCC second, HCP rejected), and a fix order. No fixes yet — awaiting review.

## 2026-09-29 — Audit fix group 1 (memory safety and silent physics)

Commits 865b415, d1c9de8, 4f88af4, a689d39 and this one. Fixed A-01, A-02/A-66, A-03, A-05,
A-10, A-11, A-12, A-14, A-19, A-30, A-31, A-32, A-34, A-47, A-50, A-51, A-52, A-54, A-60–A-65,
A-67 (details in AUDIT.md's fix log). New: `src/schedule.jl` (D-041 energy-fold snapshots,
D-042 ordered update stages with `x__pre` snapshots and hoisted folds), `Footprint` source
reach (`reach`), `Lifecycle(…; rebuild!)`, `OnIndices`, `site` builtin, Cartesian
`position`. Regression tests: `test/audit.jl`, `lib/CorePotts/test/audit.jl`.
Behaviour changes: bare reads of a variable updated in the same block are its new value
(sibling vector components and self-references stay previous values); extension
replacement ignores cadence (warns); `with_capacity` no longer touches history rings (a
mismatched ring is an error); diffusion coefficients that are not parameter expressions need
explicit `substeps`; declared names may not shadow built-ins.

## 2026-09-29 — Maintainer approvals; Phase 0 local cleanup

- Recorded in DECISIONS ("Maintainer approvals"): D-046 (CLAUDE.md code rule reworded),
  D-040 (LocalMath removal; already executed in a6b8995, re-verified: not in `[workspace]`,
  test groups or CLAUDE.md), the Akeeb `rule = :merks` connectivity as published science,
  and D-041…D-045 marked maintainer-approved. AUTONOMY §4 and CLAUDE.md now authorize the
  local Phase 0 cleanup; pushes (tags included) still wait for §5, and force pushes stay
  forbidden (D-025).
- **Phase 0 cleanup (local only, nothing pushed).** After `git fetch`, every local branch
  was checked to be an ancestor of `origin/main` or to have an `archive/*` tag at its tip.
  223 branches were deleted, and their clean worktrees removed; directories that were already missing were pruned.
  No new `archive/*` tags were needed.
  - Tags: `legacy/main` at `origin/main` in each legacy repo: CorePotts.jl 6ec7316, LocalMath.jl
    041b930, MakiePotts.jl a8a025f, Potts.jl 427dc2e2, PottsModels.jl de97149.
  - Kept:
    - each repo's `main` and its checked-out branch (PottsModels.jl `codex/compositional-act`);
    - `Potts.jl` `codex/native-act-leader-follower-potts`, whose worktree has 7 uncommitted
      files (a patch is in `.reconciliation-preservation/phase0-2026-09-29/uncommitted/`);
    - the detached worktrees under the second clone `CPM 1.6/Potts.jl/.worktrees/`, which
      SCDPotts uses;
    - the second clone itself.
  - Removed, per repo. `*` means it had a worktree, and `†` means it was kept by its `archive/*` tag
    (unmerged). The rest were merged into `origin/main`.
    - **CorePotts.jl** (98): `codex/ProcessBigraphs-Docs`, `codex/addressed-process-rng`*†, `codex/architecture-readability`, `codex/authoring-execution`*†, `codex/bounded-fold-consumer`, `codex/c10-lifecycle-product-metal`*†, `codex/c10-reconciled`†, `codex/cartesian-domain-ownership`†, `codex/cell-stage-execution`*†, `codex/checkerboard-oracle-snapshots`*†, `codex/ci-testing-performance`†, `codex/compiler-construction-simplification`, `codex/compound-publication`*, `codex/core-contract-clarity`, `codex/descriptor-source-authority`, `codex/docs-redesign-9of10`, `codex/docs-visible-workflows`, `codex/documentation-redesign`, `codex/ecosystem-core-candidate`*†, `codex/ecosystem-core-final`*†, `codex/execution-source-ownership`, `codex/finalize-phase-1`, `codex/fixed-vector-operations`*†, `codex/history-execution`*†, `codex/lexical-authoring-support`*, `codex/lifecycle-numeric-conversion`*†, `codex/lifecycle-storage-initialization`, `codex/logical-state`*†, `codex/logical-state-execution`*, `codex/logical-state-mutation`*, `codex/maintained-quantities-integration`*†, `codex/maintained-quantity-crossproduct`*†, `codex/makiepotts-v0.2`†, `codex/metal-lifecycle-abi`†, `codex/metal-lifecycle-plan-abi`†, `codex/metal-lifecycle-status-abi`†, `codex/metal-lifecycle-workspace-abi`†, `codex/model-product-authoring`*, `codex/model-state-reads`*†, `codex/native-act-leader-follower-core`*†, `codex/periodic-cell-geometry`*†, `codex/phase-11-level1`†, `codex/phase-12-baseline-harness`, `codex/phase-12-cpu`†, `codex/phase-12-cpu-closeout`, `codex/phase-12-cpu-qualification`†, `codex/phase-12-performance`†, `codex/phase-13`†, `codex/phase-14`†, `codex/phase-14-wang-order-audit`†, `codex/phase-15a-canonical-structure`, `codex/phase-15b-open-composition`, `codex/phase-15b-post-merge-hygiene`, `codex/phase-15c-attestation`, `codex/phase-15c-implementation`, `codex/phase-15c-preimplementation`, `codex/phase-16`†, `codex/phase-2-repository-structure`†, `codex/phase-3-conformance-foundation`†, `codex/phase-4-core-state-protocols`†, `codex/phase-5-execution-rng`†, `codex/phase-6-scientific-inner-loop`†, `codex/phase13-realistic-v4-launcher`†, `codex/phase13-transition-v2-launcher`†, `codex/pin-gpu-benchmark-manifests`, `codex/pr37-scan-device`*†, `codex/pre-refactor-baseline`†, `codex/product-fields`*, `codex/quantity-consumption-contract`*†, `codex/r10-maintained-foundation`†, `codex/r10-owner-index-prototype`*†, `codex/r10-spatial-relations-qualified`*†, `codex/relation-measure-sensing`*†, `codex/restack-core-r10`*†, `codex/scd-c10-restack`*†, `codex/scd-contact-owner-runtime`*†, `codex/scd-owner-filtered-gathers`*†, `codex/scd-pausable-sequential-runtime`*†, `codex/scd-r10-restack`*†, `codex/scd-r49-restack`*†, `codex/scd-relation-restack`*†, `codex/scheduled-process-draws`*†, `codex/scheduled-scope-contexts`*†, `codex/scientific-contexts`*, `codex/site-minimum-tracker`*†, `codex/source-aware-trackers`*†, `codex/structured-authoring-integration`*, `codex/structured-lifecycle-complete`*, `codex/structured-lifecycle-integration`*†, `codex/structured-owner-sums`*†, `codex/trim-makie-ci`, `codex/verification-audit`†, `codex/verification-audit-followup`, `ecosystem-candidate-ci`*, `feat/intrinsic-metropolis-engine`, `gh-pages`†, `moment-geometry-metal-witness`*†, `scientific-context-ownership`*.
    - **LocalMath.jl** (31): `codex/architecture-readability`, `codex/backend-owned-array-allocation`*, `codex/ci-testing-performance`†, `codex/collect-order-bounds`*, `codex/compact-validation-settlement`*, `codex/compacted-record-stage-access`*†, `codex/d2q9-animation`*†, `codex/data-first-fold`, `codex/dependency-table-lowering`, `codex/empty-compacted-storage`, `codex/empty-pointwise-domains`*, `codex/fixed-relation-copy-settlement`*†, `codex/fixed-value-stage-operations`, `codex/github-pages-docs`*, `codex/identity-seeded-reduction-control`*, `codex/keyed-rebuild-publication`†, `codex/keyed-reduce-workspace-identity`*†, `codex/keyed-reduction`, `codex/keyed-reduction-pr18`†, `codex/ordered-fold-step-validation`*†, `codex/pointwise-temporary-identity-segmentation`*, `codex/product-values`*, `codex/rc2-citation-metadata`, `codex/source-order-fold-direct-traversal`*†, `codex/stable-plan-preparation-waist`, `codex/structural-truth`, `codex/trigonometric-stage-admission`*†, `codex/typed-stage-execution`, `codex/verification-audit`, `ecosystem-candidate-ci`*, `gh-pages`†.
    - **MakiePotts.jl** (38): `codex/ProcessBigraphs-Docs`, `codex/architecture-readability`†, `codex/docs-redesign-9of10`, `codex/docs-visible-workflows`, `codex/documentation-redesign`, `codex/finalize-phase-1`, `codex/makiepotts-v0.2`†, `codex/phase-11-level1`, `codex/phase-12-baseline-harness`, `codex/phase-12-cpu`, `codex/phase-12-cpu-closeout`, `codex/phase-12-cpu-qualification`, `codex/phase-12-performance`, `codex/phase-13`†, `codex/phase-14`, `codex/phase-14-wang-order-audit`, `codex/phase-15a-canonical-structure`, `codex/phase-15b-open-composition`, `codex/phase-15b-post-merge-hygiene`, `codex/phase-15c-attestation`, `codex/phase-15c-implementation`, `codex/phase-15c-preimplementation`, `codex/phase-16`†, `codex/phase-2-repository-structure`†, `codex/phase-3-conformance-foundation`†, `codex/phase-4-core-state-protocols`†, `codex/phase-5-execution-rng`†, `codex/phase-6-scientific-inner-loop`†, `codex/phase13-realistic-v4-launcher`†, `codex/phase13-transition-v2-launcher`†, `codex/pin-gpu-benchmark-manifests`, `codex/pre-refactor-baseline`†, `codex/rc2-citation-metadata`, `codex/trim-makie-ci`, `codex/verification-audit`†, `ecosystem-candidate-ci`*, `feat/intrinsic-metropolis-engine`, `gh-pages`†.
    - **Potts.jl** (56): `authoring-operational-ownership`*†, `codex/accepted-copy-fixture`*†, `codex/atomic-input-publication`*†, `codex/attempt-budget-reconciliation`*†, `codex/authoring-workflow`*†, `codex/bounded-site-minimum-authoring`*†, `codex/bounded-site-minimum-restack`†, `codex/cartesian-domain-authoring`*†, `codex/cell-process-authoring`*†, `codex/component-replacement`*†, `codex/compound-compilation`*†, `codex/compound-effects`*†, `codex/declaration-control-flow`*†, `codex/dimensional-expression-scales`*†, `codex/failure-reporting`†, `codex/fixed-vector-parameters`*†, `codex/history-authoring`*†, `codex/lexical-authoring`*†, `codex/logical-state-authoring`*†, `codex/logical-state-mutation`*†, `codex/metal-runner-qualification`*†, `codex/mixed-symbolic-mutation`*†, `codex/model-product-authoring`*†, `codex/model-state-reads`*†, `codex/native-act-leader-follower-potts-integrated`*†, `codex/operation-contracts`*†, `codex/package-repository-cutover`†, `codex/potts-addressed-rng`*†, `codex/problem-construction-polish`†, `codex/product-fields`*†, `codex/product-state-authoring`*†, `codex/r09-pre-scope-split`†, `codex/r11-pre-parent-fix`†, `codex/r11-pre-restack`†, `codex/reconcile-diagnostic-validation`*†, `codex/resolved-quantity-lowering`*†, `codex/scd-c11-restack`*†, `codex/scd-compositional-activity-drives`*†, `codex/scd-leader-drive-authoring`*†, `codex/scd-native-lifecycle-phases`*†, `codex/scd-r09-restack`*†, `codex/scd-r11-restack`*†, `codex/scd-r50-restack`*†, `codex/scd-runtime-reuse`*†, `codex/scheduled-process-draws`*†, `codex/scoped-component-integration`*†, `codex/scoped-quantities`*†, `codex/stable-materialization-waist`†, `codex/stable-snapshot-schema`†, `codex/state-contract-quality`*†, `codex/step-compilation`*†, `codex/stochastic-field-authoring`*†, `codex/structured-authoring-integration`*†, `codex/structured-state-authoring`*†, `codex/verification-audit`†, `model-library-workspace`*†.

## 2026-09-29 — Follow-ups: the 11m51s Metal run; performance after group 1

- **The 11m51s Metal run was a one-off**, not threads and not group 1.
  - At the same commit, the "symbolic models on Metal" testset took 11m51s under `-t 4` and
    1m01s single-threaded; only the tail of the `-t 4` log survived.
  - Re-run now: the Metal group under `-t 4` takes 62.7 s (67.5 s single-threaded). The
    CPU-only Potts group takes 153 s at `-t 4` and 162 s at `-t 1`, and no testset differs
    by more than 1.5 s.
  - Most likely cause: contention with other julia jobs running then, or a cold Metal shader
    cache.
- **Throughput** (benchmark/README): at or above the baseline everywhere.
  - Sequential 72²: 7207 MCS/s (was 6130).
  - CPU checkerboard: 6652 MCS/s at 72² (was 5690) and 412 at 576² (was 296).
  - Metal: 5551 MCS/s at 72² (was 4470) and 956 at 576² (was 926).
- **TTFX:** build is 1.1–1.4 s faster and the first sequential MCS 0.1–0.7 s slower (cause not
  isolated). Build plus first MCS is equal or lower for every model, all under 15 s.
- **Hex paths dispatch on geometry.** `which` confirms that square lattices resolve
  `_min_image`, `_locally_connected` and `_merks` to the generic `Lattice{N}` / `Lattice{2}`
  methods. Only `Lattice{2, M, Hexagonal}` reaches the 6-ring and hex minimum-image code.
- **Warm MCS was not allocation-free, and now is.**
  - Only sequential Graner allocated 0 B. Every other model allocated 0.8–1.9 KB per
    sequential MCS, and every model 7–23 KB per checkerboard MCS.
  - Byte-identical at b491cb0, so this predates group 1. It had been missed because QA
    checked `sequential_mcs!`, not `step!`.
  - Cause 1: KernelAbstractions' CPU launch allocates (argument tuple, boxed indices) even
    for a single inline workgroup.
  - Cause 2: the lifecycle's `Array(count)[1]` readback.
  - Fix:
    - every kernel is an `@inline` body behind a thin `@kernel` wrapper;
    - `CorePotts._launch` runs the body as a plain loop when the CPU runs it as one
      workgroup, and checkerboard colors do the same;
    - `_readback` reads 1-element host arrays without a copy.
  - A first version routed propose and commit through the generic `_each_kernel!`. That
    cost 22% on Metal 576², so they keep dedicated `@Const` wrappers. It also hit a KA CPU
    pitfall: `@index` must be its own statement. The single-threaded suite never took
    multi-workgroup CPU launches, so a CorePotts test now forces that path and checks it
    against the inline one.
  - Now every published model allocates 0 B per warm MCS, sequential and checkerboard. The
    D-047 QA testset gates this (AUTONOMY §5).
  - All groups pass, including CorePotts under `-t 4` with Metal, Potts with Metal and QA,
    PottsModels and MakiePotts.

## 2026-09-29 — Audit group 4, rescoped: ordinary model tests replace legacy parity (D-048)

- **Decision (maintainer):** no parity harness against the legacy codebase; models are
  verified by ordinary tests. Removed:
  - `reference/` (the pinned legacy environment, its samplers and data);
  - the `Reference` test group;
  - the legacy comparisons in `test/parity`.

  The hand-written ports move to `test/ports`. The legacy code stays reachable through git
  history and the `legacy/main` tags.
- **Why the old tests were weak** (found while working on A-70/A-71): on the legacy 8×8
  fixtures, the mechanism under test barely acts.
  - Wortel's cells die by MCS 10 at any λ ≤ 1.
  - Merks' chemotaxis energy (≈ 0.08) is negligible against T = 6.
  - Even with surviving cells, λ_act = 20 against 0 is undetectable at 64 seeds.
- **New tests** in `lib/PottsModels/test/mechanisms.jl`, about 12 s. They are written from each
  model's specification and are independent of production code.
  - **Drives and constraints, per proposal.** The drive is ΔH minus the energy change,
    compared with the chemotaxis, Act (shifted geometric mean) and Akeeb cue formulas. The
    constraint is compared with the Merks ring rule, re-implemented (plus no-extinction
    for Akeeb).
  - **Effects:**
    - Wortel's on-copy activation and its decay (frozen cell: `max(act₀ − k, 0)`);
    - Merks' field recomputed exactly each MCS (two Euler substeps, zero flux, clip at 0);
    - OpenVT's exact division partition and mass halving, and its trigger invariant;
    - Akeeb's clocks and target-volume growth.
  - **Mechanisms with negative controls:**
    - Graner–Glazier: sorting under the published J, none under equal J, mixing under
      reversed J; H never rises at T → 0, for sequential and checkerboard;
    - Merks: a cell climbs, holds and descends a static gradient for χ = 100, 0, −100;
    - Wortel: Act gives persistent migration (median net displacement over 8 against
      λ_act = 0);
    - Akeeb: leaders invade (mean height > 28) and stay put without the cue (< 20);
      proliferation needs clocks.
- **Exact oracle on generated code.** The CorePotts oracle module moved to `oracle_core.jl`
  and gained periodic boundaries. `test/oracle.jl` checks the generated Graner–Glazier on a
  3×3 torus: χ² z = 1.6, TV at the noise level, and the T = 5 mutant gives z = 21. A
  periodic checkerboard oracle is infeasible: it needs even axes ≥ 4, and 3¹⁶ states.
- **Audit items:**
  - A-72: OpenVT divides at `volume ≥ V₀`.
  - A-75: `akeeb_state(; slab)`, with a height check.
  - A-76: the Wortel docstring now matches the code.
  - A-77: Akeeb in Float32 on Metal agrees with Float64 on the CPU (t = −0.9), with its
    trackers checked.
- **Findings for the maintainer:**
  - The Merks ring rule does not keep cells globally connected. It falls back to "allowed
    if exactly two distinct cells occupy the ring". After 200 MCS, 2–7 Akeeb cells are in
    several pieces, with or without the cue.
  - WortelAct keeps the legacy Act semantics chosen for parity (D-034): the shifted
    geometric mean, and activation only on extension into the medium. The paper and
    Artistoo use the plain geometric mean and activate every gained site.
- All groups pass: CorePotts, Potts (with Metal and QA, 80 testsets) and PottsModels.

## 2026-09-29 — Paper-fidelity round (AUDIT §11)

- Five reviewers compared each published model with its paper and reference code: the
  Graner–Glazier PRL/PRE, Merks 2006/2008, Niculescu 2015 with Wortel 2021 and Artistoo, the
  OpenVT monolayer spec with its Morpheus/CC3D/Artistoo implementations, and the Akeeb CC3D
  source.
- I re-ran the load-bearing claims:
  - Akeeb splits 4–6 cells under `:merks` and 0 under `:local`;
  - CC3D 4.3.1 accepts one arc only;
  - Merks diverges at the paper's D;
  - the Graner–Glazier λ table matches PRE Table III exactly.
- **Faithful:**
  - Graner–Glazier: energy and parameters;
  - Akeeb: everything except connectivity.
- **Reduced or legacy:**
  - Merks: no length constraint, the paper's key term;
  - Wortel: Act has no retraction term, uses the shifted mean, and activates on extension
    only;
  - OpenVT: our model is not the benchmark at all;
  - Graner–Glazier: the time unit is 1/16 of the paper's and the proposal default is
    4-neighbour.
- **Fixed now:**
  - explicit field substeps are a stability minimum (the paper's Merks D diverged
    silently);
  - capacity-deferred divisions warn;
  - honest docstrings for all five models;
  - the Graner `provenance.toml` gap line.
- **Tests:** `lib/PottsModels/test/papers.jl` reproduces the papers' own results on the
  current models, 27 tests in about 35 s:
  - Graner–Glazier: engulfment, checkerboard, the log law, the λ survival table, cell sizes
    and layer reversal, each with the paper's contrasting regime as the control;
  - Act: speed–persistence coupling, stationary weak Act, amoeboid vs keratocyte
    orientation;
  - Akeeb: motility grading, adhesion vs single-cell escape, and the published sample's 578
    divisions.
- **Decisions F-1…F-6** (science changes) are listed in AUDIT §11 for the maintainer.
- All groups pass: PottsModels, CorePotts, and Potts with Metal and QA.

## 2026-09-29 — D-049: the paper-fidelity decisions implemented

The maintainer approved F-1…F-6 (D-049).

- **F-1:** a model declares its proposal relation with `@relations proposal = …`.
  `CPMProblem` carries it and `SequentialCPM`/`CheckerboardCPM` default to it (`proposal =
  nothing`). Graner–Glazier and Wortel copy from `Moore(1)`, Akeeb from `VonNeumann(1)`.
- **Conditional sections:** an `if`/`else` around section macros in `@potts_model` is a
  runtime branch on structural parameters (Wortel `connected`, Merks `contact_inhibited`).
- **F-2:** `graner_glazier_state` is regenerated by `data/graner/generate.jl` following PRE
  §II D3. The legacy `metrics.tsv` is gone. Two `papers.jl` observables were artifacts of
  the old state and are re-set:
  - partial sorting is judged by the dark–medium share (5–6%, against ≤ 1% under
    engulfment);
  - layer reversal is measured at 4000 MCS (radius ratio 1.2–1.7).
- **F-3:** `major_length` is a cell built-in, with an exact ΔH from the moment sums
  (`CorePotts.major_length_after`, tested against committed lengths on square, hex and 3D
  lattices with seams).
  - Merks follows the 2006 paper: length constraint, J adhesion, chemotaxis on every copy,
    decay in the matrix only, one-arc connectivity, paper-scale defaults, and `merks_state`.
  - On 140² with 100 cells over 1500 MCS, elongated cells form networks (largest-cluster
    compactness 0.27, elongation 4.7). Round cells form islands (0.58, 1.5).
- **F-4:** Wortel follows Artistoo semantics. With a 200² amoeboid default, all 7 Act paper
  tests still pass.
- **F-5:** `OpenVTGrowingMonolayer` (Artistoo set). Its doubling time is about τ, and
  halving τ halves it. β = 0.95 slows the colony (259 vs 513 cells at 840 MCS on 160²), and
  the first division plane is isotropic. The old fixture is `SingleDivisionFixture`.
- **F-6:** Akeeb uses CC3D's one-arc connectivity; no cell splits over 3 seeds.
- **Suites:** all pass — CorePotts, MakiePotts, PottsModels, and Potts with Metal and QA.
  - New regression tests: conditional sections, model proposals, `major_length` ΔH on
    square, hex and 3D, and the growing monolayer on Metal.
- **Benchmarks:** the Graner–Glazier timings in `benchmark/README.md` were measured on the
  old initial state. Same size and cell count, so they are expected to hold, but they have
  not been re-measured.

## 2026-09-30 — Graner–Glazier audit fixes, D-050/D-051, feature review, R0

- **Graner–Glazier port** (fixes from the PRE 1993 audit, spec 09 §8.6):
  - square staggered-brick start with a plateau check;
  - random cell types;
  - annealed-copy measurements, with fractions over all mismatched bonds;
  - paper-timed engulfment and λ-survival tests;
  - an honest list of the remaining differences.
- **D-050:** the per-model decisions in model-specs README §4 are recorded as approved.
- **Feature review:** `research/feature-roadmap-review.md` (three reviewers) proposes R0–R16.
- **D-051:** the maintainer's answers to the review.
- **R0, family-general primitives replacing the model-named paths:**
  - Connectivity is copy-scope values: `local_components`, `ring_arcs`, `ring_cells`.
    - `connectivity(k; rule = :local | :arc_or_pair)` is shorthand, and unknown rules throw.
    - Soft rules are drives.
    - `rule = :merks` and `merks_connectivity` are gone.
  - `Chemotaxis(c; strength, response, kinds, when)` replaces `extension_only`. It comes with
    `saturating(s)` and `saturating_linear(s)`.
  - `neighborhood_mean(…; relation, fold)` with `ArithmeticMean`, `GeometricMean` and
    `Log1pGeometricMean` replaces `act_mean`/`act_delta`/`ctx.act`.
  - `log1p_geomean` replaces `geomean_shifted` and now clips at 0 like the lowered fold.
  - CorePotts declares `public` its generic lattice and RNG names.
- **Guardrails:**
  - ExplicitImports on PottsModels, which now has explicit `using Potts: …`;
  - each model builds in a bare `using Potts` module;
  - a DSL-surface snapshot;
  - one sibling per published model (hexagonal sorting, arithmetic-mean Act, saturating
    chemotaxis, soft connectivity with leader-gated chemotaxis, major-axis division),
    with a registry check;
  - a syntax-tree scan for model/author names in `src/`, `lib/CorePotts/src` and
    `lib/MakiePotts/src` (negative control checked).

## 2026-09-30 — agent-driven development set up (D-053)

- **Protocol:** AUTONOMY §7 covers the coordinator, worktree implementers and the
  adversarial reviewer, the item loop, safeguards, parallelism and checkpoints. ROADMAP
  Phase 6 holds the queue (step 0 composition fixes, then the model-specs §6 sequence).
- **Agent definitions:** `.claude/agents/potts-implementer.md` and `potts-reviewer.md`.
- **Performance gate:** `benchmark/gate.jl` with `benchmark/baseline.toml`, run
  single-threaded. A threaded KernelAbstractions launch allocates a fixed ~3 KB of tasks
  per phase, which would mask per-site allocations. Warm MCS in ns/site, sequential /
  checkerboard / Metal (Float32):

  | Model | Sequential | Checkerboard | Metal |
  |---|---|---|---|
  | Graner–Glazier | 24.8 | 27.2 | 18.9 |
  | Wortel Act | 13.7 | 14.9 | 44.3 |
  | Merks | 94.3 | 93.4 | 183.8 |
  | OpenVT | 13.8 | 15.0 | 74.2 |
  | Akeeb | 47.2 | 46.5 | 185.8 |

  All cases allocate zero bytes. A repeat run stays within 4 %.
- **Frozen acceptance tests:** `lib/PottsModels/test/frozen.toml` and `frozen.jl`.
  `papers.jl` is frozen under D-050. The negative control is a one-line edit, which fails
  the check.
- **`tools/exclusive.sh`:** a machine-wide lock for GPU suites and the gate.

## 2026-09-30 — P6.0a merged: cell and cluster division in one model (D-054, D-055)

- **Process:** the first item through the agent protocol. Freeze `ee52f55`, implementation
  `beba0a5`, freeze amendment `13513b3` (D-054, a fixture error), reviewer APPROVE with 4
  nits.
- **Behaviour:** per-domain division, in one lifecycle pass, on CPU and Metal, under
  sequential and checkerboard.
  - `Lifecycle(; clusters = true)` (entries above) is replaced by `EVENT_DIVIDE_CLUSTER`.
  - The lone-cell daughter fusion is fixed.
- **Reviewer's check:** a scratch run on 3D, hex and square lattices with capacity overflow
  matched brute-force volume, cluster volume and moments.
- **Open nit (queued):** a capacity-limited mixed-division test in
  `lib/CorePotts/test/compartments.jl`.
- **Performance gate on the merged tree:** every CPU case is ≤ 1.013 against the baseline.
  - Metal first showed openvt at 1.15. The base commit, rerun in the same session, showed
    the same slowdowns: wortel 3.3×, akeeb 1.8×.
  - An interleaved A/B test of openvt on Metal had equal medians for base and merged
    (117.8/118.6 and 119.5/119.2).
  - The GPU's timing is bimodal (about 75 or about 115 ns/site), so Metal is now gated by
    A/B (AUTONOMY §7.4).

## 2026-09-30 — P6.0h merged: docs pipeline, pilot reproduction 09 (sorting)

- **Build:** `docs/` workspace project (Documenter, Literate, CairoMakie, Markdown) and
  `docs/make.jl`. It builds offline in about 2 minutes, with `checkdocs = :exports`.
  - Literate pages go into a gitignored `docs/src/published/`.
  - After adding a workspace project, the shared Manifest needs `Pkg.resolve()`.
- **Pilot:** `lib/PottsModels/reproductions/09_cell_sorting.jl`. It took three review
  rounds.
- **Verdicts:** they use the nominal times of spec §8.5 (V-PRE1/2/3). The spec's ±2×
  time-scale check is informational only, with a best s = 1.0.
- **Reduced run (n = 4, 64 cells):**
  - Fails: heterotypic @10, light–light @10/100/10³, the 5–4000 log law, the light–light
    crossing (128), and the raw light–medium plateau.
  - Passes: the rest. The 10⁴ rows are pending.
  - The failures come from aggregate size (a 1000-cell generator is queued as P6.1b2).
- **Science correction (reviewer):** the medium share does not change the time axis.
  - The sampler draws attempts uniformly over all sites, and a padded-lattice test gave
    identical curves.
  - Spec 09 D9 and the §8.5 ±2× premise have been sent to the spec owner for revision
    before pre-registration.


## 2026-09-30 — P6.1a merged: layout library, first slice (D-056, D-057)

- **What merged:** `Tiling`, `Scattered`, `Frame`, `overlay` and `layout`, with 99 unit
  tests and the frozen acceptance.
- **Review:** 3 rounds. They fixed:
  - the gap across the periodic wrap (touching on 42 of 200 seeds before);
  - an untested jam path;
  - an O(cut × L) split check (22 s at 200³, now 0.34 s);
  - a non-public extension API.
- **Rename:** `Scatter` → `Scattered` because of a clash with Makie (D-056).
- **New dependency:** StableRNGs.
- **Gate:** not run, because the change is host-only. No solver, kernel or step path
  changed, and another agent was running heavy suites at the time.
- **Nits queued:** P6.1a3.
- Merge fix: two `@ref` links in the layout docstrings pointed at undocumented names (`overlay`, `PottsProblem`) and broke the docs build. They are now plain code. The docs build is now a standing suite.

## 2026-09-30 — follow-ups merged: P6.0a2, P6.1a3, P6.0h2

- **P6.0a2:** capacity-limited mixed-division test. It pins D-055 item 4, and the reviewer
  killed 5 of 5 mutations with it.
- **P6.1a3:**
  - the `Scattered` area bound no longer rejects feasible requests on periodic axes;
  - the timing test is warmed before it measures;
  - `_warn_split` uses dense per-cell buffers.
- **P6.0h2 (tutorial 09):**
  - wording and caveats;
  - the plateau criterion adds a last-decade log-slope check (±5 % of the final value per
    decade), which turns the smoke run's "plateau reached" row from PASS to FAIL
    (0.042 per decade against 0.011), correctly;
  - the helper code is hidden.
- **Merge fixes:** the local `nsites` in `_warn_split` is renamed `ncount`, because it
  shadowed the exported function. The ±0.014 read-off uncertainty is marked as our own
  estimate.

## 2026-09-30 — P6.0b merged: several relationships per model (D-058)

- **What merged:** named link stores; edge variables scoped by relationship; `x(edge)`
  bound per body before `@extend`; and shared read claims on checkerboard, which are
  exact.
- **Review:** 2 rounds.
  - Round 1 found an untested exactness check and broken `@extend` composition.
  - Round 2 killed all 5 kernel mutations.
- **Gate on the merged tree, idle machine:** every CPU case is within 0.978–1.001.
- **Metal A/B against the base** (4 rounds):
  - openvt 0.995;
  - akeeb 1.031, consistent across rounds. That is within the 5 % tolerance, but it is
    real. Akeeb has no relationships, so the no-reads path costs about 3 % on Metal.
    Queued as P6.0b3.
- **Merge fix:** a missing `[[file]]` header in frozen.toml after a conflict. The frozen
  check caught it.

## 2026-09-30 — P6.0b3 merged: no-reads kernels pay nothing again

- **Cause:** P6.0b passed two dead length-1 `wclaim` buffers to the propose and commit
  kernels of models without reads. The IR diff showed identical bodies, with the extra
  arguments only in the signatures.
- **Fix:** `wclaims = (nothing, nothing)` through a `CheckerboardCache` type parameter.
- **A/B against the pre-P6.0b base (implementer):** akeeb 0.993, openvt 0.996, merks 1.001.
  The reviewer's A/B was inconclusive because the GPU stayed in its slow power state. The
  reviewer approved on the code and IR evidence.
- **Rule recorded:** D-058 item 4.


## 2026-09-30 — P6.0e merged: contact energies read site values (D-061)

- **Process.**
  - The write set had to be widened twice: `src/macro.jl` (my scoping error) and
    `src/compose.jl`.
  - The review ran 3 rounds. They fixed `x′` in `@extend`, a silently inconsistent
    user-declared `x′`, and a missing regression test.
- **Exactness.** It was verified adversarially: contact relations of radius 2–3, on-copy
  writes and clears, two site terms, square, hex and 3D, all below 1e-9.
- **Wortel.** Its generated code is bitwise-equal apart from new locals. A/B on CPU gives
  1.000 sequential and 0.999 checkerboard.
- **Queued as P6.0e2:** the `m′` error message, and the check for programmatically built
  systems.
- **Gate on the merged tree (idle):** CPU cases 0.971–1.010. Metal openvt was flagged at 1.122; the A/B gives 1.001.

## 2026-09-30 — follow-ups merged: P6.1a2, P6.1a4, P6.0b4 (D-062)

- **P6.1a2:** `Frame` on masked lattices uses a Chebyshev ring.
- **P6.1a4:** `_warn_split` allocates its visited array lazily: 378 KB against 2.4 MB
  eagerly.
- **P6.0b4:** a permanent Metal test of a model with relationship reads.
- **Review:** 2 rounds. Round 1 added hex and 3D frame tests.

## 2026-09-30 — P6.1b2 merged: paper-size GG aggregate, papers.jl annealing, tutorial guardrail

- **`graner_glazier_aggregate` / `VoronoiBall`:** connected cells across 1,040 reviewer
  layouts; n = 1000 in 0.026 s.
- **papers.jl:** each regime is annealed under its own Hamiltonian (D-059).
- **Public-names guardrail** for `reproductions/*.jl`, covering multi-part imports and
  family-module aliases.
- **09 FULL:** each replicate runs from its own 1000-cell aggregate, at an estimated 25–40
  min on 6 threads (not run yet).
- **Freeze bug:** a fixture shadowed `Base.all` (D-060), so a stub run is now part of every
  freeze.
- **Review:** 2 rounds.
- **Peer:** tutorial rows 109–110 and one `##` comment await ratification by the peer.


## 2026-09-30 — P6.0i merged: author question batch 1 (drafts, not sent)

- **Letters:** 8 files under `docs/design/research/author-questions/`, with 59 questions in
  all. 31 are blocking (30 distinct) and 11 are on HOLD.
- **Sending:** the maintainer sends them personally. Nothing was sent, and the letters
  carry no contact details.
- **Before sending:** do the pre-send checklist in README.md. It lists the sources to
  obtain (Document S1 of Biophys J 2020 and the nanoHUB gltcellcrawl code,
  Instructions_To_Run.pdf, ACRI 2018, the Dal-Castel version of record, Chaste 2017.1 and
  Merks 2006 supplementary). Then remove the [HOLD] tags, revise the context sentences
  that depend on those checks, and confirm the spelling of Akeeb's first name.
- **Review:** 3 rounds. Round 2 found that Merks 2008 p.9 answers the Fig 10 lattice
  question; that answer is recorded in spec 01 §3.3 row 10 and §8 A-10. It also corrected
  the first author to Ismael Fortuna.

## 2026-09-30 — P6.0j merged: ExplicitImports in Potts, CorePotts and MakiePotts (D-064)

- **Checks:** five ExplicitImports checks in each package's QA, the extension included.
  Negative controls failed as expected, run by both the implementer and the reviewer.
- **Owner fixes:** `SymbolicIndexingInterface.getname`, `Symbolics.rename` and
  `TermInterface.maketerm`/`metadata`. Each is the same function object as before.
  TermInterface is now a weakdep of Potts and a second trigger of the units extension.
- **Suites on the merged tree:** CorePotts (QA on), PottsModels, MakiePotts, docs, and
  Potts on Metal all pass.
- **Performance gate:** not run. The changes are import lines and qualified names that
  resolve to identical function objects, so no generated code changes. The machine was
  also busy with P6.0f.
- **Review:** 1 round. Nits N3 (compat order) and N4 (testset name) were fixed at merge.
  N1 (allowlists match by name only) is recorded in D-064.

## 2026-09-30 — P6.0i2 merged: author-letter pre-send checks (D-067); letters untracked

- **Sources obtained (legitimate public only):** Fortuna 2020 Document S1, the nanoHUB
  gltcellcrawl port, `Instructions_To_Run.pdf`, the CC3D 3.7.9 and 3.6.2 solver and
  chemotaxis sources, the Chaste release_2017.1 and paper-tag Potts sources, the HMR core
  xls files, the Merks 2006 PMC manuscript and the TST chapter. They are catalogued in the
  gitignored `docs/references/codebases/SOURCES.md`.
- **Not obtained (the maintainer will get them):** the Merks 2006 supplementary methods,
  the Dal-Castel 2025 version of record, and ACRI 2018.
- **Letters:** 57 questions, 30 blocking, 4 HOLD.
- **Specs:** spec answers recorded in 01, 08, 09 and 14. C7 and X5 are changed (approved,
  D-067).
- **Letters untracked:** they are local, untracked files, per the maintainer (4275f24).
- **Review:** 1 round. The blocker was that the approved §4 rows had been overwritten; it
  was resolved by maintainer approval.
- **Holds:** P6.1c and P6.2b are held for the V-target audit.

## 2026-09-30 — P6.5a0 merged: liveness survey; D-066 adopted

- **Survey:** CompuCell3D 3.7.9 and 4.9, Morpheus 2.4.1 and Artistoo, at pinned commits.
  Citations were verified by two reviewers.
- **D-066:** a cell is alive exactly while it owns a site.
- **Deviations:**
  - X1: slot reuse, measured. At 16× capacity, Akeeb checkerboard is +16 % and
    sequential +5 %, and every growth allocates in a warm MCS.
  - X2: a cell is born only when it receives a site. Signed off by the maintainer.
  - X3: links are dropped at the next boundary. Not measured.
- **`retain_empty`:** dropped (maintainer).
- **Akeeb seeding:** handed to the P6.2b audit.
- **Review:** 3 rounds.
- **Found:** the link NaN freeze, now P6.0l.

## 2026-09-30 — P6.0f merged: per-rule `Every(n)`; the firing rule alone writes daughter state (D-070)

- **Cadence:** each division or link rule has its own cadence. The lifecycle pass is gated
  by the gcd of the cadences, and only rules whose cadence differs from the gcd get a
  modulo gate.
- **Overlapping rules:** the firing rule's index travels in the event (CorePotts
  `ruled_event`), and only models whose rules overlap generate it.
- **Also fixed:** `@link` used to drop a positional `Every` silently.
- **Review:** 2 rounds. Round 1 found the daughter-state cross-talk bug, which predated
  this item.
- **Suites on the merged tree:** CorePotts (QA on), PottsModels, MakiePotts, docs and
  Potts on Metal all pass.
- **Performance gate:** the CPU cases pass (ratios 0.996–1.037, run under load). Four Metal
  cases were flagged; the A/B against the pre-merge tree gave Akeeb 0.997, OpenVT 1.018,
  Merks 0.988 and Wortel 0.963 (Wortel's first 4-round run gave 1.49 under load; 8 rounds
  settled it).

## 2026-09-30 — P6.1c merged: reproduction 09 frozen (pre-registered, D-072)

- **Page:** `reproductions/09_cell_sorting.jl` is rebuilt from spec 09 §9.1, following the
  spec owner's audit, and frozen.
- **Smoke CI verdicts:** V-GG6, V-PRE13(a), NC1 (size-free) and the V-PRE3(a) NC1 clause
  all pass.
- **Calibrations:**
  - V-PRE3(a) is FULL-only; its size-free form first drops below 0.1 at the 640 save.
  - NC1's size-free clause: six four-seed means 0.442–0.500.
  - The margin stays 10 (largest difference 1.10 SE at n = 6).
- **V-PRE4 measurement:** Voronoi start D = 0.0214 vs relaxed start D = 0.0212; paper 0.014.
- **New:** a `margin` keyword on `graner_glazier_aggregate`, and V-PRE16 checked in
  `generate.jl` (regenerated data is byte-identical).
- **Suites on the merged tree:** PottsModels and docs pass.
- **Review:** 2 adversarial rounds plus a coordinator check.
- **Spec owner:** ratified the page and made 7 rulings. Spec 09 §9.1 and README §5 are
  committed with this merge.
- **Next:** the FULL run, 1000 cells per replicate, 25–40 CPU-min per replicate on 6
  threads.

## 2026-09-30 — P6.2c merged: Akeeb seeding emulates the authors (D-068, D-071)

- **Seeding:** `akeeb_state(; seeding = :authors | :retry)`. The default counts a missed
  draw toward the quota without creating a cell.
  - An independent CC3D-loop emulation by the reviewer matches it on 5000 of 5000 seeds.
  - Statistics: 382.1 ± 2.7 painted and 7.9 ± 2.8 empty, matching the spec owner's audit.
  - `:retry` is identical to the old code in 468 of 468 cases.
- **Frozen `papers.jl`:**
  - μ = 24 by default;
  - an ensemble divisions band, 585.0 ± 16.4 over 40 seeds, giving [535.8, 634.2] with the
    paper's 578 inside;
  - the adhesion floor is now `> 0` (D-071).
- **`mechanisms.jl`:** every split cell at pp = 0.5 must be a divided mother or daughter,
  checked on seeds (3, 5, 6, 24). The connectivity check runs at pp = 0.
- **Gate:** the Akeeb case changes state (75 leaders instead of 77 at 99×60). The reviewer
  measured CPU sequential at 46.7–46.8 and checkerboard at 45.2–45.9 ns/site against
  baselines of 47.2 and 46.5, with 0 allocations, so no re-baseline is needed. Metal was
  covered by the Metal suite's Akeeb CPU-vs-Metal test, not timed.
- **Suites on the merged tree:** PottsModels and Potts on Metal pass. CorePotts passed on
  the branch.
- **Review:** 1 round plus one targeted fix, the check for split daughters.

## 2026-09-30 — P6.2a merged: `InsertUntil` and `PottsModels.Analysis` (D-073)

- **Frozen test:** passes 308/308, including the authors' four profiles (fingers 12/12/0/0,
  areas exact).
- **Review:** 1 round, approved with doc nits, which were applied at merge. The reviewer
  diffed against the SciPy/NumPy source text and cross-ran the cached SciPy with 0
  mismatches; all mutants were killed.
- **Suites on the merged tree:** PottsModels (with and without the reference data), Potts
  CPU and docs pass.
- **Gate:** not run; no kernels changed.
- **Follow-up:** P6.2a2 moves `akeeb_state` onto `InsertUntil`.

## 2026-09-30 — D-075: the target API ratified (coordinator)

- **Ratified.** The maintainer ratified `research/api-synthesis.md` at round 3, all nine
  §8.1 answers ("Ratify all nine (Recommended)", relayed verbatim by the spec-owner
  session).
- **Review history.** Round 1 found 4 blockers and round 2 found 2 new blockers. Round 3
  was approved for ratification.
- **Recorded as D-075.** It covers the §6.1 amendments and the Q9 breaking batch.
- **ROADMAP changes.**
  - The §6.4 build plan is folded into the Phase 6 rows (P6.0c, P6.2a2, P6.3a, P6.3b,
    P6.4a, P6.4b, P6.5b, P6.6–P6.12).
  - The round-3 should-fixes are acceptance text on those rows.
  - P6.0m2 is added for the `PottsProblem` rename, because P6.0m was already in flight.
- **Still untracked:** the draft sketches in `model-specs/sketches/`.

## 2026-09-30 — P6.0k merged: MTK discrete-time components (D-077)

- **Review.** Three adversarial rounds; round 3 approved.
  - Round 1: cross-scope Jacobi, extension guarding.
  - Round 2 blockers:
    - Gauss–Seidel across cells, with a GPU race on a single tick phase;
    - array variables collapsing into one slot.
  - Both are fixed: scratch slots `x__tick` when a rule reads another cell's slot, and scalar slots `name₊z_i` per array element.
- **Suites on the merged tree: all exit 0.**
  - CorePotts (QA);
  - PottsModels (with `POTTS_REFERENCES`);
  - MakiePotts;
  - Potts on Metal (P6.0k testsets on the device: 5/5, 4/4 and 2/2);
  - docs.
  - Full ModelingToolkit 11.45.1 is now in the test environment.
- **Gate.** CPU ratios are 0.977–1.006 with zero allocations. Metal flagged four cases, which `benchmark/ab.jl` settled against afdf507:
  - Merks 0.981, OpenVT 1.006, Akeeb 0.994.
  - Wortel 1.068 (6 rounds) and 1.057 (8 rounds). Per-round medians spread 67–112 ns/site on BOTH sides, with the candidate faster in some rounds, and Wortel's generated code is byte-identical to base (canonicalised, round-3 review). Accepted as noise.
- **Follow-ups in ROADMAP:** P6.0k2 (F1, F4, F6) and P6.0n (cell-ODE cross-cell reads).

## 2026-09-30 — P6.0m merged: four confirmed defects (D-076)

- **Review.** Two adversarial rounds. The round-1 blockers came from D-075, which landed after the branch was cut:
  - `Chemotaxis(when = true)` must mean every copy;
  - `a`/`b` must be reserved globally.
- **Coordinator rulings:**
  - the global reservation, with frozen p6_0f and p6_0a re-frozen as pure kind renames under D-076;
  - the `:arc_or_pair` zero-arc change reverted to TST semantics, because D-074 covers the local rule only.
  - Round 2 approved.
- **Merge conflicts:**
  - `src/codegen.jl`: P6.0m's integral-refresh readers now include the P6.0k discrete `next` rules;
  - `frozen.toml`: 11 entries.
- **Suites:** CorePotts (QA), PottsModels (with `POTTS_REFERENCES`), MakiePotts, Potts on Metal and docs all exit 0.
- **Akeeb.** The frozen band was revalidated under D-074 (40/40 seeds).
- **Gate.**
  - CPU: 0.976–1.001, with zero allocations.
  - Metal: two cases flagged. `ab.jl` against f554597 gives Wortel 1.015 and OpenVT 1.011, both within tolerance.
- **Follow-up:** P6.0m3 (`integral(Pre(w))`), filed earlier.

## 2026-09-30 — P6.0m2 merged: `CPMProblem → PottsProblem` (D-075, breaking batch part 1)

- **The change.**
  - The CorePotts type is renamed to `PottsProblem`, with the supertype unchanged and no alias.
  - The Potts symbolic constructors are now methods of `CorePotts.PottsProblem`, so the two are one function.
  - `SciMLBase.isdiscrete(::CPMAlgorithm) = true`.
- **Frozen acceptance.** `p6_0m2_potts_problem.jl` (D-075).
- **Review.** Round 1 approved.
  - Checkpoints don't serialise the type name, so old ones still load.
  - `isdiscrete` changes no dispatch at the pinned SciMLBase/DiffEqBase.
- **Coordinator fixes at merge.**
  - The symbolic `PottsProblem(sys, op, tspan)` docstring was orphaned before this change. It is now attached, so `?PottsProblem` shows both forms.
  - Docstring alignment.
  - A note on `isdiscrete` for when `AbstractPottsAlgorithm` lands.
- **Leftover `CPMProblem` mentions.** They remain only in the historical records (DECISIONS, PROGRESS, research/, the M1.4 ROADMAP line) and in this row's own text.
- **Merge checks.** CorePotts (QA), PottsModels, MakiePotts, Potts on Metal and docs all exit 0.
- **Gate.**
  - CPU: 0.969–1.001, with zero allocations.
  - Metal: three cases flagged. `ab.jl` against 9b4cf48 gives Akeeb 1.025, Wortel 0.953 and OpenVT 0.995, all within tolerance.

## 2026-09-30 — MTK-native investigation reviewed; P6.0o added (maintainer)

- **Research report.** `research/mtk-native-investigation.md` (spec owner) concluded that fully MTK-native Potts is not achievable.
- **Coordinator's review.** `research/mtk-native-review.md`.
  - **Confirmed:** that conclusion.
  - **Corrected:** five supporting claims. The largest: about 99 % of the 64² `ODEProblem` cost is the `InitializationProblem`, not scalarized codegen.
  - **Items:** adopted `PottsSystem <: AbstractSystem`; deferred per-entity MTK initialization and `PDESystem` input; rejected `mtkcompile` of model ODEs, SymbolicDiscreteCallback storage and the 64² gate.
  - **New defect:** `@components` silently ignores component initialization equations, events and bindings. Filed as P6.0k2 F7.
- **Maintainer.**
  - "Approve P6.0o (Recommended)". P6.0o is added with the review's acceptance and latency conditions. AUTHORING and INTERNALS now mark the subtype as planned.
  - "Correct, then commit (Recommended)". The report is committed with its corrections marked inline.
- **Upstream.** No amendment and no upstream post.

## 2026-10-01 — P6.0c merged: solver placement on PottsProblem (D-078; D-075 breaking batch complete)

- **The change.** `field_solver`, `ode_solver` and `solvers` are now `PottsProblem` construction keywords.
  - Several solver groups stay Jacobi, through `x__ode` scratch.
  - `remake` takes a rebuild hook.
  - The fingerprint is canonical and independent of the checkout path or build. This was verified against a `git archive` copy: 7 problems, Merks included.
- **Review.** Three adversarial rounds. The round-3 residual (flattening nested `+`/`*` in the code hash) was fixed by the coordinator with the reviewer's verified patch.
- **Merks.** Bitwise unchanged: all 5 digests recorded on 1092ada match.
- **Merge checks.** CorePotts (QA), PottsModels, MakiePotts, Potts on Metal and docs all exit 0.
- **Gate.**
  - CPU: 0.983–1.002, with zero allocations.
  - Metal: three cases flagged. `ab.jl` against 424bd63:
    - OpenVT 1.006, Wortel 0.794;
    - Akeeb 1.544 under parallel-agent load, then 1.016 over 10 rounds.
  - None of these three models has ODEs or a field, so their generated code is unchanged.
- **Follow-ups.** P6.0c2 (filed).
- **Note.** The disk filled up during the parallel batch. With the user's approval, the Julia 1.10/1.11 precompile caches (about 22 GB) were removed.

## 2026-10-01 — P6.0l merged: links to a copy-killed partner (D-079)

- **The change.** A link to a partner killed by a copy no longer reads 0/0. `link_delta` and `total_energy` skip volume-0 partners, and each `@link`/`@unlink` phase drops dead cells' links first (D-079).
- **Review.** Approved in round 1. D-066 item 4 (the killing copy's ΔH misses the edge credit) is filed as P6.0r.
- **Published models.** Generated code unchanged after canonicalising (D-070).
- **Merge checks.** CorePotts (QA), PottsModels, MakiePotts, docs, Potts on Metal and CorePotts on Metal all exit 0.
- **Gate.** It ran under parallel-agent load: CPU flagged Graner–Glazier sequential (1.067) and Wortel checkerboard (1.066); Metal flagged four cases at 1.5–2.9. `ab.jl` against 75daa0c settled all six:
  - Metal: Wortel 1.035, Merks 1.001, OpenVT 1.015, Akeeb 1.000 (8 rounds);
  - CPU: Graner–Glazier sequential 0.990, Wortel checkerboard 1.000 (6 rounds).
- **Tooling.** `ab.jl` starves other `exclusive.sh` waiters; filed as P6.0s. `ab.jl` needs absolute checkout paths.


## 2026-10-01 — P6.0m3 merged: `integral(Pre(x))` (D-080)

- **The change.** In an update block, `integral(Pre(x))` is the fold of the block-start values over the σ the block sees, in its own slot with no `x__pre` snapshot. An integral mixing `Pre` and bare reads of block-written variables, and `integral(Pre(x))` outside update blocks, are `ArgumentError`s (D-080).
- **Review.** Approved in round 1. The coordinator corrected the AUTHORING wording and the mixed-integral hint (253caab). Follow-ups: P6.0t (integral refresh waste), P6.0u (`@components` gaps; temperature error location).
- **Code.** 75 of 81 fingerprints unchanged; the 6 that changed use `integral(Pre)`. Published models unchanged.
- **Merge checks.** Potts, PottsModels, docs and Potts on Metal exit 0.
- **Gate.** Under parallel-agent load CPU flagged Graner–Glazier and Wortel sequential (1.050, 1.055) and Metal flagged four cases (1.21–2.24). `ab.jl` against 8b953b6: Metal Wortel 0.985, Merks 0.986, OpenVT 1.015, Akeeb 0.618 (8 rounds; base drew the slow power state); CPU Graner–Glazier 1.005, Wortel 0.995 (6 rounds).

## 2026-10-01 — P6.2a2 merged: `akeeb_state` on `InsertUntil` and StableRNG (D-082); GPU host-transfer rows (user)

- **The change.** `akeeb_state = layout(akeeb_layout(...))` (follower slab + `InsertUntil` leaders), clocks from `StableRNG(seed + 1)`; `akeeb_layout` exported, with the counted inventory via `layout_tally` (D-082).
- **Review.** Approved in round 1. 120-seed onset study: division onset unchanged (MCS 184.0 vs 186.1). The coordinator added lattice validation to `akeeb_layout` and fixed two test comments (5ec3e5a). Follow-up: P6.0w (sub-stream seeds through a stable mixer).
- **Merge checks.** The first run failed at precompile: the main checkout's workspace Manifest lacked the new `Logging` stdlib dependency; `Pkg.resolve()` fixed it. Then PottsModels, docs and Potts exit 0.
- **Gate: pass.** CPU 0.983–1.013 (Akeeb 0.996 / 1.013); Akeeb Metal 1.047. Three Metal flags on untouched models, `ab.jl` against 1554d56 (6 rounds): Graner–Glazier 0.959, Wortel 0.731, OpenVT 0.941.
- **User (2026-10-01).** New ROADMAP rows P6.0v (GPU host-transfer audit and transfer counters), P6.0v1 (lifecycle on the device), P6.0v2 (ODE/`HostPhase` column-only copies), P6.0v3 (launch fusion and Metal codegen fixes), with the overall accept; P6.0d round 2 builds the frozen mask on the device. The sub-stream seed row is renumbered P6.0w.

## 2026-10-01 — P6.0k2 merged: `@components` rejections and fixes (D-084)

- **The change.** F1 (`Pre` of component variables), F4 (only MTK's compile call is relabelled; Potts' own errors propagate), F6 (no double `_nonzero`), F7 (MTK features Potts would drop are `ArgumentError`s naming the component) (D-084).
- **Review.** Approved in round 1. The coordinator added the review's fixes (60e4ec0): stdlib frames recognised by path, `brownians` rejected, comments. Follow-up P6.0u (`tstops`/`assertions`, component names in binding errors).
- **Code.** All 18 fingerprints (published models and P6.0k fixtures) byte-identical.
- **Merge checks.** Potts, PottsModels, docs and Potts on Metal exit 0.
- **Gate: pass.** CPU 0.984–1.017. Metal flags on Graner–Glazier, Wortel and OpenVT; `ab.jl` against a213e39 (6 rounds): 0.952, 0.980, 0.983. The A/B base checkout needed its own `Pkg.resolve()` for P6.2a2's `Logging` dependency.

## 2026-10-01 — P6.0n merged: cell ODEs Jacobi across cells (D-086); initial-state decisions (D-087, user)

- **The change.** A cell ODE that reads other cells' ODE unknowns (`y[j]`, a gather, an unhoisted fold) gets Jacobi scratch even with one solver group, so results are independent of cell order and labels; `y[j]` on a same-group variable compiles (D-086, superseding D-078's Gauss–Seidel note).
- **Review.** Two rounds. Round 1 found that index expressions had silently switched to the held value (`w[ifelse(y > 0.5, id, 3 - id)]`); fixed in round 2. Follow-up P6.0x (gather allocation in cell-ODE rates, pre-existing).
- **Code.** Fingerprints of every published model unchanged.
- **Merge checks.** Potts, PottsModels, docs and Potts on Metal exit 0.
- **Gate: pass.** CPU 0.996–1.029. One Metal flag, Graner–Glazier (1.129): `ab.jl` against 23933c2 gave 1.052 at 6 rounds under load, then 1.013 at 10 rounds.
- **User (2026-10-01).** "i like both recs" (also relayed by the peer session): `merks_state` moves to `Scattered` at P6.3d, and `BrickWall`/`Plane`/`Spheres` are replaced by general layers with doc recipes at P6.4d/P6.5c (D-087, amends D-075 §3.3).

## 2026-10-01 — P6.0e2 merged: primes of non-site quantities are Potts errors (D-088)

- **The change.** `m′` for a cell or model variable, parameter, kind, observed quantity or inherited name is an `ArgumentError` ("primes exist only for site/field variables"), raised by translating the constructor's `UndefVarError`; every `PottsSystem` construction rejects a declared `x′` beside a site/field `x` (D-088).
- **Review.** Two rounds. Round 1's static scan rejected valid local names (`let λ′`, `for n′ in …`); round 2 replaced it with catch-and-translate, which also closed the `@extend` gap. Residual (hand-written `@extend` bases) filed under P6.0u.
- **Code.** Fingerprints unchanged; constructor time within noise.
- **Merge checks.** Potts, PottsModels, docs, MakiePotts and Potts on Metal exit 0.
- **Gate.** Under parallel-agent load every CPU checkerboard case read 1.06–1.11 and OpenVT Metal 1.072. `ab.jl` against 6d4b51e (6 rounds): checkerboard Merks 1.019, OpenVT 1.000, Graner–Glazier 1.004; Metal OpenVT 0.982.

## 2026-10-01 — P6.0r merged: a killing copy's ΔH drops the dying cell's links (D-083, maintainer); no quiet-MCS sync on GPU (D-089, user)

- **The change.** For a copy that kills its old owner, `link_delta` removes that cell's edges at their pre-copy energy (no edge credit), so ΔH equals the H difference plus the empty-state cell/cluster credit; `total_energy` sums alive cells and live clusters only, free slots add nothing; the self-check helpers use `_killing_credit` (D-083, maintainer: "Yes, ΔH = H change").
- **Review.** Approved in round 1; the coordinator added a free-slot test and fixed a docstring and a test comment (b3c9559). `link_delta` cost unchanged (59.38 vs 59.43 ns/site).
- **Fingerprints.** Every published model's fingerprint changes (`total_energy` is hashed); per-MCS kernels unchanged; no stored checkpoints exist.
- **Merge checks.** CorePotts (QA), Potts, PottsModels, MakiePotts, docs, CorePotts on Metal and Potts on Metal exit 0.
- **Gate: pass.** CPU 1.004–1.021. Metal flags OpenVT (1.319) and Akeeb (1.076); `ab.jl` against 1a9b5d3 (8 rounds): 0.997 and 1.002.
- **P6.0v review and user decision.** The P6.0v audit review asked for a QA guard on the counting helpers (round 2 in progress, which also merges the approved P6.0d). User: "Remove it, device-side (Recommended)": on GPU the lifecycle is planned on the device and a quiet MCS costs 0 syncs / 0 transfers (D-089, amends D-035 and D-085). New rows P6.0v7 (gate times Metal to completion; top priority), P6.0v4, P6.0v5; P6.0v8 folded into P6.0v3.

## 2026-10-01 — P6.0d merged: the frozen-kind mask follows lifecycle events (D-081)

- **The change.** After an MCS with lifecycle events the mobility mask is recomputed: on a device by one kernel (standard rule: frozen kind or outside the domain), on the host for a custom `remake_frozen`. Models whose mask cannot vary never refresh. New public `refresh_frozen!`, `frozen_sites`, `u_modified!` (re-exported), hooks `frozen_varies`/`frozen_kinds`; MakiePotts frames use each state's own mask (D-081).
- **Review.** Three implementer rounds. Round 2 moved the mask to the device and dropped the whole-state snapshot (user's GPU standard, P6.0v); round 3 fixed the hook defaults (checkpoint resume and `remake` saw the t0 mask) and removed the blocking 8-byte read-back by carrying the counts in the lifecycle's read-back. The coordinator applied the final fix (ee2331b: the read-back stays 4 B with its sync, 12 B only while counts are pending).
- **Note.** A P6.0d implementer's broad `pkill -f` killed another agent's Metal run mid-session; agents are now told to kill only their own PIDs.
- **Merge checks.** CorePotts (QA), Potts, PottsModels, MakiePotts, docs, CorePotts on Metal and Potts on Metal exit 0. Fingerprints unchanged.
- **Gate: pass.** CPU 0.993–1.039. Metal flags (Wortel 1.40, Merks 1.51, OpenVT 1.73, Akeeb 1.91) under parallel load; `ab.jl` against ec544d8 (8 rounds): 1.005, 1.040, 0.980, 1.028 (enqueue-timed, P6.0v7 pending).

## 2026-10-01 — P6.0v merged: host-transfer audit and counters (D-085)

- **The change.** `research/gpu-host-transfer-audit.md` lists every synchronize, host↔device copy and host-side step in an MCS, with a verdict for each (remove, file or justify). One set of counted helpers (`_sync!`, `_to_host`, `_copy!`, `_readback`, `_snapshot`; `transfers.jl`) feeds `stats.syncs`, `stats.transfers` and `stats.transfer_bytes` on devices; the CPU compiles to what it was. A QA guard rejects raw transfers in the integrator; a Metal wait-identity test wraps `Metal.wait_cmdbuf!` (Metal pinned to 1.10.0). Frozen `p6_0v_transfer_counters.jl`; Merks' wait count is `@test_broken` until P6.0v3.
- **Findings carried forward.** Device→device `copyto!` waits on the GPU twice (P6.0v3/P6.0v8); Akeeb event MCS move about 137 KB (P6.0v1); the old gate timed only enqueue for Graner–Glazier and Wortel (P6.0v7). Rows P6.0v1–P6.0v5 and P6.0v7 carry the work; D-089 (user) sets a quiet MCS to 0/0/0.
- **Merge checks.** CorePotts (QA), Potts, PottsModels, MakiePotts, docs, CorePotts on Metal and Potts on Metal exit 0.
- **Gate: pass.** CPU 0.995–1.031. Metal flags (Wortel 2.90, Merks 1.50, OpenVT 1.67, Akeeb 1.86) under parallel load; `ab.jl` against f133b69: Wortel 1.000, Akeeb 1.034 (6 rounds), Merks 0.988, OpenVT 0.994 (10 rounds; 6-round reads of 1.36 and 1.46 were load).

## 2026-10-01 — P6.0s + P6.0v7 merged: a fair machine lock; Metal timed to GPU completion (D-090)

- **The change.** `tools/exclusive.sh` is a FIFO ticket queue in front of the old lock (tickets stale after 5 min without refresh, the lock after 3 h; stray entries ignored; keeper exits with its holder). `gate.jl` and `ab_one.jl` time device `step!` followed by `synchronize`; the Metal baseline was re-measured once (GG 86.3, Wortel 139.3, Merks 179.7, OpenVT 80.6, Akeeb 187.8 ns/site).
- **Review.** Two rounds (dead-ticket starvation and stray entries fixed in round 2); the coordinator added the two optional nits (keeper skips a failed `ps`; ids without leading zeros).
- **Merge checks.** Tooling only (no library code). Frozen check 69/69; transition test 15/15 and 23/23; tooling acceptance on Metal 32/32 (GG 72: `ab_one` 149.6 vs `step!`+`synchronize` 148.2 ns/site).
- **Gate: pass.** CPU 0.982–1.019. Every Metal row flagged together (1.50–2.08, median 1.79) while three agents ran: a common-mode GPU slowdown, not a per-case change (no device code changed). The P6.0v3 follow-up normalises Metal flags by the run's median Metal ratio.
- **Transition.** `ab-base` moves to this commit; live worktrees call the main checkout's `tools/exclusive.sh` by absolute path.

## 2026-10-01 — P6.1a6 merged: the layout protocol (D-091)

- **The change.** Every layer, built-in or user, is one method `paint!(op::LayoutState, l, lat)` on an opaque state (`new_cell!`, `assign!`, `owner`, `kindof`, `ncells`, `record!`) and the lattice queries `size`, `isperiodic`, `indomain`. `layout(l, x; report = true)` returns one report row per leaf layer; `Tiling(partial = :skip | :clip)`; `splits = :warn | :allow`; `remake` on layers. `paint!(σ, kinds, l, lat)`, `layout_tally` and `_AkeebSlab` are removed with no alias; `akeeb_layout` is a plain `overlay(Tiling, InsertUntil)` and reproduces all 16 Akeeb digests bit for bit. `p6_2a` and `p6_2a2` re-frozen (API calls only).
- **Review.** One round, approved; coordinator doc fixes. Painting at parity or faster (Akeeb 1.55 → 0.95 ms) except 1×1 tiling (+1.4 ns per box).
- **Merge fix.** P6.0v's raw-transfer allowlist pinned `src/layouts.jl` at 3; the rewrite leaves 2 (Frame masks, setup only).
- **Merge checks.** CorePotts (QA), Potts, PottsModels, MakiePotts, docs and Potts on Metal exit 0.
- **Gate: pass.** CPU 0.991–1.032. Metal rows all flagged together (1.52–2.07) while agents ran, as on the previous merge; this change has no device code.

## 2026-10-01 — P6.1a7 merged: `Scattered` overlap test on an occupancy mask (D-094)

- **The change.** `Scattered` tests each draw against a BitArray mask of its region (the draw's box grown by `gap`, split at a periodic wrap) instead of every box placed so far: O(box) per draw, no allocation per draw. Same draws and decisions: σ, kinds and reports identical to before.
- **Review.** One round, approved: 2·10⁶ random decisions and 10⁵ random layouts identical to the old pairwise test; coordinator nits (comment wording, a long line).
- **Numbers.** 10⁴ cubes of 5³ at 200³: 17 ms closed and periodic (was 480 and 860 ms); per-box time at 4·10⁴ vs 4·10³ squares: 1.2× (was 9.9×).
- **Merge checks.** Host-only layout code: PottsModels (P6.1a7 126/126), Potts and docs exit 0. No gate case paints with `Scattered`; gate not rerun.

## 2026-10-01 — P6.0v2 merged: ODE and `HostPhase` copy only the columns they use (D-092)

- **The change.** `HostPhase(f!; every, reads, writes)` copies only the declared leaves (σ or cell columns); adaptive-ODE phases copy only the unknowns and the leaves their rates read (a scan of the generated code, falling back to the whole state); generated `@link`/`@unlink` phases declare their reads and writes; the static domain mask comes down once per run. Per-MCS Metal bytes: adaptive ODE 5388 → 1032, `@link` 10752 → 4864, declared HostPhase 2000 → 384, all independent of unused columns and lattice size.
- **Review.** Two rounds: round 1 found host phases handed a cached `p` (stale after in-place writes); round 2 passes the live `p`, caches only the mask, and adds sentinel tests for the scanned read sets. R4 filed as P6.0v2b; the idle second sync under P6.0v3.
- **Merge checks.** CorePotts (QA), Potts, PottsModels, MakiePotts, docs, CorePotts on Metal and Potts on Metal exit 0.
- **Gate: pass.** CPU 1.004–1.032. Metal rows all flagged together (1.32–1.89) under load; `ab.jl` against 3df39655 (6 rounds): Akeeb 0.991, OpenVT 0.959.

## 2026-10-01 — P6.0w merged: sub-stream seeds through a stable mixer (D-093)

- **The change.** `Potts._substream_seed(seed, stream)` (SplitMix64 of the seed and the stream name's FNV-1a id) derives every sub-stream seed; `akeeb_state`'s clocks use the `:clock` stream instead of `StableRNG(seed + 1)`. σ and kinds are unchanged; clocks differ per seed with the same law. `p6_2a2` re-frozen (oracle stream and a comment).
- **Review.** One round; the coordinator replaced a seed re-pick in `mechanisms.jl` with a correct attribution (the clock reset marks exactly the cells that divided). Akeeb divisions over 80 seeds: mean 585.8, SD 18.7 (band 585.0 ± 3×16.4; no re-baseline).
- **Merge checks.** PottsModels and Potts exit 0 (branch: also CorePotts, docs, Potts on Metal). No step-loop change; gate not rerun.

## 2026-10-01 — Merks 2006 parameter set as the defaults (D-098, user)

- **The change.** `MerksVasculogenesis()` defaults are the Merks et al. (2006) set: V₀ = 100, λ = 50, λ_L = 5, L = 50, χ = 1000, T = 50, D_c = 0.75, ε = δ = 5.4·10⁻³, J = [0 20; 20 40], with `ExplicitEuler(substeps = 15, lower = 0)`; `merks_state` side 10. The old defaults fragmented the network (largest component 0.27–0.45 of the cells); the 2006 set keeps it connected (0.98–1.0). New frozen `merks_2006_defaults`; `p6_0c_solver_placement` and `p6_0v_transfer_counters` re-frozen with `side = 7` (sizes only); Fig. 6 mechanism test retuned.
- **Gate.** `merks_100` is now 25 cells of 10² with 15 substeps; CPU rows re-baselined (sequential 286.41, checkerboard 287.85 ns/site — the 3× is the substeps, about 16 ns/site each). The Metal row measured 1.51× the old baseline, inside the common-mode band of the other Metal rows (1.32–1.89) under load, so it is not re-baselined (corrected at the P6.0v1 merge: re-baselined to 729.75).
- **Merge checks.** CorePotts (QA), CorePotts on Metal, Potts, Potts on Metal, PottsModels, MakiePotts, docs and the gate exit 0.

## 2026-10-01 — Lab docs merged (D-097)

- **The change.** Documentation for the lab session: getting started, tutorials, the manual, and Gridap-style model pages (construction tutorial → constructor docs → reproduction) for Graner–Glazier, Merks, Akeeb, Wortel Act and OpenVT, each opening with a full paper run as a video (`docs/paper_runs/*.jl` → `docs/src/assets/paper_runs/`), with "paper: X; here: Y" reductions and a differences table. States are shown as videos. Reproduction 09 shows replicate 1 as a video (D-097, re-frozen). Internal IDs removed from docstrings and user-facing error strings. The Merks page and tutorial model use the 2006 defaults (D-098).
- **Merge checks.** Potts, PottsModels, MakiePotts exit 0; a fresh clone with an empty depot instantiates `docs/` and builds it (exit 0; only the Documenter `example_size_threshold` notice).

## 2026-10-02 — P6.0v1 merged: the lifecycle on the device (D-089, D-096)

- **The change.** On a device the lifecycle (trigger, plan, partition, copies and links, rules, frozen-mask refresh) runs as one fused kernel sequence with no synchronization and no transfer; statistics and mask counts fold into `integ.stats` at the host read points. Quiet and plain-division event MCS cost 0 syncs / 0 transfers / 0 B on Metal (were 1/1/4 B and 2/18/1098 B); cluster and link events also run on the device. Host fallback for a `rebuild!` hook or a custom `remake_frozen`; the first launch falls back fused → staged → host with one warning. A cell whose `m2[k,k]` exceeds `typemax(Int32)` is deferred on the device (warned; divides on the CPU only).
- **Review.** Two rounds: round 1 found a race between the newborn's link cleaning and a linking `divide!` rule, and a late, sticky Int32 moment guard; round 2 approved with exactness (trackers recounted from σ) and bitwise determinism over 23 Metal comparisons, id allocation in lockstep with the host planner under deferral, and no added sync from the fallback.
- **Merge.** Combined with D-098's `side = 7` edit of `p6_0v_transfer_counters.jl` (listed under D-096) and gave the Merks fixture of `p6_0v1_device_lifecycle.jl` `side = 7` (D-060 style); internal IDs removed from the new docstrings.
- **Merge checks.** CorePotts (QA), CorePotts on Metal, Potts, Potts on Metal, PottsModels, MakiePotts and docs exit 0.
- **Gate / A/B.** Idle machine: CPU 0.969–1.010; Metal GG 1.03, OpenVT 0.871, Akeeb 0.774, Wortel 1.21 (A/B 0.889), Merks 4.06 — `ab.jl` against the pre-merge base gives 1.008, so the Merks row was mis-baselined at D-098 (see its correction) and is re-set to 729.75. Akeeb Metal A/B 0.695 against fd84ba91 (review).

## 2026-10-02 — P6.0ad merged: `Barker` carries its offset (D-100)

- **The change.** `Barker(; offset)` shifts ΔH as Metropolis does (`1/(1 + e^{(ΔH − δ)/T})`; at T ≤ 0 the two laws coincide); `@sweep Barker(; offset)` and `acceptance = Barker(; offset)` carry it (it was accepted and dropped). `offset = 0` is the old law bit for bit; a Float64 offset is narrowed to Float32 on a device.
- **Review.** One round, approved (0 mismatches on an extreme-value grid, zero allocation, CPU and Metal agree in law); coordinator doc nits.
- **Merge checks.** CorePotts (QA), CorePotts on Metal, Potts, PottsModels and docs exit 0. No gate model uses Barker; gate not rerun.

## 2026-10-02 — P6.0aa merged: `:arc_or_pair` exempts a two-cell ring only without medium (D-099)

- **The change.** `connectivity(k; rule = :arc_or_pair)` is `ring_arcs ≤ 1 || (ring_cells == 2 && ring_medium == 0)`; new public copy-scope value `ring_medium` (medium sites on the ring; out-of-domain sites are neither medium nor a cell). Multicell `WortelAct(connected = true)` no longer accepts copies at cell–cell–medium junctions that split cells.
- **Review.** One round, approved: other ring values identical to before over ≈ 575k random proposals; splits 167 → 7 (sequential, 12 seeds × 1000 MCS); no speed change; Metal agrees. Closed edges still differ from TST's frame-as-cell reading (documented; P6.0ae).
- **Merge checks.** CorePotts (QA), CorePotts on Metal, Potts, Potts on Metal, PottsModels and docs exit 0. No gate model uses `:arc_or_pair`; gate not rerun.

## 2026-10-02 — P6.0v3 + P6.0v8 merged: no GPU wait in a quiet MCS; launch fusion (D-101)

- **The change.** Device→device copies and fills in the step path are kernels (Merks: 30 GPU waits per MCS → 0); a model's last after-MCS cell update runs inside the lifecycle trigger when Potts proves the trigger reads its columns only at the cell's own index (`Lifecycle(…; before)`; OpenVT 10 → 9, Akeeb 14 → 13 launches per quiet MCS); an adaptive-ODE phase right after another skips its sync (2 → 1); T3's uncounted `fill!` removed. Every gate model: 0 syncs, 0 transfers, 0 B, 0 GPU waits per quiet MCS on Metal.
- **Review.** One round, approved: fused = unfused bitwise over 252 comparisons (CPU and Metal, every fallback form, `Every(2)`, callbacks, `reinit!`, resume); coordinator: no launch for empty copies, docstring ID removed, follow-ups as P6.0af.
- **Merge checks.** CorePotts (QA), CorePotts on Metal, Potts, Potts on Metal, PottsModels, MakiePotts and docs exit 0.
- **Gate: pass.** CPU 0.994–1.034. Metal: Merks 142.77 ns/site (0.196 of its baseline; now faster than the CPU's 286), OpenVT 0.625, Akeeb 0.657, GG 1.016, Wortel 1.122 (flagged; reviewer's reversed A/B 0.998). Metal rows re-baselined on this idle run: Merks 142.77, OpenVT 50.36, Akeeb 123.46.

## 2026-10-02 — P6.0x merged: a gather in a cell-ODE rate allocates nothing (D-103)

- **The change.** Fixed-step ODE systems whose rates contain a gather are written out in place instead of calling a per-cell `rhs` closure (Julia 1.12 builds it as an opaque closure on every call when the rate is not inlined): 480–1472 B per warm MCS → 0, values bitwise unchanged, fingerprints of other models unchanged. It also fixes Metal compilation of gather ODEs (all failed before).
- **Review.** One round; the coordinator corrected the rationale: the closure, not the gather, is the cause, so non-gather rates that are not inlined still allocate and fail on Metal — P6.0ag (D-104), started.
- **Merge checks.** CorePotts, Potts, Potts on Metal, PottsModels and docs exit 0.
- **Gate: pass.** CPU 0.987–1.021; Metal Merks 0.963, OpenVT 1.003, Akeeb 1.006, Wortel 1.043, GG 1.087 (flagged; GG has no ODE, so this change does not touch its step — load from concurrent agents).

## 2026-10-03 — P6.0y merged: the automatic substep count keeps a margin and counts linear reaction (D-102)

- **The change.** `ExplicitEuler()` without `substeps` picks `n = max(1, ceil(dt·(D·Σ4/h² + k)/1.8))` from the live parameters, k a bound on the reaction's |∂f/∂c| (parameters, indicators, `rand()`, kind tables, `ifelse`; another field's Δ is a source); state-dependent rates fall back to k = 0 with a build-time warning, and a negative diffusion coefficient warns. Diffusion–decay that blew up (2D, D = 0.5, k = 0.2: ×1.21 per MCS) now decays; explicit counts above the new one are unchanged bit for bit (Merks' 15).
- **Review.** Three rounds (a `rand()` reaction no longer built; per-kind decay fell back; cross-diffusion cancelled the own coefficient, also on the base), then approved.
- **Merge.** Merks' fingerprint changes with the substep function; `p6_0x_gather_ode_alloc.jl`'s Merks pin re-recorded (D-102 addendum).
- **Merge checks.** CorePotts, Potts, Potts on Metal, PottsModels and docs exit 0.
- **Gate.** CPU (idle rerun) 0.967–1.016. Metal (under concurrent review load) 1.008–1.046, OpenVT 1.160 flagged — OpenVT has no field, so this change does not touch its step.

## 2026-10-03 — P6.0ag merged: every fixed-step ODE system is expanded in place (D-104, D-105)

- **The change.** The per-cell `rhs` closure is gone: every fixed-step rate evaluation (Euler, RK4 stages) is an in-place block. Rates that were not inlined (Hill circuits, `ifelse` chains, long sums, population folds) no longer allocate (48–640 B per MCS → 0) and now compile on Metal (all failed with `jl_new_opaque_closure_jlcall`), matching the CPU Float32 run (Hill within 4 ulp of device math). Fingerprints of ODE models change by design.
- **Finding (D-105).** Symbolics orders sum terms by the hashes of Potts-registered operators, which change with each package build, so rates with `population`/`gather`/`at` can move by a few ulp between builds of identical source; P6.0ag's model-scope pins compare within 8 ulp; canonical term order is P6.0ah.
- **Review.** One round, approved (closure removal bitwise-safe over 752 runs; full Metal suite completes).
- **Merge.** Merks' fingerprint pin in this file re-recorded for P6.0y's substep function (D-105 addendum).
- **Merge checks.** CorePotts, Potts, Potts on Metal, PottsModels and docs exit 0.
- **Gate.** CPU 0.968–1.020; Metal 1.007–1.043, GG 1.125 and OpenVT 1.292 flagged; `ab.jl` OpenVT against d5bfd3dc (before P6.0x/y/ag), 8 rounds: 1.016 (55.4 → 56.6 ns/site, every round), so the flag was noise and the three merges cost OpenVT about 1.6 % on Metal.

## 2026-10-03 — P6.1e merged: `graner_glazier_aggregate` defaults to a 60-site margin (D-106)

- **The change.** Default margin 10 → 60 on the periodic lattice (side `2⌈√(40n/π)⌉ + 1 + 2margin`): long runs no longer drift onto the edge or join the periodic image; explicit margins bitwise unchanged. Non-frozen tests that need a small aggregate pass `margin = 10`.
- **Checks.** Frozen P6.1e 92/92, P6.1b2 12/12; PottsModels, Potts and docs exit 0 (branch based on the current `monorepo`; no step-loop change, gate not rerun).

## 2026-10-03 — P6.0ah merged: canonical term order in generated code (D-107)

- **The change.** Sums and products in generated code are ordered by a key of their generated code text (memoised per build), fold slots, gather numbers and integral names are canonical, so a rate's floating-point result no longer depends on the build's operator hashes (D-105). `p6_0ag` item 3 compares bitwise again (re-frozen under D-107); 43 new symbolic tests.
- **Review.** Fold keys now carry bound-variable names (two folds differing only in their bound variable no longer collide), keys are memoised, integrals keep their folds inside; approved. Follow-ups P6.0ai (integral of a fold is O(sites × cells)) and P6.0aj (`_GATHER_COUNT` is not thread-safe).
- **Merge checks.** CorePotts, Potts, Potts on Metal, PottsModels and docs exit 0.
- **Gate: pass.** CPU 0.972–1.028. Metal OpenVT 1.049, Akeeb 1.016; Wortel 1.150, Merks 1.065, GG 1.062 flagged; `ab.jl` against 457104d8, 6 rounds: Wortel 1.005, Merks 1.003, GG 1.018 (noise).

## 2026-10-03 — P6.0af merged: the device lifecycle's mid-sequence handover; `generated_code` shows fusion (D-108)

- **The change.** The staged device form's first launch is compiled before anything is enqueued and counts the kernels it enqueues: a failure at the trigger or the planner (k ≤ 2) hands the MCS to the host planner without `before` and without this MCS's device counts (the k = 2 handover double-counted divisions before); a failure after the partition (which writes σ) is rethrown (`_StagedFailedMidway`) instead of handing over a partly divided state. `generated_code(sys).lifecycle` shows the trigger and the fused `before`. X4 stays deferred in the row.
- **Review.** Two rounds; round 1 approved with notes (the post-partition rethrow, the compile-on-empty-range comment, launch counts at the handover), done in round 2.
- **Merge checks.** CorePotts (CPU and Metal), Potts, Potts on Metal, PottsModels, MakiePotts and docs exit 0 (a first run used wrong test projects; rerun).
- **Gate.** CPU 0.991–1.056 under three concurrent agents (GG seq 1.053, OpenVT cb 1.056 flagged; no CPU step change). Metal under the same load 1.2–2.0×; `ab.jl` against 2f54c1e9, 4 rounds: GG 0.981, Wortel 1.011, Merks 0.874, OpenVT 1.007, Akeeb 0.986.

## 2026-10-03 — P6.0aj merged: a model build keeps its state per build (D-109)

- **The change.** The bound-variable/draw counter, the lattice dimension that `centroid()` reads and the `@extend` state are one per-build state in a `ScopedValue`, so models built concurrently (threads, or tasks that yield mid-build) get the same generated code, names and fingerprints as built serially; 4 threads used to give 16–21 of 32 builds different code, reused names within a model and `centroid()` build errors. Serial output unchanged for all 225 systems checked. Only an `@extend` base continues the outer build; any other model built inside a body is its own build (it used to reset the outer model's lattice dimension).
- **Review.** Two rounds (round 2: the one-shot base flag), approved.
- **Merge checks.** Run together with P6.0ab's (below).

## 2026-10-03 — P6.0ab merged: kind tables from parameters; `observe` by name (D-111)

- **The change.** A kind table whose entries are expressions of parameters (`J[kind, kind] = [0 Jx Jx; …]`) builds (it raised a `MethodError`) and follows its inputs at build, `remake` and the integrator setters, with the problem's scalar type kept and symmetry checked on the values; `observe(sol | prob, :name)` resolves a variable, `@observed`, built-in or parameter (it raised "cannot lower constant"), with a clear error for an unknown name. Fingerprints of existing models unchanged.
- **Review.** Two rounds: the parameters page now says an explicit value holds only until the next change of another parameter (the existing rule; P6.0ak to keep it), the declaration order and `observe`'s resolution order. Follow-ups P6.0ak, P6.0al.
- **Merge checks (P6.0aj + P6.0ab).** CorePotts, Potts, Potts on Metal, PottsModels (`-t 4`), MakiePotts and docs exit 0. No step-loop change in either; gate not rerun.

## 2026-10-03 — P6.0ak merged: explicit parameter values survive unrelated changes (D-112)

- **The change.** A computed parameter (scalar or kind table) is re-derived only by a change that names one of its inputs (transitively), so an explicit value from `remake`, a setter or the operating point survives unrelated changes; a `setp` with several names is one change, validated all-or-nothing (new CorePotts hook `set_parameters`). Unrelated changes are 2–3× faster.
- **Review.** Two rounds (round 2: the batched `setp`), approved, including on Metal. Follow-up P6.0ap.
- **Merge checks.** CorePotts (CPU and Metal), Potts, Potts on Metal, PottsModels (`-t 4`), MakiePotts and docs exit 0. No step-loop change; gate not rerun.

## 2026-10-03 — P6.0al merged: one name, one category (D-113)

- **The change.** Kinds, parameters, variables, observed quantities, relations, relationships and components (with their `comp₊name` quantities) share one namespace, and each vector claims its name and its component names: a clash is an `ArgumentError` naming the name, both categories and the base, however the system is built (one model, `@extend`, `extend`, programmatic). `extend` replaces a vector as a whole and may lengthen it, not shorten it. About 1 µs per build.
- **Review.** Three rounds (vector component names; whole-vector override; no shorter override), approved.
- **Merge checks.** CorePotts, Potts, PottsModels (`-t 4`), MakiePotts and docs exit 0. Build-time only; gate and Metal not rerun.

## 2026-10-03 — P6.0ai merged: population folds inside `integral` are hoisted (D-110)

- **The change.** A population fold inside `integral(x)` that reads neither the site nor the cell is computed once per refresh in a model slot (named by content, canonical), not at every site of every tracker: the frozen 200², 400-cell case went from 22× the hand-factored cost to 0.80–0.95×. Every refresh point (init and checkpoint load, before-MCS, gated, after-block stale refresh, MCS boundary, observed) computes its slots first; observed integrals no longer write into the observed state. Models without such a fold get exactly the base's phases, types and fingerprints.
- **Review.** Two rounds plus a performance round, approved.
- **Finding (A/B method).** A Metal A/B of a few percent is not evidence on its own: identical source in two checkouts differed by up to ±4% (Merks: 1.042, then 0.975 in a later session), because each checkout's compiled package caches differ and are rebuilt often in the shared depot. Before treating a small Metal ratio as a regression, compare two checkouts of the same source (or the host enqueue time with `--pkgimages=no`).
- **Merge checks.** CorePotts, Potts, Potts on Metal, PottsModels (`-t 4`), MakiePotts and docs exit 0.
- **Gate.** CPU 0.971–1.033; Metal GG 1.018, Merks 0.942, OpenVT 1.030, Akeeb 1.033, Wortel 1.090 flagged; `ab.jl` Wortel against ea26df4c, 6 rounds: 0.940 (noisy after the machine slept; the implementer's earlier run 0.974).

## 2026-10-03 — P6.0an merged: `remake` with a NamedTuple (D-115)

- **The change.** On a model's problem, `remake(prob; p = (λ = 3.0,))` is a parameter map like pairs or a `Dict` (one change under D-112); a whole `PottsParameters` of the same type is taken as given, of another type only with the same names (values converted); `p`/`u0` `= missing` or `nothing` keep the current value, as in SciML; any other value is an `ArgumentError` instead of a silent replacement that failed later. A NamedTuple `u0` works in `remake` and `reinit!`. Hand-written CorePotts problems keep their contract.
- **Review.** Two rounds (round 2: whole objects checked, keep sentinels, `u0` catch-all), approved.
- **Merge checks.** CorePotts, Potts, PottsModels (`-t 4`), MakiePotts and docs exit 0. Host-only; gate and Metal not rerun.

## 2026-10-03 — P6.0am merged: an `@extend`-bound name redeclared keeps its own default (D-114)

- **The change.** `@extend λ = base = Base(); @parameters λ = 3.0` used to take the base's symbol as the default ("does not reduce to numbers") and to drop a constructor keyword `λ = 5`; each parameter keyword is now captured before section code runs, so a redeclared bound name takes the extension's default or keyword (scalars, vectors, kind tables), and every expression reading it uses that one value. Names starting with `#` are rejected. Fingerprints of existing models unchanged.
- **Review.** One round, approved; follow-ups (vector regression test, `#` names) done before merge.
- **Merge checks.** CorePotts, Potts, PottsModels (`-t 4`), MakiePotts and docs exit 0. Build-time only; gate and Metal not rerun.

## 2026-10-03 — P6.0ap merged: parameter-setter loose ends (D-116)

- **The change.** A `setp` list naming a state is an `ArgumentError` at build pointing to `setu`/`setsym`; `setsym`/`setu` with a list sets its parameters as one change and its states as before; `SII.remake_buffer` returns a new parameter object (it overflowed the stack) for a model's problem and for a hand-written NamedTuple one; hand-written CorePotts problems with a NamedTuple `p` get `getp`/`setp`/`integ.ps[x]` by field name; a read-only built-in in a list setter is reported as read-only. `setp_oop`/`setsym_oop` now work.
- **Review.** One round, approved (including Metal); follow-ups done before merge.
- **Merge checks.** CorePotts (CPU and Metal), Potts, Potts on Metal, PottsModels (`-t 4`), MakiePotts and docs exit 0. Single-name setters unchanged in time; no step-loop change, gate not rerun.

## 2026-10-03 — P6.0ao merged: computed defaults that call functions or read kind tables (D-117)

- **The change.** A computed default (scalar or kind-table entry) is evaluated numerically: Base math, `÷`/`div`, comparisons, lazy `ifelse`, constants, registered functions and kind-table reads by kind number (with `@kinds medium P Q`, `V₀[2] ≡ V₀[Q]`), in the problem's scalar type; D-112 re-derivation sees through them. A default reading a variable or built-in, drawing `rand()`, reading an out-of-range kind or failing on its values is an `ArgumentError` naming the parameter. Kind-table literals are rewritten like the rest of the model (a table reading a table works). `÷`/`div` now work in model code on CPU and Metal (Float32 without Float64; equal to Base while the quotient is exact); a model may not define its own `div`. Fingerprints of existing models unchanged.
- **Review.** Two rounds (round 2: Metal-safe float division, the substep bound, local `div` rejected), approved.
- **Merge.** One conflict with P6.0am on the kind-table keyword line: both the hidden keyword local and the literal rewrite kept.
- **Merge checks.** CorePotts, Potts, Potts on Metal, PottsModels (`-t 4`), MakiePotts and docs exit 0. No existing model's step code changes; gate not rerun.

## 2026-10-03 — P6.0q closed: a fold reading `time` in a cell ODE runs on Metal (D-119)

- **Finding.** The `InvalidIRError` the row reported came from the per-cell `rhs` closure that P6.0x/P6.0ag removed; on 4e81e1eb the P6.0n fold fixture and the time, mcs, both and two-fold variants under Euler, substepped Euler and RK4 run on Metal bitwise equal to the CPU Float32 run. No source change; the acceptance file is a regression guard wired into `test/gpu.jl`.
- **Merge checks.** Potts, Potts on Metal and PottsModels (`-t 4`) exit 0.

## 2026-10-03 — P6.0p merged: the fingerprint includes the tick cadence (D-118)

- **The change.** The fingerprint also hashes non-default cadences kept outside the generated code: discrete-component clocks (period and phase, resolved after `mcs_duration`), `@divide … Every(n)`, `@link`/`@unlink … Every(n)`, and a non-default `mcs_duration` (the `Adaptive` ODE solver's step). A checkpoint no longer loads into a problem with another schedule. Models on the default schedule — every PottsModels system and every existing pin — keep their fingerprints.
- **Review.** Two rounds (round 2: `mcs_duration`), approved. Follow-up P6.0aq (the acceptance law's offset).
- **Merge checks.** Potts and PottsModels (`-t 4`) exit 0. Host-only (problem build); gate and Metal not rerun.

## 2026-10-04 — P6.0aq merged: the fingerprint includes the acceptance law (D-121)

- **The change.** The fingerprint also hashes a non-Metropolis `@sweep` law and a non-zero `offset`, so a checkpoint no longer loads across `Metropolis`/`Barker` or across offsets. Defaults (Metropolis, offset 0) keep their fingerprints; every PottsModels pin holds.
- **Review.** One round, approved. Follow-ups P6.0ar (neighbourhoods) and P6.0as (NaN offset, closure `combine`).
- **Merge checks.** Potts and PottsModels (`-t 4`) and the docs build exit 0. Host-only (problem build); gate and Metal not rerun.

## 2026-10-04 — P6.0ar merged: the fingerprint includes the proposal and contact neighbourhoods (D-122)

- **The change.** The fingerprint also hashes `@relations proposal` and `@relations contact` when they resolve to something other than their default (`VonNeumann(1)`; the lattice neighbourhood), so a checkpoint no longer loads across copy or contact neighbourhoods. Because the proposal default is `VonNeumann(1)`, the models declaring `proposal = Moore(1)` — GranerGlazier, WortelAct (both), MerksVasculogenesis, OpenVTGrowingMonolayer — and one fixture were re-pinned in six earlier frozen files under D-122 (pins only); AkeebInvasion and every model without `@relations` keep theirs.
- **Review.** Two rounds (round 1: thin lattices whose default aliases), approved. Follow-up P6.0at (named and inline relations).
- **Merge checks.** Potts, PottsModels (`-t 4`), CorePotts and the docs build exit 0. Host-only (problem build); gate and Metal not rerun.

## 2026-10-04 — P6.0t merged: integrals refresh only for readers after the sweep (D-120)

- **The change.** The integral refresh at the start of the after-MCS phases covers only integrals read after the sweep; integrals read only by the before block or the temperature stay fresh from the previous boundary, and an integral read only by `@observed` has no cell column and is computed from the saved state on query. Values seen by every reader are unchanged. 8 observed-only integrals on 128×128 went from 3.6× to ≈1.0× per warm MCS.
- **Review.** Two rounds (round 1: a discrete tick's population fold reading an integral ran one MCS behind; stored-integral order changed for some models), approved. Follow-up P6.0au (integral in drives and constraints).
- **Merge checks.** Potts, CorePotts, MakiePotts and the docs build exit 0; Potts and CorePotts on Metal exit 0; Metal gate passes (all allocs 0) — it flagged graner_glazier_72.metal 1.095 and wortel_act_100.metal 1.058, decided by `benchmark/ab.jl` (6 rounds) as noise: 0.986 and 1.005 (neither model has integrals). PottsModels (`-t 4`) first failed 5 pins of this item's frozen file that P6.0ar had moved; re-pinned to the D-122 values at merge, then exit 0.

## 2026-10-04 — P6.0as merged: `@sweep` validation and `combine` identity (D-123)

- **The change.** `@sweep` rejects a non-finite or non-real `offset`, and a `combine` whose printed form holds a compiler-generated name (anonymous functions, closures, wrappers holding them) — those fingerprinted differently in every session and could collide across sessions. Named functions, stable wrappers (`min ∘ max`) and callable structs with value fields are accepted. No fingerprint or pin changes; the CC3D `ArithmeticAverage` translation in "Coming from" now uses a named function.
- **Review.** Two rounds (round 1: the stability check tested the wrong thing), approved. Follow-up P6.0av (`mcs_duration`).
- **Merge checks.** Potts, PottsModels (`-t 4`) and the docs build. Host-only (sweep validation); gate and Metal not rerun.

## 2026-10-04 — P6.0au merged: no `integral` in drives and constraints (D-125)

- **The change.** A drive or expression constraint that reads `integral` (plain, `Pre`, inside a cell fold or `Chemotaxis` arguments) is an `ArgumentError` at build naming `integral`, the statement and the workaround: store it with `@before_mcs s ~ integral(u)` and read `s[new]`/`s[old]`. Before, a plain read failed with an unhelpful message and a folded one built and crashed at the first `solve`. Drive, constraint and variables manual pages updated.
- **Review.** Approved in round 1: no bypass (Chemotaxis `when`/field, `ifelse`, `@extend`, functional `extend`, 3D), no false rejection; the documented workaround runs as written on both algorithms. Coordinator added a sentence that a copy-scope temperature may read `integral` directly. Follow-ups P6.0aw (`@on_copy` reading an integral) and, from the P6.0at review, P6.0ax.
- **Merge checks.** Potts and the docs build exit 0. PottsModels (`-t 4`) failed one timing check, P6.0t's "observed-only integrals cost nothing" (1.854 vs 1.545 ms, limit 1.1×), with about six other Julia suites running; the file alone passes on both algorithms. Build-time check only; gate and Metal not rerun.

## 2026-10-04 — P6.0at merged: the fingerprint includes named and inline gather relations (D-124)

- **The change.** Named relations (`@relations far = Ball(2.0)`, read by `contacts(far)` or a fold) and inline gathers (`Moore(1)(42)`) reached the generated code only as run-context fields, so twin models differing in them fingerprinted alike and a checkpoint loaded across them. The fingerprint now hashes every such relation the generated code reads, resolved on the lattice; unread and observed-only relations are left out. Relations named `lattice`, `mobility` or `spacing` are refused at `mtkcompile` with CorePotts' reserved-names error.
- **Pins.** WortelAct (both variants) and the `P60ahAt` fixture moved: 9 lines in 5 frozen files on the branch, plus WortelAct in `p6_0as` and `p6_0au` at merge (D-124). No dynamics change.
- **Review.** Two rounds (round 1 approved with a reserved-name nit, fixed in round 2). Follow-up P6.0ax (an inline gather in a division `when` fails at build, pre-existing).
- **Merge checks.** Potts, PottsModels (`-t 4`) and the docs build exit 0. Build-time only; gate and Metal not rerun.

## 2026-10-04 — P6.0av merged: `@sweep mcs_duration` validation; the `@sweep` checks live in `SweepSpec` (D-126)

- **The change.** `mcs_duration` must be a real number that is finite and > 0 after conversion to Float64; NaN, ±Inf, 0, negatives, out-of-range `BigFloat`s, non-numbers and symbolic parameters are an `ArgumentError` naming it when the model is built (before: silent NaN runs, frozen or backwards time, opaque `MethodError`s). The `offset`, `combine` (D-123) and `mcs_duration` checks now run in `SweepSpec`'s inner constructor, so a hand-built spec passed to `PottsSystem(; sweep)` cannot skip them. Messages show the rejected value's type. No fingerprint changes.
- **Review.** Approved in round 1 (constructor is the only method; serialization round-trips; fields stay Float64; build-time only). Coordinator nits at merge: docstring order, type in the message. WortelAct's pins in `p6_0av` re-pinned under D-124 at merge.
- **Merge checks.** Potts and the docs build exit 0. PottsModels: the first run was suspended by a ≈3 h machine sleep and killed at the background limit; the rerun failed only P6.0t's timing check (1.075 vs 0.975 ms, limit 1.1×), which aborted the chain; P6.0t and every later acceptance file then ran separately (exit 0, 93 testsets) and Aqua passed. P6.0ay (load-robust cost check, chain collects failures) is in progress. Build-time only; gate and Metal not rerun.

## 2026-10-04 — P6.0aw merged: no `integral` in `@on_copy` updates (D-129)

- **The change.** An `integral` on either side of an `@on_copy` statement (right-hand side or a computed left-hand-side index; bare, in a fold, with `Pre`, at any scope) is an `ArgumentError` at build naming `integral`, `@on_copy`, "every accepted copy" and the `@before_mcs` workaround. Before, a folded read built and wrote the start-of-MCS value, which could enter ΔH through an energy reading the written variable. Updates, drive and variables manual pages say so.
- **Review.** Two rounds (round 1: an integral in the left-hand-side index bypassed the check). WortelAct's pins in `p6_0aw` re-pinned under D-124 at merge. Follow-up filed meanwhile: P6.0az (closure-weighted lattice neighbourhood not fingerprinted by value, from the P6.0c2 review).
- **Merge checks.** Potts, PottsModels (`-t 4`) and the docs build, run one after another: exit 0. Build-time only; gate and Metal not rerun.

## 2026-10-04 — P6.0ay merged: P6.0t's cost check is structural; the acceptance chain collects failures (D-131)

- **The change.** P6.0t's frozen "observed-only integrals cost nothing" check, which flaked at 1.1× under parallel agent load and then aborted the include chain, now compares the executed phase lists and integral columns (re-frozen) with a loose paired-timing backstop (≤ 1.5×, defect ≈ 3.6×). PottsModels' test and acceptance files now run one testset per file inside an outer testset, so a failing file no longer hides later ones; the run still exits 1.
- **Review.** Approved in round 1.

## 2026-10-04 — P6.0v2b merged: a custom frozen rule declares the leaves it reads (D-128)

- **The change.** `CorePotts.frozen_reads(sys)` (public; default `nothing`) lets a custom `remake_frozen` declare `:σ` and the cell columns it reads; a device refresh then copies only those (Metal, test fixture: 1408 B per refresh for both twins, vs 1792/3460 B undeclared). Bad or repeated names are an `ArgumentError` at `init` and every refresh. Standard rule unchanged (no gate model uses a custom rule). Audit row R4 resolved.
- **Review.** Two rounds (round 1: a repeated name crashed on Metal only).

## 2026-10-04 — P6.0b2 merged: re-declared edge variables keep their relationship; operating-point edge values seed initial links (D-127)

- **The change.** An extension that re-declares a base edge variable (to change its default) keeps the base's relationship, with `@extend` and with functional `extend`; an explicit re-scope, conflicting bases, and a change of scope are clear `ArgumentError`s at build. `:rest => 9.0` (or a parameter expression) in the operating point now seeds every initial link of its relationship instead of being silently ignored; a non-number is rejected. No generated-code or fingerprint change.
- **Review.** Two rounds (round 1: functional `extend` disagreed with `@extend` for a body built on its own).
- **Merge checks (P6.0ay, P6.0v2b, P6.0b2 together).** Merged locally one after another and checked once on the combined tree, one suite at a time: CorePotts, Potts, PottsModels and the docs build exit 0; `GROUP=GPU` on Metal under `tools/exclusive.sh` exit 0, including the P6.0v2b Metal testsets. Standard frozen-rule path unchanged, so no gate run.

## 2026-10-04 — P6.0c2 merged: canonical solver strings, session-bound closures, reserved suffixes (D-130)

- **The change.** A solver value nested deeper than the canonical printer's cap, or cyclic, is an `ArgumentError` instead of a silent truncation (two different `Adaptive` solvers used to share a group and a fingerprint, dropping the second). Closures in `Adaptive` keywords stay allowed (SciML idiom; coordinator decision) and make the fingerprint session-bound: on base, three processes with different closures shared one fingerprint and a checkpoint resumed across them. Reserved suffixes are checked on vector, `@observed` and component observed names. New `tools/fingerprint_compare.jl` (D-078 merge check). AUTHORING §6 and INTERNALS §1.6 state the after-MCS phase order.
- **Review.** Approved in round 1, with nits applied before merge. Re-frozen once before implementation (rule 2 changed from rejecting closures to session-binding them).
- **Merge checks.** Potts, PottsModels (`-t 4`) and the docs build, one at a time: exit 0. `tools/fingerprint_compare.jl` against the pre-merge `HEAD`: all 10 fingerprints agree. Build-time only; gate and Metal not rerun.

## 2026-10-04 — P6.0u merged: remaining `@components` gaps (D-133)

- **The change.** MTK `tstops`/`assertions` on a component are rejected instead of ignored; every rejected component binding names the component and the bound name, including a bound parameter the model reads as `comp.x`; an error inside a hand-written `@extend` base propagates as the base raised it; `frozen_varies(sys) = false` silences `init`'s static-mask warning; the temperature's `integral(Pre)` error says "in @sweep".
- **Review.** Two rounds (round 1: a model read of a let-through bound parameter still gave the old message). Two pre-existing component limitations noted in D-133, not filed (D-134).
- **Merge checks.** CorePotts, Potts, PottsModels (`-t 4`) and the docs build, one at a time: exit 0. Build-time only (the CorePotts change is an `init` warning guard); gate and Metal not rerun.

## 2026-10-04 — P6.0ax merged: inline gathers outside the copy step are numbered (D-132)

- **The change.** Every inline gather the compiler lowers is numbered, including those in division `when`s and rules, link `when`s, edge energies and `@on_copy` update indices (they used to fail at build with `KeyError`). One `scanned` list drives both tracker flags and numbering; the footprint scans on-copy indices (a named relation read there now reports its full reach). Models that built before keep their fingerprints; `@observed` gathers are not fingerprinted.
- **Review.** Two rounds (round 1: the on-copy index was not scanned; D-132 overstated `@observed` fingerprint stability — the shared build counter is folded into P6.0z).
- **Merge checks.** Potts, PottsModels (`-t 4`, 13278 pass, 37 broken) and the docs build, one at a time: exit 0. Build-time only; gate and Metal not rerun.

## 2026-10-04 — P6.0g merged: kind classes (D-135)

- **The change.** `@kinds medium tip stalk endothelial = (tip, stalk)` declares a kind class; `x ∈ g` / `x ∉ g` lower to a constant `==` chain in every gate, and `cells(g)` and `Chemotaxis(kinds = …)` take classes. Members are resolved when the macro expands; `kind == g` is an error pointing to `∈`; `extend` merges classes; operating points and layouts reject class names. Programmatic `kind_classes` are validated at construction. Published models' generated code and fingerprints are unchanged.
- **Review.** Two rounds (round 1: `kind == g` silently constant; members unchecked at expansion; layouts partly ignored class names).
- **Merge checks.** Potts, PottsModels (`-t 4`, 13617 pass, 38 broken) and the docs build, one at a time: exit 0. `GROUP=GPU POTTS_GPU=metal` under `tools/exclusive.sh`: exit 0. Gate with Metal: pass (CPU within tolerance; Metal GG/Wortel/Merks flagged). `benchmark/ab.jl` on all five Metal cases against 03db26ed: Akeeb 1.010, Merks 1.026, OpenVT 1.010, Wortel 0.965; GG 1.052 in 4 rounds, rerun with 8 rounds 1.011 (generated kernels are byte-identical, so treated as power-state noise).

## 2026-10-04 — P6.0o merged: `PottsSystem <: AbstractSystem` (D-137)

- **The change.** `PottsSystem` is a `ModelingToolkitBase.AbstractSystem` with MTK's `System` fields mirrored; `equations`, `unknowns`, `parameters`, `observed`, `nameof`, metadata, `toggle_namespacing`, `independent_variables` and `sys.x` work as in MTK. `sys.x` is strict (a non-symbol name is an `ArgumentError` naming its category); keys namespaced by the model's own name resolve at every key site, others are rejected. `complete` is exported and Potts-owned; `@set` on a mirror field maps to the Potts field; `extend` keeps the newest metadata. `compose`, `ODEProblem`, `JumpProblem` and `extend` with a plain `System` are clear errors (`compose(sys, [x])` used to recurse forever). 378 internal property reads now use `getfield`; public `Potts.lattice`. New direct dependencies JumpProcesses and ConstructionBase (both already loaded by MTKBase). Generated code and fingerprints unchanged (25 pins). Seven frozen files re-frozen under D-137 (property reads → `getfield`/accessors only).
- **Review.** Three rounds (round 1: namespaced keys inconsistent per site; `complete` not exported; `@set` on mirrors a no-op; stale metadata on `extend`. Round 2: foreign-namespaced keys leaked through `getp`, `prob.ps`, `solvers` and expressions).
- **Maintainer.** D-137 rule 8: the absolute D-047 figure is reported, not gated — the maintainer, on the 14.69 s baseline: "14.69 s is fine" (2026-10-04).
- **Merge checks.** Potts, PottsModels (`-t 4`), MakiePotts and the docs build, one at a time: exit 0 (first attempt failed to load Potts until the workspace Manifest was re-resolved for the new dependencies). `GROUP=GPU POTTS_GPU=metal`: exit 0. Gate with Metal: pass (Wortel, Merks Metal flagged). `benchmark/ab.jl`, 8 rounds against 8be0df58: Akeeb 1.007, Merks 0.979, Wortel 0.985, GG 0.975, OpenVT 0.976. Latency (`benchmark/p6_0o_latency.jl 5 10`, paired against 8be0df58): time to first MCS 0.988–1.004, cold construct/mtkcompile/problem ≤ 1.035; Akeeb Float32 first MCS 14.32 s (base 14.4 s). Warm medians for Merks and OpenVT construct/mtkcompile read 1.10–1.17; a paired minimum-time micro-benchmark (BenchmarkTools, two alternations) gives 0.98–1.04 for all three tested models, so treated as GC noise.

## 2026-10-05 — P6.1d: reproduction 09 FULL run (no code change; page frozen, D-072)

- **Run.** Commit 8eb9d210, Julia 1.12.6, 6 threads, `POTTS_FULL_REPRODUCTION=true`, base seed 1, 10 replicates each from `graner_glazier_aggregate(1000; seed = i, margin = 10)` on 247 × 247 periodic. Executed with `Literate.markdown(…; execute = true)` on the page alone; wall time 3 h 6 min (11 166 s, 2026-10-04 23:22 → 2026-10-05 02:29) on a heavily loaded machine (load average up to 59). Outputs (executed page, replicate-1 video, log) kept outside the repo in `PottsWorktrees/p6-1d-out/`; the page writes nothing to `data/09/`, which stays pending.
- **Verdict (n = 10, nominal times).** Every FULL and SMOKE+FULL row passes except one:
  - V-PRE1 fractions at 10/100/10³/10⁴ (heterotypic 0.372, 0.250, 0.133, 0.073; dark–dark 0.318, 0.382, 0.444, 0.474; light–light 0.250, 0.308, 0.363, 0.394): all PASS. Log law 5–4000: R² 0.991, slope −0.114 per decade: PASS.
  - V-PRE2 (homotypic > heterotypic at every save; dd crossing 25, ll crossing 64, dd first; NC1 no crossing): PASS.
  - V-PRE3 (a) dark–medium < 0.003 by 320: PASS; NC1 0.03: PASS. (c) size-free plateau R = 1.013: PASS. (d) raw 0.06: PASS.
  - **V-PRE3 (b) light–medium plateau reached before 10³: FAIL** — our plateau is reached at 3200 paper MCS (within 5 % of the 20 000 value; last-decade slope −0.003 per decade), against ≈ 200 (PRE) / ≈ 300 (PRL). Also FAIL at the informational time scale s = 1. The plateau level itself matches (rows (c), (d)).
  - V-PRE4 drop D 0.021 ± 0.003 in [0.005, 0.03]; flat over [10³, 10⁴] (−27.5 bonds/decade ≤ 181): PASS. Start check: D = 0.02 from Voronoi starts and 0.02 from relaxed copies (replicates 1–3).
  - V-PRE5 dark clusters 20.3 → 12.2 → 5.1 → 1.8, largest 0.905 at 10⁴: PASS.
  - V-PRE13 partial sorting (dark–medium 0.023; heterotypic 0.322, 0.228, 0.153): PASS.
  - V-GG6 Δa = −2.861 ± 0.061 SE, NC1 0.073: PASS. NC1 symmetric contacts (share 0.497, dark–medium 0.03, 0 engulfed): PASS.
  - Periodic-boundary variant (494 × 494, 9 Bonferroni comparisons at 5 %): all within, PASS.
- **Next.** Send the table to the spec owner (spec 09 §9.1) for the V-PRE3 (b) failure: the slow light–medium approach may come from the unrelaxed Voronoi start (cell-area SD 6.9 vs 1.8 relaxed) or the aggregate shape, not the dynamics. No change to the frozen page without a DECISIONS entry (D-072).

## 2026-10-05 — P6.1b merged: `Potts.boundary_lengths` and `Potts.anneal` (D-139)

- **The change.** Two public (not exported) analysis functions next to `total_energy`: `boundary_lengths(prob, u; relation)` splits the boundary by kind pair (each bond once, relation weights, periodic wrap, domains; Σ J·L == `total_energy` for a contact-only model), and `anneal(prob, u; mcs, seed, alg)` returns a copy relaxed at copy temperature 0 with the run's own ΔH (drives included), refreshing integrals and energy snapshots before each MCS and running nothing else. No CorePotts or kernel change. New manual page `manual/analysis.md`; HexSorting sibling. The frozen 09 page keeps its own helpers (D-072; switch later under its own entry).
- **Review.** Two rounds (round 1: frozen population-fold snapshots and integrals; a failed run returned silently; docs overclaimed a lower energy).
- **Merge checks.** Potts, PottsModels (`-t 4`), MakiePotts and the docs build, one at a time: exit 0. CPU gate: pass (GG sequential 1.022, others 0.968–1.017; 0 allocations). No device code touched; Metal not rerun.

## 2026-10-05 — P6.1a5 merged: core `Voronoi`, shapes, `RandomPoints`, clipping, `layer_rng` (D-138)

- **The change.** `VoronoiBall` (PottsModels) is replaced by the core `Voronoi(points; region, lloyd, kinds, splits)` (medium-only fill, minimum-image nearest generator, Lloyd, D-063 repair), with `RandomPoints`, `Center()`, public `Potts.points`, and the GeometryBasics shapes `HyperSphere`/`Circle`/`Sphere`/`Point` (exported; closed membership with a relative rounding tolerance, wrapping on periodic axes). Every layout report row gains `clipped`. Public `Potts.layer_rng`; Akeeb clocks use it; StableRNGs leaves PottsModels. `graner_glazier_aggregate` and the Akeeb clocks are byte-identical (44 Voronoi pins, 8 aggregate pins). GeometryBasics is imported last in Potts (its `OffsetInteger` converts invalidate the symbolic stack otherwise: `using Potts` +29 % → +4 %).
- **Review.** Two rounds (round 1: hex discs lopsided at exact lattice distances; load-order invalidations failing P6.0o's +5 % bound; hex tie wording). Final paired time to first MCS ×1.013–1.034 against 8eb9d210.
- **Merge checks.** Potts, PottsModels (`-t 4`, 14 629 pass, 38 broken), MakiePotts and the docs build, one at a time: exit 0. CPU gate: pass (GG sequential 1.040, others 0.971–1.016; the base measured GG sequential 1.034 in the P6.1b review, so drift). Host-only change; Metal not rerun.
- **Open.** Spec sketches 09 and 11 still name `VoronoiBall` (peer session's files).

## 2026-10-05 — P6.3c merged: `Eden`, `Splits`, `RandomPoints(replace = true)`, `shortfall` (D-141)

- **The change.** `Eden` (TST GrowInCells, frontier-based, draw stream identical to the full-scan rule), the host routine `Splits` (TST DivideCells geometry, on-plane sites stay with the mother up to a relative 1e-9, one-piece warnings issued by `layout` with final ids), `RandomPoints(replace = true)`, and `shortfall = :error | :warn | :allow` on Eden and Splits; a HexSorting sibling is the first `:allow` consumer in code. LinearAlgebra (stdlib, already loaded transitively) is a new direct Potts dependency. Spec 01 §7.6 bands reproduced (de novo 357–360 cells ≈ 47.6 px; sprout 1 816–2 439 px).
- **Review.** Two rounds (round 1: on-plane sites in Float64; paint-time ids in warnings). Follow-up folded into P6.3d: a Splits cell repaired by a later layer still warns.
- **Merge checks.** First attempt failed to load Potts until the workspace Manifest was re-resolved for LinearAlgebra (the merge script now resolves first). Potts, PottsModels (`-t 4`, 15 258 pass, 38 broken), MakiePotts and the docs build, one at a time: exit 0. CPU gate: pass (GG sequential 1.018, others 0.968–1.003). Host-only change; Metal not rerun.

## 2026-10-05 — P6.3a merged: shell topology, soft E₀, `Global()`, `track = (:ΔH,)` (D-140)

- **The change.** Shell topology for the lattice relations, a soft E₀, the `Global()` scope, and an opt-in `track = (:ΔH,)` that records per-proposal ΔH. The track lives in the checkerboard buffers `(; track, dH, acc)` and is a `sequential_mcs!` argument, not part of `DeviceFunctions`. Untracked runs use the unchanged base kernels; tracked runs use separate kernels (76e98133).
- **Review.** Three rounds. The first merge check read Merks Metal A/B at 1.098. The implementer could not reproduce it (1.024, identical device LLVM) but split the track kernels anyway, and round 3 approved.
- **Merge checks.** These ran one at a time on the staged tree and all exited 0: CorePotts (9 021 pass), Potts, PottsModels (`-t 4`, 15 911 pass, 39 broken), MakiePotts, the docs build, CorePotts Metal and Potts Metal. CPU gate: pass, with GG sequential at 1.034 (the known tight baseline, D-140 drift note) and the others 0.990–1.028.
- **Metal.** The gate's Metal rows were measured while other jobs were running (1.8–6.2×), so the A/B decides. Metal A/B, 8 rounds against 9016f53b: GG 0.974, Wortel 1.000, Merks 0.989, OpenVT 0.991, Akeeb 0.901. All pass.
- **Caveat.** P6.2b found that `ab.jl` shows 5–16% offsets between two checkouts of the same commit on Akeeb Metal. The Merks 1.098 reading was probably this artefact. The follow-up is P6.0bb.

## 2026-10-05 — P6.1f staged: reproduction 09 margin 60 and an isolation guard (D-144); FULL rerun pending

- **The change.** This applies the peer spec-owner's ruling on P6.1d's V-PRE3 (b) failure. The cause is the fixture: with margin 10, aggregates touch their own periodic image after ≈ 3000 paper MCS. On 494², the frozen rule gives t_p = 200, a PASS. The 09 page now uses `MARGIN = 60` (347²) and has a FULL isolation-guard row. Spec 09 §9.4 is new, and the 09 and 11 sketches are updated. No target, tolerance, n or run length changed. The 09 page is re-frozen under D-144.
- **Merge checks.** `frozen.jl` 204/204; the docs build exits 0, and the reduced 09 page renders the guard row.
- **Record.** P6.1d stays on record as a FAIL of V-PRE3 (b) with this cause. The P6.1f FULL rerun replaces it.

## 2026-10-05 — P6.2b merged: Akeeb μ = 24 default, `akeeb_observables` (D-142, D-143)

- **The change.**
  - The default μ moves from 30 to 24 (D-142), and the docstrings now state the paper-vs-code items P14 and the time mapping P12.
  - `akeeb_observables(σ, kinds)` and `akeeb_observables(u)` compute O1–O8 by composing existing Analysis primitives.
  - The Akeeb docs page runs 701 MCS (the authors' MCS 700) and shows the observables beside the P1 reference. Every one of the six reads within one SD.
- **Review.** Two rounds. Round 1 found the page stopping one MCS short of the paper's endpoint, the missing observables table, and the kinds check reading ids that own no site. In round 2 the coordinator fixed the plot axis nit.
- **Merge checks.** These ran one at a time and all exited 0: `frozen.jl` (210), Potts, PottsModels (`-t 4`, 16 251 pass, 42 broken) and the docs build. No solver or device code changed, so Metal was not rerun.
- **Gate.** Gate metal passed on the implementer's run. The baseline was not re-set. Measured in one process, alternating μ 30 and 24, the change costs ≈ 1%. The `ab.jl` reading of 1.24 was mostly a per-checkout artefact (P6.0bb).

## 2026-10-05 — P6.15a merged: OpenVT monolayer benchmark track (D-147); full-run outputs rule (D-146)

- **Spec.** Spec 15 v3 was written by the peer session "Potts.jl models and publications" and verified by the coordinator's spec verifier. The verifier re-derived the spring–dashpot reference to 5e-13, and found that `metrics.cpp` reproduces its own output byte for byte only with `-ffp-contract=off` (D11). It also corrected CC3D's J, the V4 shape target and the Artistoo replicate counts, and added item A3.
- **Plan.** ROADMAP Step 3b, P6.15b–j. The P6.15b (calibration) and P6.15d (analysis port) test authors are running.
- **D-146.** Full reproduction runs are offline, and their verdicts, per-save TSVs and provenance are committed under `reproductions/data/NN/`. Videos go to release assets.
- **Merge checks.** Docs only: `frozen.jl` passes.

## 2026-10-05 — P6.15b merged: OpenVT chain calibration (F2 / Table S5, D-148)

- **The change.**
  - In `Analysis`: `centroids(σ; periodic)`, plus `chain_centroids`, `chain_width`, `crossing_time` and `relaxation_mse`.
  - Exported from PottsModels: `OpenVTChain`, `openvt_chain(11 | 21)`, `openvt_release` (a `DiscreteCallback` that switches A*) and `spring_dashpot_width` (an exact eigenmode solution; no new dependency).
  - Nothing in core changed.
  - `p6_0v1_device_lifecycle.jl` is re-frozen under D-148, gaining one `:OpenVTChain` builder.
  - A new `ScheduledRelease` sibling covers generality.
- **FULL tier (implementer's run, 14.5 s).** Every V6–V8 row passes:
  - T = 297, 156, 111 and 77 MCS for λ = 1, 2, 3 and 5, against Table S5's 290, 155, 110 and 75;
  - at λ = 2 the MSE is 0.38× Table S5;
  - the 21-chain predictions without refitting fall inside the consortium spread.
- **Review.** One round, APPROVE; the coordinator fixed three nits.
- **Merge checks** (one at a time, all exit 0):
  - `frozen.jl`;
  - the frozen calibration test with `OPENVT_MONOLAYER_REPO` set;
  - PottsModels (`-t 4`): 16 457 pass, 44 broken;
  - the docs build.

  No core or device change, so no gate run.

## 2026-10-05 — P6.1f: reproduction 09 FULL rerun at margin 60 (D-144); the record moves to it

- **Run.** Commit 0eb1ea72 on an otherwise busy machine, 10 replicates on 347², 6 threads, 5052 s. The D-146 outputs are committed under `lib/PottsModels/reproductions/data/09/full-2026-10-05/`: verdicts, per-save time series, clusters, page metadata, provenance and the wrapper.
- **Verdicts.**
  - The isolation guard is clear at every save of all 10 replicates.
  - **V-PRE3 (b) now passes** (t_p = 320; P6.1d's FAIL was the fixture, as D-144 found).
  - Every other binding row passes except **V-PRE5 "one dark cluster @ 10⁴": the largest fraction is 0.815 against ≥ 0.90.** Per replicate it is 0.99, 0.76, 0.64, 1, 1, 0.90, 0.75, 0.51, 1, 0.60, and three replicates have one cluster. P6.1d read 0.905.
  - The coordinator's reading, unconfirmed: at margin 10, dark clusters that touched across the periodic image were probably counted as one, which inflated P6.1d's value.
  - V-PRE5 is a pre-registered target and is not changed here. The table goes to the spec owner, as P6.1d's did.
- **Other rows moved by ≤ 0.006.** V-PRE1 heterotypic @ 10⁴ is 0.068 (was 0.073), and the cluster count @ 10⁴ is 2.2 (was 1.8).

## 2026-10-05 — P6.15b data: the F2 / Table S5 calibration FULL record (D-148, D-146)

- **Run.** Commit 30c39601, 4 threads, 13.9 s wall time (11.2 s of simulation). The D-146 outputs are committed under `lib/PottsModels/reproductions/data/15/calibration-2026-10-05/`: verdicts, the per-MCS 11- and 21-chain time series (mean and SD, from the burn-in at t = −100), per-run crossings, the spring–dashpot reference, metadata, provenance, the runner, and a Fig 2b/2d/2e-layout PNG (Potts only; no G data).
- **The runner is the frozen FULL tier.** It uses the test's seeds, run lengths, algorithm, observables and bands through the public API, and also saves the burn-in. Checks:
  - all five width matrices (t ≥ 0) are bitwise identical to the test's own `p615b_runs`;
  - the frozen test with `POTTS_FULL_REPRODUCTION=true` passes (213 pass, 2 G rows skipped).
- **Verdicts.** Every V6–V8 row passes, and the numbers equal the implementer's run.
  - V6: T = 297, 156, 111 and 77 MCS.
  - V7: MSE/S5 = 1.69, 0.38, 0.92 and 0.76. At λ = 2, w₁₁(0.5T) = 7.859 and w₁₁(2T) = 9.794.
  - V8: w₂₁ = 15.96, 19.28 and 19.89 at 1, 5 and 10 T. The inner w₁₁ = 7.24, 9.51 and 9.93. The plateau ends at 0.173 T.
  - w₂₁(10T) = 19.889 is 0.011 below the lattice spread but inside the ± 0.15 band.
- **Reported.** The per-run crossing SD is 33, 14, 9 and 5 MCS for λ = 1, 2, 3 and 5. The cycle 5·T(2) is 780 MCS, against M's 775.

## 2026-10-05 — P6.1g filed: V-PRE5 kept as frozen, late coarsening an open deviation (D-151); spec 10 P9 SD 2888 (D-152)

- **V-PRE5.** The peer spec-owner ruled that the one-cluster clause stays as frozen and P6.1f's FAIL stands.
  - The coordinator's periodic-image reading was wrong: F_dM is 0 from ≈ 320, so no dark–dark bond crosses the seam. P6.1d's 0.905 and P6.1f's 0.815 differ by ≈ 1 SE.
  - Diagnostic: 6 seeds from both the Voronoi and the relaxed starts, run to 2×10⁴. The mean largest share is 0.72–0.81 at every reading time, and several replicates arrest with two or three domains.
  - Both published runs coarsen faster than almost all of our 22 replicates after 10³ (p ≈ 0.004).
  - The page gains, as text only, an open-deviation row and an author question. P6.1g is the follow-up, and the question goes to the phase report (§7.5).
- **Spec 10 P9.** The infiltrative-area SD is 2888, not 2889. The frozen Akeeb test constant is corrected and the file re-frozen.
- **Checks.**
  - `frozen.jl`: 213.
  - Reproduction 10 test: SMOKE passes, and with `POTTS_REFERENCES` set the reference rows pass 208/208.
  - Docs build: exit 0.

## 2026-10-05 — P6.15d merged: OpenVT analysis port (D-149)

- **The change.**
  - `Analysis.concave_hull`: the Graham scan of `metrics.cpp` followed by concaveman, with uniform-grid candidate filtering.
  - The `openvt_*` metrics, the neighbour histogram, the A3 inhibition codes and fractions, and `write_openvt`/`read_openvt`/`openvt_filename` for O1–O6, all in `src/benchmarks/`.
  - `Printf` is a new stdlib dependency.
- **Fidelity.**
  - The 25 frozen parameter-plane rows match `metrics.cpp -ffp-contract=off` byte for byte.
  - 53 of 54 real consortium frames match. The other, a TST frame, is D13: the reference's R-tree pruning error.
  - Fuzzing found no other mismatches outside exact ties.
  - Spec 15 records two deliberate departures, D12 (an exact, strict Graham order) and D13 (unpruned search).
- **Speed.** A 10⁴-centroid hull takes 6–27 ms, and 10⁴ lattice points take 45 ms.
- **Review.** Two rounds.
  - Round 1 found D12 and D13 on real data.
  - In round 2 the coordinator added an underflow-safe bound, an exact integer fast path and a timing note.
- **Merge checks** (one at a time, all exit 0):
  - P6.15d acceptance with the repo set: 186/186.
  - P6.15b calibration: 240/240.
  - PottsModels (`-t 4`): 16 648 pass, 46 broken.
  - Docs build.
  - `frozen.jl`: 216.

## 2026-10-06 — P6.3b merged: `@boundary` faces and site masks, `@schedule` (D-145)

- **The change.**
  - `@boundary` takes `Dirichlet`/`NoFlux` face pairs per axis, plus site-mask clamps applied in every substep and on a fresh initial state.
  - `@schedule` sets the phase order. The sweep and the lifecycle are entries of the static MCS tuple, and `step!` is one `Base.afoldl` over it.
  - D-035 is amended: a host pass costs one round trip per firing, and a model with no host pass pays nothing.
- **Review.** Two rounds.
  - Round 1:
    - integral refreshes follow one rule on the placed order (S1, S2 and S4 regression tests);
    - clamps run on fresh states only, so checkpoint resume is exact;
    - a mask that reads its own field is an error, as is a face on a field with no `Δ`;
    - faces apply in every `Δ`;
    - `default_order` stays internal.
  - Round 2: no recursion over the tuple and no non-leaf `@inline`; `sum` and `foldl` allocated, `afoldl` does not.
- **Merge checks** (one at a time, all exit 0):
  - CorePotts suite; `frozen.jl`: 219; Potts suite; PottsModels (`-t 4`): 16 961 pass, 47 broken; docs build; Metal GPU suite.
  - Gate: two runs, pass, every ratio within 0.969–1.020.
  - Metal A/B: the type-cache-seeded ratios are at most 1.010, with same-commit controls (D-145 Applied).
- **Filed.** P6.0bc: cache compiled HostKernels.

## 2026-10-06 — Cold construction: compile workloads for every published model (D-047)

- **The change.** PottsModels precompiles every constructor, plus the first problem and MCS of the published models; Potts precompiles a `@potts_model` model through to its first MCS. PrecompileTools is a new PottsModels dependency.
- **Effect.** Time to first MCS from a fresh process falls from 9.0–13.5 s to 5.8–5.9 s. About 4.9 s of that is package load, now the only real cost.
- **Merge checks** (one at a time, all exit 0): `frozen.jl`; Potts suite; PottsModels (`-t 4`): 16 961 pass, 47 broken; docs build; latency against ca3b24c3.

## 2026-10-06 — P6.15c merged: OpenVT Table S1 model, contact fold, `randn`, per-daughter draws (D-150)

- **The change.**
  - In CorePotts: `ContactCount`/`ContactCounts` and `commit_contact_count!`.
  - In the DSL: the cell-scope fold `count(pred for _ in contacts[(rel)])`, `randn()` / `randn(μ, σ; lower)`, and per-daughter evaluation of drawing division rules.
  - In PottsModels: `OpenVTReferenceMonolayer`, `openvt_reference_state`, `openvt_snapshot`, `stop_at_cells`, `edge_guard` and `Analysis.near_edge`.
  - The reference model joins the compile workload (D-047). `OpenVTGrowingMonolayer` is unchanged.
- **Merge with P6.3b.** The two touched the same lines in `CorePotts.jl` (`public`: `normal`/`bounded_normal` beside `GhostFace`), `src/macro.jl` (the boundaries/schedule keywords plus `metadata`), the Analysis exports and the PottsModels imports. All were resolved by keeping both sides.
- **Merge checks on this Mac** (one at a time, all exit 0 unless noted):
  - CorePotts suite; `frozen.jl`; Potts suite; PottsModels (`-t 4`): 17 217 pass, 48 broken; MakiePotts; docs build; Metal GPU suite.
  - The O2 `write_openvt`/`read_openvt` round trip now runs, since P6.15d is merged.
  - Gate: new case `openvt_reference_100`, baseline set from this tree at sequential 19.55, checkerboard 19.20 and Metal 72.03 ns/site. The implementer measured 20.12, 19.60 and 72.08.
  - The gate flagged Akeeb CPU against the stored baseline in both runs. The paired base read +3.0% sequential and +1.1% checkerboard; the base itself read 1.041 against the stored checkerboard value (drift). Akeeb's generated code is identical before and after the merge (diff with line comments stripped).
  - Seeded Metal A/B (candidate / same-commit control): GG 1.001 / 1.011, Merks 0.998 / 1.005, Wortel 1.002 / 0.996, Akeeb 0.997 / 1.000. The OpenVT pair was not run: Metal verification is deferred until all paper models are done (D-157).
- **Checks on the PC** (`praneeth-NucBox-EVO-X2`, Ryzen AI Max+ 395, CPU; D-156/D-157):
  - Akeeb CPU A/B, paired and pinned to one logical CPU on a reserved core (`taskset -c 12`): sequential 1.001, with a same-commit control of 1.001. Each round reads 38.2–39.4 ns/site.
  - Unpinned under a load of 25: sequential 1.006 and checkerboard 1.005. The unpinned control read 1.729, because SMT sharing makes timings bimodal (≈ 40 vs ≈ 71 ns/site); this is why the core pinning was adopted.
  - So the Mac gate's Akeeb flag was drift.
  - Latency (`p6_0o_latency.jl 5 10` against 82e240ba): to_first_mcs 1.004–1.028 on every case.
  - `problem` reads 1.07–1.11 on GG, Wortel, Merks and OpenVT, which is +4–9 ms on a 44–90 ms step (contact-count relation wrapping and initial-state work at construction). Accepted: time to first MCS is unchanged.