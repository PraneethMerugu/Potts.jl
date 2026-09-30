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
