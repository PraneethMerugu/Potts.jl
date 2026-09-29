# Adjudication of legacy design/spec findings

Sources: four scans of `Potts.jl/design`, `Potts.jl/spec`, `CorePotts.jl/spec`,
`LocalMath.jl/spec` (2026-09-29), about 180 findings with heavy overlap, deduplicated below.
Filters: **D-029** (performance over exactness), **D-030** (Julia-only), and "adopt the
best high-level features". Verdicts: **FIX** (a bug in our design), **ADOPT**, **ADOPT-LITE**
(the high-level feature without the costly guarantee), **DEFER** (later milestone),
**REJECT** (with reason).

## 1. Bugs in our design (FIX, applied to INTERNALS.md now)

| # | Finding | Fix |
|---|---|---|
| F1 | RNG key `seed ⊕ replica ⊕ repeat` collides (seed 1, replica 2) with (seed 2, replica 1) | key = Philox-hash of the tagged tuple `(seed::UInt64, replica::UInt32, repeat::UInt32)` |
| F2 | cell-addressed draws lack the generation, so a reused id replays a dead cell's randomness | entity field packs `(id, generation)`; generation wraps at 2⁸, which is acceptable per D-029 |
| F3 | 8-bit codegen-assigned streams renumber when the model is edited and cap at 256 | stream = 32-bit hash of a namespaced operation key; collisions are rejected at compile time; built-ins (direction, acceptance, priority, color order, init) are reserved |
| F4 | checkerboard claims only `{old, new}`, but ΔH may read other cells (linked partners, a neighbor cell's orientation, contacts whose energy depends on cell quantities) | footprint analysis produces a per-proposal **claim set**: `{old, new}` plus every cell whose quantities ΔH or `commit!` read. Combinations that cannot be bounded are **rejected at init** for checkerboard |
| F5 | stride ignores the write footprint (`@on_copy` writes to neighbors) | `s ≥ r_read + r_write + 1`; the remainder color class is the rule for indivisible periodic axes, not "next divisor" |
| F6 | "claim both cells" would serialize every medium copy | medium (id 0) and obstacle domains are never claimed (FusedCPM already does this) |
| F7 | NaN/Inf ΔH is silently rejected forever | `!isfinite(ΔH)` sets a status bit; the solve ends with `ReturnCode.Failure`, naming the term (a single compare) |
| F8 | `attempts_per_site` silently redefines the MCS | **1 MCS = N copy attempts**, always, where N = mutable sites. `attempts_per_site` is removed; "16 attempts per site" in a paper means 16 MCS |
| F9 | the scalar type depends on the backend, so one model changes precision silently | one default, **Float32** on every backend. A model or solve may declare Float64; a backend never narrows it (it errors instead) |
| F10 | hidden default `volume > 1` constraint breaks conventional CPM | extinction is a per-kind option, `extinction = :retire` (default, conventional) or `:forbid` |
| F11 | host capacity growth inside the MCS loop needs a sync | capacity is preallocated (`max_cells`, default 2 × initial + 64). Exhaustion **defers** that MCS's creations (the cell stays eligible) and counts it in `stats`; the host grows capacity at the next sync point |
| F12 | `sol(t)` interpolation for a discrete process | `sol(t)` is an exact lookup at saved MCS; unsaved time is an error |
| F13 | the ΔH self-check used exact equality | `≈` with a tolerance scaled to the magnitude of H |

## 2. Semantics to state (ADOPT; free, and documented in INTERNALS/AUTHORING)

- Closed boundary: an out-of-domain direction is a counted null attempt, not renormalized, and no contact or surface edge exists across it.
- N counts mutable sites; obstacles and walls are neither recipients nor donors.
- Separate relation roles: `proposal`, `contact`, `surface`, `connectivity`, plus named query relations. The default proposal relation is the first shell (4 in 2D, 6 in 3D). Widening the contact relation never widens the proposal relation. Relations that alias under a small periodic axis are rejected.
- Canonical direction order: by squared distance, then lexicographic, so a direction draw is well defined.
- Bounded integer draws use Lemire multiply-shift (bias ≤ n/2³², D-029). Uniforms are grid midpoints in (0,1).
- Neighborhood names: `NeighborOrder(k)` = CompuCell3D's cumulative first-k-distance-shells; `Moore(k)` = Chebyshev ≤ k; `VonNeumann(k)` = Manhattan ≤ k; `Ball(r)`; `Stencil`. `Shell(k)` is removed. Self is excluded unless `include_self = true`.
- Surface = number of surface-relation edges with exactly one endpoint in the cell. A cell–cell edge counts for both cells; closed-boundary edges don't exist. Integer accumulation.
- Contact: `J` symmetric, finite; distinct cells of the same kind use `J[k,k]`; out-of-domain neighbors contribute nothing.
- Periodic moments are tracked unwrapped and incrementally, with minimum-image ties at half a box resolved to +.
- `@on_copy` effects read the pre-commit state and publish after the ownership commit. Rejected, same-owner and lost proposals change nothing.
- Drives: `@drive copy => e` is energy-like (divided by T); `@bias copy => b` adds directly to log α. Neither appears in `total_energy` or the ΔH self-check.
- Symbolic summation and CSE change floating-point rounding relative to source order. This is accepted (D-029).
- Ensemble: replica = `sim_id`, one master seed, `prob_func` runs before the seed injection. Default seed = 0.
- Counter overflow (MCS > 2³²) is an init-time error for the requested `tspan`.
- Integrator parameter changes via `setp` take effect at the next MCS. `remake` is the problem-level path.

## 3. Features adopted into the roadmap

| Area | Adopt | Milestone |
|---|---|---|
| Acceptance | pluggable acceptance law: `Metropolis()` (default), `Barker()`, `MetropolisHastings()` (proposal-ratio correction for equilibrium sampling), CompuCell3D-style `offset`/`yield` options; named T=0 rule | M2.1 |
| Proposals | bound `direction` in proposal scope; custom proposal distributions (`Proposal(...)` law: boundary-copy for foam shear, swap moves) as an extension point | M2.1 / M2.6 |
| Media & domains | multiple media kinds with their own properties; obstacles (no id, immutable) distinct from frozen finite cells; site-kind conversion (degradable ECM → medium) | M2.1 / M2.3 |
| State | vector/tensor/Bool/Int state types (`SVector` polarity); site ownership-change policy (`:preserve`, `:reset => v`, `:copy_from_source`); `extensive = true` variables default to `Split()` at division, others to `Copy()` | M2.3 |
| Aggregates | user-authored maintained aggregates `aggregate(expr; over = sites, by = owner)` with incremental maintenance, including over fields updated outside copies; distinct-neighbor-cell queries vs contact-weighted queries; empty-set policies | M2.2 / M2.7 |
| Fields | field grids independent of the lattice (nearest/multilinear/conservative maps); per-field, per-face BCs (periodic, no-flux, Dirichlet, Robin); CFL-derived automatic substeps (explicit fixed substeps error if unstable); Lie/Strang split options; steady-state solve; extensive vs intensive fields; secretion/uptake with Michaelis–Menten and conservative field↔cell transfer | M2.4 |
| Chemotaxis | library laws `Linear`, `Saturating`, `MichaelisMenten`, `LogScaled` × responder modes `Extension`, `Retraction`, `Reciprocal`, `Interface(filter)` | M2.5 |
| Mechanics | fluctuating OU volume pressure / surface tension as cell-scoped SDE state (exact OU update per MCS, not per color) | M2.5 |
| Lifecycle | per-rule `priority`; statically overlapping equal-priority rules rejected at build; `FilterInadmissible`/error policy; division: side choice, minor/major axis, explicit plane point, parent/daughter kind maps, daughter nonempty + connected check; id reuse lowest-first from t+1; `RemoveCell` (sites → a medium); `SeedAt`/`SeedStencil`; relationship consequences (`RemoveIncident`, `RejectWhileLinked`); `DepositTo(field)` on retire | M2.8 |
| Relationships | directed edges, anchors to fixed points, payload retune, link age, max degree, endpoint division/retire policies; link creation requested inside `@on_copy`, applied at the end of the color (focal adhesion) | M2.9 |
| Schedule | user-declared named phases before/after the sweep with explicit order; staged protocols (`@protocol` stages by MCS range), piecewise scheduled parameters, `Every(n; start)`, `AtMCS`, `BetweenMCS`; after-lifecycle slot | M2.3 |
| Coupling | ODE/SDE/DAE/jump components via MTK/Catalyst/JumpProcesses; SBML via SBMLToolkit; per-cell FBA via COBREXA (Julia); held outputs over the CPM interval; init-once; per-cell component lifecycle (reinit from published state at division, discard at retire); `mcs_duration` maps MCS to component time | M4.1 |
| Events | sampled events with trigger memory (`OnRising`, `WhileTrue`, `Once`), delays via MTK | M3.3 / M4.1 |
| Compartments | compartment cells grouped under a parent (internal vs external J, coordinated division) | M2.10a (new) |
| Observation | `CellSeries` keyed by (id, generation) with lineage; Tables.jl `observation_table`; typed reductions; storage sinks via HDF5.jl/Zarr.jl extensions; `ObservationTransform` (T=0 anneal on a private copy, needed for Graner–Glazier measurements); opt-in detailed attempt accounting (`stats = :detailed`, atomics only when requested) | M2.10 |
| Checkpoint | one logical schema (state, slots, MCS, RNG contract version, semantic fingerprint independent of backend/precision, parameter history, component integrator state); restore on another backend = logical restart; JLD2/HDF5 adapters | M2.10 |
| Initialization | layout library (uniform seeds, rejection placement, rectangles/spheres/blobs, masks/images), PIFF importer (pure Julia), init-only RNG stream, canonical id compaction | M2.1 / M3.3 |
| Diagnostics | aggregated build errors with source locations; `inspect(sys, Schedule() / RandomOperations() / Effects())`; runtime failures name MCS, stage and source | M3.3 |
| Escape hatch | `@stage` blocks exposing LocalMath laws (`Resolve`, bounded `Collect`, `KeyedReduce`, `@ordered` recurrences, grouped outputs) inside a Potts model | M3.4 |
| Preflight | unsupported algorithm × backend × feature combinations rejected at `init` (e.g. exact connectivity on checkerboard); no silent fallback | M1.4 |
| Verification | **exact transition-matrix oracle on tiny lattices** (1D hand-derived, exhaustive 2D, minimal 3D; independent of production ΔH; scheduler state lifted into the chain; TV distance per row). Test-only cost, high scientific value. Plus a statistical CPU/GPU comparison with preregistered tolerances | M1.4 (harness), each M2.x (fixtures) |
| Benchmarks | full workload matrix (volume-only, sorting, surface, chemotaxis, focal, growth/division, death, dense/sparse, 2D/3D, small → publication scale); metrics: attempts/s, launches/MCS, syncs/MCS, memory, thread scaling, ensemble throughput, compile growth vs model size | M1.5 + each M2.x |
| Models | Mombach 3D sorting; Shirinifard CNV; Wang 2025 collective migration; OpenVT categories (single-cell migration, prescribed-gradient chemotaxis, elongation angiogenesis); Jiang 2005 3D tumor; Bauer 2007/2009 angiogenesis; Zajac anisotropic adhesion; Jafari Nivlouei tumor + therapy; Starruß myxobacteria (needs ordered chain relations); Fortuna compartments; Jiang 1999 foam rheology; FBCA via COBREXA; the "hard-model" adversarial set | M4.3 (new) |
| Visualization | vector/arrow channels, relationship overlays, lineage, tensor ellipses, true 3D `PottsVolume`, WGLMakie, DataInspector with generation, rerun controller via `remake`, no hidden device sync in plot conversion | M5.2a (new) |
| LocalMath | keep every scientific witness (spring/fracture, matrix-free FEM, z-buffer, deposition/rasterization, RSA, PGS, stoichiometric admission, DEM broad-phase, adaptive FEM, particle grouping) and the negative controls as tests/examples | M5.1 |

## 4. Rejected or deferred (with reason)

| Finding | Verdict | Reason |
|---|---|---|
| bitwise CPU/GPU parity, fixed FMA policy, fixed-tree reductions, no float atomics | REJECT | D-029 |
| canonical source-order summation of H terms | REJECT | D-029; symbolic simplification is the point of global H |
| whole-MCS inactive-bank execution for failure atomicity | REJECT | D-029; failures are rare errors, reported via `retcode`; saves/checkpoints are the recovery points |
| bitwise split == straight checkpoint continuation | REJECT | D-029; the state round-trip is exact |
| preregistered statistical plans with false-positive control for every test | ADOPT-LITE | fixed tolerances decided before a test is written; no ceremony |
| mandatory explicit extinction and inheritance policies with no defaults | ADOPT-LITE | defaults exist (`:retire`, `Copy`/`Split` by extensivity) and are documented; silent mass duplication is prevented by `extensive` |
| lifecycle "reject all ambiguity" default | ADOPT-LITE | static overlap with equal priority is rejected at build; dynamic conflicts resolve by priority, then a stable random tiebreak |
| claim-before-accept checkerboard order (the legacy spec) | REJECT | accept-then-claim yields more accepted copies per color, so it is faster. Both are approximate parallel dynamics; ours is documented and validated statistically against sequential |
| `PottsIntegrator` must not be a `DEIntegrator` | REJECT | SciML coexistence: JumpProcesses' `SSAIntegrator <: DEIntegrator` is the precedent; `t` is an integer MCS and `u` a read-only view |
| units kept entirely out of execution | ADOPT-LITE | units validate parameters at `mtkcompile`; `mcs_duration` maps MCS to physical time for components and output; execution never branches on floating-point time |
| LocalMath plan-time `code_typed` admission | ADOPT-LITE | kept, but only for **user-supplied** LocalMath callables and cached per callable type; Potts-generated evaluators are trusted and skip it |
| leases / poison / receipts | ADOPT-LITE | resource lifetime is owned by the integrator/prepared plan until the next sync (the GC-safety concern is real); receipts and poison are dropped |
| capability report objects | ADOPT-LITE | preflight rejection at `init` (see §3); no report objects |
| 5 fingerprints | ADOPT-LITE | two: a semantic fingerprint (checkpoint compatibility, backend-independent) and the executable cache key (internal) |
| `extend` strictness (duplicates are errors) | REJECT | follow MTK `extend` semantics; conflicting writers of the same state in the same phase are rejected by the scheduler |
| LotteryCPM, TiledCheckerboardCPM | DEFER | checkerboard covers parallel execution; add a parallel family if a model needs its kinetics |
| hexagonal / rhombic-dodecahedral / graph lattices | DEFER | the architecture allows them (relations are stencils); not in the first release |
| multi-device, off-lattice, NeuralPotts, fitting/inference | DEFER | out of scope for the rewrite |
| MethodOfLines input fields | DEFER | upstream limitation; output-only MOL components until then |
| MorpheusML/SBML runtime interop through non-Julia tools | REJECT | D-030; SBMLToolkit and a pure-Julia MorpheusML importer are allowed |

## 5. Open scientific questions to carry, not block on

- the invariant distribution of checkerboard variants with shared cell-wide state (SEM-ALG-001), answered empirically by the transition-matrix oracle on tiny lattices
- statistical portability of normal/Poisson/permutation samplers across backends (SEM-RNG-005): statistical only, per D-029
- validated CompuCell3D/Morpheus/Artistoo parameter conversions (SEM-COMP-001). Energy rescaling must rescale T, yield and drives together
- paper-level: Graner–Glazier annealing semantics, Merks split and stencil, Wortel self-inclusive neighborhood, CNV relationship division policy. Each is resolved when that model is ported, and recorded as a D-entry
