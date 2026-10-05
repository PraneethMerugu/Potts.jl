# Decision log

Append-only. Each entry: context → decision → consequence. New questions during the
rewrite are answered here by the implementer using the principles in `AUTONOMY.md`,
not by asking the maintainer, unless the question is in the escalation list.

## D-001 Rewrite, not migrate (2026-09-29)
Context: 60k of 90k lines slated for deletion; branches diverged in those files.
Decision: greenfield monorepo; LocalMath and MakiePotts imported with history; frozen
`origin/main` set as scientific reference. Consequence: no conflict resolution in legacy
compiler/execution code.

## D-002 Monorepo home
Decision: `Potts.jl` on GitHub becomes the monorepo (in place). During the rewrite all
work lands on branch `monorepo`; `main` is untouched until cut-over. Legacy history
reachable via `legacy/*` tags. Other repos archived read-only after cut-over.

## D-003 Compatibility break
Decision: pre-migration trajectories and checkpoints match statistically, not bitwise.
Versions: Potts 0.4.0, CorePotts 0.3.0, LocalMath 0.3.0, MakiePotts 0.4.0,
PottsModels 0.2.0.

## D-004 Package names
Decision: keep LocalMath, CorePotts, Potts, MakiePotts, PottsModels. No renames.

## D-005 RNG
Decision: Philox4x32-10, 64-bit key from (seed, replica, repeat), 128-bit counter
(mcs, phase_round, entity, stream|draw). Streams assigned by codegen from namespaced
operation keys. Rationale: 32-bit multiplies are native on all GPUs; address semantics
preserved.

## D-006 Deterministic acceptance across backends
Decision: package-owned pure-Julia `exp` (no fast-math) in Metropolis; bitwise CPU/GPU
parity for the same scalar type is a tested guarantee. Base `exp` may be selected by
`fast_math = true` (opt-in, parity not guaranteed).

## D-007 Scalar types
Decision: `Float64` default on CPU, `Float32` default on GPU, `scalar_type` keyword
overrides. Parity claims are per scalar type.

## D-008 Checkerboard coloring
Decision: stride `s = max_read_radius + 1` per axis from footprint analysis (Moore
contact → 4 colors in 2D, not 9). Conflict rule: mutual-maxima cell claims. Dynamics
difference from sequential documented; sequential is the fidelity reference.

## D-009 Default algorithm
Decision: `SequentialCPM` default on CPU; `CheckerboardCPM` required on GPU. `solve`
without an algorithm on a GPU backend errors with a message naming `CheckerboardCPM`.

## D-010 Failure semantics
Decision: device status word + `ReturnCode.Failure`; phases validate before writing so
the last MCS boundary is consistent. No per-color shadow copies, no receipts.

## D-011 Lifecycle gating
Decision: device-side candidate count; all lifecycle kernels early-exit on zero. No
host sync per MCS.

## D-012 Parameters
Decision: `PottsParameters{T,NT,D,C}` (tunable `NTuple{NT,T}`, discrete, constant).
Structural parameters are literals in generated code; changing them rebuilds the
problem.

## D-013 State layout
Decision: structure-of-arrays `CPMState` with `NamedTuple`s keyed by model names.
Cell capacity grows by host reallocation at MCS boundaries.

## D-014 Codegen mechanism
Decision: Symbolics `toexpr` + custom lowering rules for Potts primitives (gathers,
trackers, draws, CSR reads), assembled into one `Expr` per generated function, compiled
via RuntimeGeneratedFunction + `drop_expr`. `eval_expression`/`eval_module` and
`expression = Val(true)` supported as in MTK. `cse = true` default.

## D-015 Symbolic front end dependency
Decision: ModelingToolkitBase (not full ModelingToolkit) in Potts; full MTK,
MethodOfLines, Unitful, Metal, CUDA as extensions.

## D-016 Fingerprint
Decision: one `UInt64` fingerprint = hash(generated code strings, structural parameters,
lattice, scalar type). Used only for checkpoint compatibility.

## D-017 Native components
Decision: init-once integrators coupled via SII; per-cell ODEs batched; Metal via
`EnsembleGPUKernel`. Scheduling phases kept.

## D-018 MakiePotts
Decision: stays `lib/MakiePotts`; reads through public accessors; gains `plot(sol)`.
Its `SPLIT_PROVENANCE.md` and render-frame contract are kept.

## D-019 Testing tools
Decision: ParallelTestRunner with `GROUP` (Core, QA, GPU, Reference); Aqua,
ExplicitImports, JET, AllocCheck in QA; Downgrade CI; AirspeedVelocity for benchmarks;
JuliaFormatter `style = "sciml"`.

## D-020 GPU testing
Decision: the GPU group runs locally (Metal) before every merge, by the implementer;
hosted GPU CI is a later addition and not a blocker.

## D-021 Reference environment (superseded by D-048)
Decision: `reference/Project.toml` + committed `reference/Manifest.toml` pin the legacy
set (LocalMath 041b930, CorePotts 6ec7316, Potts 427dc2e2, PottsModels de97149,
MakiePotts a8a025f) by git revision. The only committed Manifest. Reference tests run
in the `Reference` group only.

## D-022 Parity dispute rule (superseded by D-048)
Decision: if the new implementation disagrees with the reference beyond statistical
tolerance, the brute-force oracle decides. If the oracle sides with the new code, the
discrepancy is recorded here with evidence and the reference is marked wrong for that
observable. If the oracle sides with the reference, the new code is a bug.

## D-023 Talks and studies
Decision: SCDPotts, LocalMathSCD, SCDslides move to a separate `PottsStudies` git
repository pinned to the reference set; not part of the monorepo. KaimonCompilerTools
stays standalone.

## D-024 Legacy repos and branches
Decision: after tags are pushed, archived branches are deleted locally and remotely and
stale worktrees pruned. Legacy repos are archived on GitHub after cut-over.

## D-025 What must never happen without the maintainer
- force-pushing or rewriting `main` of any repository (cut-over is the one planned
  instance, and it is pre-authorized only when AUTONOMY.md's cut-over checklist passes)
- deleting a GitHub repository
- changing scientific semantics of a published model beyond D-003/D-008 without a
  decision entry citing the oracle evidence

## D-026 Authoring surface (2026-09-29)
Decision: the surface in `AUTHORING.md`. Global-H authoring (`@energy domain => expr`)
with symbolic ΔH derivation and a compiler-generated `total_energy` self-check; MTK
syntax for all differential equations (`D(x) ~ …`, lattice operators `Δ`, `∇`); updates
as equations with `Pre`; generator comprehensions over relations replace gather/fold;
`@potts_model` mirrors `@mtkmodel` and lowers to plain constructors. Coexistence with
MTK/SciML over replacement.

## D-027 Lattices and neighborhoods
Decision: N-dimensional lattices (1D/2D/3D tested), per-axis boundaries and spacing,
neighborhoods of any order (`Moore(k)`, `VonNeumann(k)`, `Ball(r)`, `Shell(k)`,
`Stencil`, weighted variants). Checkerboard stride derives from the declared orders.

## D-028 Renames
Decision: the table in `AUTHORING.md` §9 is authoritative; old names are not kept as
aliases.

## D-029 Performance over exact playback (2026-09-29, maintainer principle)
Principle: take inspiration from the best high-level features; disregard guarantees
that cost performance. Exact trajectory playback is not a product goal.
Decisions:
- **Supersedes D-006.** Metropolis uses native `exp` (fast math allowed on GPU). CPU/GPU
  agreement is statistical, not bitwise.
- Same seed + same backend + same scalar type → same run is kept, because the counter RNG
  makes it free; it is a debugging aid, not a published guarantee.
- Checkpoints resume a statistically correct continuation; bitwise split == straight is
  not required (tests assert state round-trips exactly, not trajectories).
- No ordered/canonical reductions on the hot path when a relaxed atomic suffices;
  LocalMath's `CanonicalLeftFold` remains available, never the default in CorePotts.
- Filter for importing legacy features: a feature is carried over only if its
  steady-state cost is ~zero or it is scientifically essential.

## D-030 Julia-only coupling and dependencies (2026-09-29, maintainer principle)
Decision: every runtime dependency and every coupling target is a Julia package.
Intracellular models couple through ModelingToolkit (ODE/SDE/DAE/jump systems),
Catalyst.jl, JumpProcesses.jl, SBMLToolkit.jl (for SBML import) and COBREXA.jl (flux
balance); PDEs through MTK/MethodOfLines or built-in lattice stencils. No Python,
RoadRunner, Antimony, MaBoSS, Tissue Forge or other non-Julia runtimes. Binary
artifacts (JLLs) pulled transitively by Julia packages are acceptable; importers for
foreign model formats (e.g. MorpheusML, PIFF) are allowed if written in pure Julia.

## D-031 Legacy-spec adjudication (2026-09-29)
Decision: `research/legacy-spec-adjudication.md` is adopted. Fixes F1–F13 (RNG key and
generation, stable stream hashes, checkerboard claim sets and write footprint, medium
never claimed, non-finite ΔH status, 1 MCS = N attempts, Float32 default everywhere,
per-kind extinction default `:retire`, deferred creations on capacity exhaustion,
exact-lookup `sol(t)`, tolerance-based ΔH self-check) are applied to INTERNALS.md.
Adopted features are scheduled in ROADMAP.md. Rejections are recorded with reasons.
Supersedes D-007 (scalar defaults) and the `attempts_per_site` parts of D-008/AUTHORING.

## D-032 Morpheus and CompuCell3D research (2026-09-29)
Decision: AUTHORING.md §12 is adopted (from `research/morpheus-gaps.md` and
`research/cc3d-gaps.md`). Highlights: `NeighborOrder(k)` replaces `Shell(k)`; unordered
contact pairs counted once; contacts may read both owners' cell state (non-local claim
set); per-length energy normalization; per-kind/per-cell temperature with `combine`;
unified `offset` (CompuCell3D offset = −Morpheus yield); proposal-scope `δcentroid`,
`normal`, `velocity`; neighbor-cell iteration with interface lengths; cell-level field
reductions; CompuCell3D shape descriptors; kind-dependent diffusion, quasi-steady
fields, secretion/uptake helpers, per-face field BCs, `@brownians`; kind-scoped ODE
blocks and pure-Julia intracellular components; division with `daughter` index and
state-oriented planes; `@terminate`; hexagonal geometry and irregular domains promoted
from deferred; PIFF and pure-Julia MorpheusML import. Portability semantics per §12.9.

## D-033 CorePotts phases are generated KA kernels; LocalMath is optional
Evidence (2026-09-29, M1 Pro, Julia 1.12.6): one periodic 5-point Laplacian, 256².

| | first execution | warm |
|---|---|---|
| LocalMath (`@localmath` + `@prepare` + `execute!`) | 8.2 s (law 3.0 s, prepare 5.0 s) | 1.77 ms |
| plain KernelAbstractions kernel | 0.16 s | 0.31 ms |

At 1024² with 8 threads the warm times are 7.2 ms and 1.2 ms.

Decision:
- Synchronous site and cell updates, history pushes and field steps run as plain KA
  kernels generated like `delta_H`, through a phase protocol
  `phase(st, p, ctx, key, mcs, backend)` (INTERNALS §1.6).
- CorePotts does not depend on LocalMath.
- LocalMath stays in the monorepo, tested, as an optional stage-program runtime for the
  laws plain kernels express poorly (ordered folds, bounded collections, keyed reductions
  with provenance). A LocalMath prepared plan is wrapped as a phase.
- Supersedes INTERNALS §3's "used by CorePotts for…" list. Reversible if LocalMath's
  first-execution and warm costs reach parity.

## D-034 Act model mean and legacy connectivity semantics (Act part superseded by D-049)
- **Act mean.** Legacy Potts averages activity as `exp(mean(log1p a)) − 1`. The published
  model (Niculescu et al. 2015, Artistoo) uses the plain geometric mean, which is zero if any
  owned neighbour has zero activity. `act_mean`/`act_delta` default to the published plain
  mean; `shifted = true` reproduces legacy and is used in the parity tests.
- **Merks connectivity.** Legacy counts out-of-domain ring sites as medium: CorePotts
  6ec7316 returns owner 0 for an absent neighbour, and `typemin` only when the offset is
  missing from the relation. A literal reading of the Potts.jl call site suggested
  "reject at walls", but that ratchets cells against closed walls (mean volume 11.4 against
  legacy 7.8 at MCS 40). The port follows the executed semantics, and parity passes.

## D-035 Lifecycle: one 4-byte readback per checked MCS
INTERNALS §1.7 asked for a lifecycle with no host synchronization. Lowest-first id reuse,
capacity deferral and exact tracker rebuilds are sequential, host-shaped work. Doing them
on-device needs device-wide scans, plus 64-bit atomics that Metal lacks.

Decision:
- A model with a `Lifecycle` runs one trigger kernel per checked MCS (`every`) and reads
  back the 4-byte event count. Quiet MCS end there.
- Event MCS plan ids on the host, run partition/removal/rule kernels, and rebuild
  trackers exactly on the host.
- Models without a lifecycle pay nothing. Cost is under 1% at publication scale.
  Revisit if profiling shows lifecycle syncs matter.

## D-036 Compartments are a cluster id per cell, not a second level of ownership
CompuCell3D's compartments put `clusterId` on every cell; Morpheus has no equivalent.
A two-level lattice (site → compartment → cell) would double every ownership read in the
hot loop.

Decision:
- `st.cell.cluster[c]` names each cell's cluster by a live member (the root, lowest id
  after normalization); a lone cell is its own cluster, and free slots are their own.
- Internal vs external contact energies are plain model code
  (`same_cluster(st.cell, a, b) ? Jint : J`), so the symbolic layer needs no new
  construct: it becomes a conditional on a cell quantity.
- Cluster volume and surface are trackers indexed by cluster id, committed atomically so
  they stay exact under checkerboard. Energies read exact values only with
  `cluster_claims` (the `link_claims` trade: at most one change per cluster per color).
- `Lifecycle(…; clusters = true)` divides clusters as a unit. The root's trigger decides;
  the host evaluates the plane on cluster moments (planning is host-side already, D-035);
  every member splits along it through the cluster centroid; daughters form a new
  cluster. Without it, compartments divide alone and daughters stay in the cluster.
- Lifecycle events re-root clusters whose root died.

## D-037 Symbolic front end: implementation choices (M3 first slice)
- **IR.** Symbolics expressions, every model quantity tagged with an `Info` metadata
  record (role: param, kindtable, site/cell/model/field variable, builtin, bound). The
  metadata survives `substitute`/`expand`. Variables are MTK-style `x(t)`, so `D(x)`,
  `Pre(x)` and `~` come from ModelingToolkitBase unchanged.
- **Macro.** `@potts_model` is sugar for a constructor. Section bodies run as ordinary
  Julia with built-ins and DSL words bound locally (nothing but the entry points is
  exported). A syntactic rewrite turns `x[i]` into `at`/`at2`, `&&`/`||`/`!` into `&`/`|`/`!`,
  ternaries into `ifelse`, and `fold(body for n in R(s) if cond)` into a `gather` term.
- **Codegen emits its own neighbour loops.** It does not call `contact_delta`: `weight` may
  appear anywhere in a contact term, and the surface δ is fused into the contact loop
  when the relations coincide. Cell-term deltas are `E(q+δq) − E(q)`, expanded when
  that is cheaper by operation count (the volume term becomes `λ(1 ∓ 2(V − V₀))`).
- **Contact terms** are symmetrized unless structurally symmetric. Kind tables used in
  them must be symmetric: compared up to index order symbolically, and checked against
  their values at `PottsProblem`.
- **`total_energy`** sums cell terms over every cell slot: an emptied cell keeps
  `E(volume = 0)`, matching the ΔH of the copy that emptied it (legacy/CC3D semantics).
  The self-check `ΔE == H(after) − H(before)` is exact (0.0) on all four models.
- **Deterministic generated code.** Generated names are derived from model content
  (never `gensym`), so rebuilding a problem yields the same RuntimeGeneratedFunction type
  and never recompiles. Found when per-seed rebuilds cost 18 s in the parity tests.
- **Deferred.** No-extinction is an explicit `@constraint no_extinction`, not a default
  (the legacy published models allow extinction). The proposal relation stays on the
  algorithm (`SequentialCPM(; proposal)`), and the `@sweep` law is not yet propagated
  (Metropolis with offset 0 is the default everywhere).

## D-038 Components as generated batched cell ODEs (2026-09-29)
Context: D-017 asks for init-once integrators, per-cell ODEs batched over the cell
dimension, and Metal via DiffEqGPU's `EnsembleGPUKernel`.

Decision: `@components cells(k) name = sys` takes an MTK `System`. At `mtkcompile`:
- The system is `mtkcompile`d once.
- Its unknowns become cell variables (`name₊x`) and its parameters become model
  parameters (`name₊p`). A parameter coupled with `@equations name.p ~ expr` is replaced
  by that cell-scope expression instead.
- Its observed equations are substituted.
- Its explicit ODEs join the model's own cell ODEs, gated by kind.

Advancing the ODEs:
- All cell ODEs advance together per cell in one generated kernel (a `CellPhase`, CPU or
  GPU). Each MCS covers `mcs_duration` with the sweep's `ode_solver`:
  `ExplicitEuler(substeps)` or `RK4(substeps)`.
- The unified kernel is Jacobi: every right-hand side sees the state at the start of the
  step. Before, each cell ODE was its own phase, so later equations saw earlier updates.

Why:
- This is `EnsembleGPUKernel`'s execution model (one fixed-step trajectory per work
  item), produced by our own code generator. It needs no new dependencies (Julia-only,
  small), works on Metal, and fuses with the model's cell state.
- MTK remains the authoring and compilation front end for the component.

Deferred: adaptive or stiff integration, via an optional host `ODEComponent` that keeps
an init-once OrdinaryDiffEq integrator and couples through SII. Also deferred: DAE and
jump components, MethodOfLines components, and output couplings into kind tables.

## D-039 No `compose` for Potts systems; units on DynamicQuantities (2026-09-29)

Decision: Potts models do not implement MTK's namespacing `compose(sys, subsystems)`.
Composition works in three ways:
- `extend`/`@extend` merges models; this is MTK's `extend`.
- `@components` embeds MTK systems per cell or per model, namespaced as `name₊x` (D-038).
  A component may itself be an MTK `compose`d hierarchy, which is flattened by its own
  `mtkcompile`.
- `lookup` reaches into a built model.

Units use MTK's own mechanism: `VariableUnit` metadata, with DynamicQuantities in a weak
extension. This replaces the Unitful extension named in D-015.

Why:
- A Potts model owns one lattice, one kind list, one sweep and one H. A namespaced
  sub-model would have to share all of them, so "compose" would really be `extend`
  with renamed parameters.
- Every use seen so far (legacy composition tables, Morpheus and CompuCell3D plugins) is
  either an extension of a base model or an intracellular or model-level MTK system,
  and both are covered.
- For units, following MTK means one unit system across Potts and its components.

Revisit if a model needs two copies of the same sub-model with different parameters.
That would be `extend` plus automatic prefixing.

## D-040 LocalMath leaves the monorepo (2026-09-29, maintainer-approved)

Decision: `lib/LocalMath` may be deleted. Nothing in Potts, CorePotts, MakiePotts or
PottsModels depends on it (D-033). Its reserved niche (ordered folds, bounded collections,
keyed reductions) is covered by generated gathers and population folds, atomic `CellReduce`
and cluster trackers, and host phases for the lifecycle, links and compartments.

Why:
- D-033 benchmark: 8.2 s first execution vs 0.16 s, and 1.77 ms vs 0.31 ms warm, for one
  Laplacian stencil.
- Much of its size (about 24.5k source and 15k test lines, 45% of the repo) is exactness
  machinery (receipts, leases, canonical ordering, plan-time admission) that D-029 drops.

Consequences:
- M5.1 (LocalMath slimming) is withdrawn.
- INTERNALS §3 is historical.
- The workspace, CLAUDE.md, the test groups and CI lose `LocalMath`.
- Its git history is preserved in the legacy `LocalMath.jl` repository and in this repo's
  history. If a stage-program runtime is wanted later, revive it there as a standalone
  package, not as a Potts dependency.

## D-041 Populations in energies are snapshots per MCS (2026-09-29, maintainer-approved)

Decision: a population fold inside `@energy` (e.g. `mean(volume for c in cells)`) is
evaluated once per MCS, after the before-MCS updates and just before the sweep (and at
initialization). It is hoisted into a model-scope value and held constant during the sweep. AUTHORING says so. Under this meaning ΔH is exact.

A live, exact variant may come later as an opt-in (AUDIT §1 decision a/b). It would cover
sum-decomposable folds (sum, count, mean): model-scope running totals updated on every
accepted copy, with cell terms expanded algebraically into totals. It would be exact on
`SequentialCPM` and use a colour-lagged total on the checkerboard (D-029). `minimum` and
`maximum` stay snapshot-only.

Why: today's behaviour gives a wrong ΔH and costs O(N) per proposal (A-60). The snapshot is
standard CPM practice, cheaper, and GPU-safe, and it keeps global energy terms.

## D-042 Update blocks follow MTK discrete semantics (2026-09-29, maintainer-approved)

Decision:
- Within one update block, `Pre(x)` is always the value before the block, snapshotted where
  needed.
- A bare `y` on a right-hand side, where `y` is updated in the same block, means y's new
  value.
- The compiler orders the updates by these dependencies across scopes and cadence groups,
  and reports cycles as errors.
- Population folds inside updates become reductions that run before the update reading them.
  They fold old values under `Pre` and new values when written bare.

Why: execution in alphabetical scope order made `Pre(m)` return new values (A-63). In-place
folds raced and compounded (A-62). This keeps chaining, now explicit, and fixes both.

## D-043 `position` is Cartesian; `site` is the lattice site (2026-09-29, maintainer-approved)

Decision:
- `position[k]` is the embedded (Cartesian) coordinate times the spacing. On a square
  lattice with spacing 1 it equals the old values.
- The new name `site` is the current lattice site. It is usable as a gather anchor.
- Domain predicates receive Cartesian coordinates. Raw indices are opt-in.
- `Weighted` weight functions receive embedded offsets.

Why: raw indices are sheared by 60° on hex, and `position` could not be indexed or used as
an anchor (A-02, A-05, A-66).

## D-044 3D hexagonal lattices: prism first, then FCC; HCP deferred (2026-09-29, maintainer-approved)

Decision: `Hexagonal(; stacking = :prism)` in 3D (6 in-plane + 2 axial neighbours) comes
first, then `:fcc` (12 equidistant neighbours).

HCP is deferred. Its layer-parity-dependent offsets don't fit the one-static-relation
design, and it shares FCC's first shell. It may come later as its own geometry type, so
that only HCP models pay for the parity branch.

## D-045 Keep features the audit proposed rejecting (2026-09-29, maintainer-approved)

- **An energy that reads an on-copy-written variable** is scored with the on-copy update
  applied, so ΔH includes it (A-67).
- **`@relations proposal = …`** maps onto the algorithm's proposal (A-41).
- **Extension replacement** is keyed by `(phase, target)`, with a warning when the cadence
  differs. This matches AUTHORING (A-47).
- **Still rejected, each with a pointer to what works:**
  - `rand()` in an `Adaptive` ODE: use a fixed-step solver, or a future SDE option (A-68).
  - `Every(n)` on `@on_copy`: use `when = mcs % n == 0` (A-36).

## Codegen committee (2026-09-29): amendments to D-012, D-014, D-016; D-046, D-047

A maintainer review raised five SciML-alignment items. Three proposers and an adversarial
judge weighed them; scratch evidence is in `/tmp/committee/`, not in the repo.

### D-012 (amended) Parameters

Decision: `PottsParameters` stores parameter values in a `NamedTuple`. It is isbits, values
are converted to the scalar type `T`, and kind tables are `SMatrix`. The generated code reads
parameters by name, which is a constant field index.

SciMLStructures is implemented on the host side:
- **Tunable:** every `T`-valued scalar and kind table, flattened on `canonicalize`.
- **Discrete:** integer, Bool and enum values.
- **Constants:** everything else.

`replace` re-derives parameters defined by expressions and re-checks the tables. Structural
parameters are literals in the generated code; changing them rebuilds the problem.
Flattened tunable storage (a tunable `SVector`) is deferred until a need is measured.

Why:
- Performance is identical either way.
- A raw `replace` on flattened storage would bypass the re-derivation (D-042/A-39) and the
  contact-table symmetry check.
- Names in the type are moot, because every RGF type already carries a per-model id.
- CPM acceptance is discontinuous, so AD gradients through `solve` are essentially zero.
  The payoff is derivative-free fitting and ensemble `replace`.

### D-014 (amended) Codegen mechanism

Decision: Potts owns its lowering from symbolic terms to `Expr` (`src/lower.jl`). It does not
use Symbolics `toexpr`/`build_function`, because it needs:
- `literal_pow` for integer exponents;
- literals in the scalar type `T` (no Float64 on Metal);
- a lazy `ifelse`;
- loops for gathers, folds, history rings and draws;
- its own scope and mode diagnostics.

N-ary `+`/`*` are emitted as left-associated binary calls: Julia varargs above 32 arguments
allocate. The result is bitwise identical, since n-ary `+` is itself a left fold. Functions
are compiled via RuntimeGeneratedFunction plus `drop_expr` in the Potts cache.

There is no general CSE. Lowering reuses the bindings it already has (`k_old`, `k_new`,
per-side loads), and LLVM removes about 85% of the repeated scalar work. A Potts-owned
Expr-level CSE pass that never hoists out of conditionals may come later, if a published
model gains more than 10% from it. SymbolicUtils' CSE is not used: its internals are not
public API, it binds exponent constants, and it hoists work out of a lazy `ifelse`.

`eval_expression`, `eval_module` and a problem-building `expression = Val(true)` are not
supported. `Potts.generated_code(sys; T)` returns every generated Expr. PottsModels
precompiles its models by running a workload (D-047): RGF ids are content hashes, so the
cached code is reused.

### D-016 (amended) Fingerprints

Decision: the fingerprint is a hash of every generated Expr with line numbers stripped
(ΔH, `commit!`, constraint, temperature, total energy, phases, lifecycle), plus the lattice,
spacing, neighbourhood and `T`. It must not depend on the install path. It is valid for the
same Julia version only.

### D-046 Model content in types (scopes the CLAUDE.md rule)

Decision: per-model types are allowed because they are per-model by construction: RGF ids,
the parameter NamedTuple, `SMatrix` sizes and the state NamedTuples (D-013). CorePotts
algorithm, lattice and kernel types must not encode model content. CLAUDE.md's code rule
says so (wording approved by the maintainer, 2026-09-29).

### D-047 Codegen QA and time to first step

Decision: every PottsModels model and test fixture must pass, in Float64 and Float32:
- AllocCheck on the sequential and checkerboard MCS;
- JET on plain functions `eval`'d from `generated_code` (JET cannot see inside RGF bodies,
  so `@test_opt step!` alone is blind to generated code);
- under Float32, no Float64 literal in the generated code and no LLVM `double`.

PottsModels carries a `@compile_workload` (Akeeb, Float32, Sequential and Checkerboard),
which developers can switch off with the PrecompileTools preference. Target: first MCS in
under 15 s from a fresh process for the covered configuration (16.1 s measured before the
workload).

## Maintainer approvals (2026-09-29)

- **D-046**: approved, with the CLAUDE.md wording now in place.
- **D-040**: approved. LocalMath is gone from the workspace, the tree, the test groups and
  CLAUDE.md. M5.1 is withdrawn and INTERNALS §3 points here. `reference/` is untouched.
- **Phase 0 local cleanup**: approved (AUTONOMY §4). Pushes, tag pushes included, wait for
  the cut-over checklist (§5). Force pushes stay forbidden (D-025).
- **Akeeb connectivity**: `AkeebInvasion` using `connectivity(...; rule = :merks)` is
  approved as the published model's science. The justification is the legacy parity test
  (`test/parity/akeeb.jl`: every metric agrees under `:merks`).
- **D-041, D-042, D-043, D-044, D-045**: approved as written.
- **D-049 implementation choices** (2026-09-29): approved as reported.
  - Merks uses the one-arc connectivity rule, a hard veto standing in for the paper's
    splitting penalty (E₀ > 2000).
  - Merks keeps these differences: free closed walls (paper J_cB = 100), no dissipation
    threshold E₀, and the fewest stable field substeps instead of 15.
  - Two Graner–Glazier paper observables are re-set on the PRE §II D3 state: partial
    sorting by the dark–medium share, and layer reversal at 4000 MCS.

## D-048 No parity harness against the legacy codebase (2026-09-29, maintainer)

Decision: models are verified by ordinary tests, not by statistical parity with the legacy
implementations. `reference/` (the pinned legacy environment, its samplers and data), the
`Reference` test group and the legacy parity tests are removed. The legacy code stays
reachable through git history and the local `legacy/main` tags. Supersedes D-021 and D-022.

Why: the maintainer's call. Audit group 4 also showed the parity tests were weak evidence:
the legacy fixtures are 8×8 toy configurations in which the tested mechanism barely acts.
Wortel's cells die by MCS 10, and Merks' chemotaxis energy (χ·Δc ≈ 0.08) is negligible
against T = 6. Strong Act effects stay undetectable at 64 seeds even when the cells survive.

What replaces it, per published model:
- the brute-force check that ΔH equals the difference in total energy (already in place);
- independent recomputation of the drives (chemotaxis, Act) and of the effects (on-copy
  writes, phases, field steps, division) against the model's specification;
- the exact transition-matrix oracle on tiny lattices for the generated code;
- invariants: trackers against recounts, connectivity, conservation;
- mechanism tests with negative controls: the mechanism must change the outcome in the
  stated direction, and switching it off must remove the effect;
- generated code equal to the hand-written CorePotts ports (test/ports), and CPU/Metal
  statistical agreement.

The scientific dispute rule becomes: brute-force oracle, then the paper.

## D-049 Paper fidelity of the published models (2026-09-29, maintainer-approved)

The maintainer approved every recommendation of the paper-fidelity round (AUDIT §11, F-1…F-6).
The paper and its reference code define each model (D-048).

- **F-1: models declare their copy neighbourhood.** `@sweep Metropolis(; proposal = …)`
  sets the default for algorithms constructed without one. `GranerGlazier` declares
  `Moore(1)`, as the paper copies from 8 neighbours.
- **F-2: the Graner–Glazier initial state follows PRE §II D3.** Rectangular cells of area
  40 are relaxed as one type (J_ll = 2, J_lM = 8, T = 5, λ = 1) for 400 paper MCS
  (6400 here), then given random types, 32 dark and 32 light.
- **F-3: Merks as in the 2006 paper.**
  - Energies may read `major_length` (4√λ_max of the cell's inertia, Merks Eq. 5), and the
    model has the length constraint `λ_L (major_length − L)²`.
  - It has adhesion `J`, and `c` decays only in the medium.
  - Chemotaxis applies to every copy, as in 2006; the 2008 contact-inhibited
    extensions-only form is kept as an option.
  - The defaults are paper-scale, in lattice units.
- **F-4: WortelAct follows Niculescu et al. 2015 and Artistoo.**
  - The plain geometric mean.
  - The Act term applies to every copy, so retracting active sites is penalised.
  - Every gained site becomes fully active.
  - Connectivity is optional.
  - The defaults are the amoeboid parameter set on a 200² torus. This supersedes the parity
    choices in D-034.
- **F-5: the OpenVT name belongs to the benchmark.**
  - The single-division fixture is renamed `SingleDivisionFixture`.
  - `OpenVTGrowingMonolayer` implements the OpenVT growing monolayer with the Artistoo
    parameter set (A₀ = 25, λ = 20, τ = 84, T = 20, J_cc = J_cM = 20).
  - Cells divide at a deterministic 2A₀ (the spec's baseline), along a random plane.
  - Type-1 contact inhibition is on through β.
- **F-6: `AkeebInvasion` uses `rule = :local`**, exactly CC3D 4.3.1's `Connectivity`. This
  supersedes the parity-based approval of `:merks` (maintainer approvals, item 4).

## D-050 Per-model paper-vs-code decisions for the 12 published models (2026-09-30, maintainer-approved)

Decision: the recommendations in `research/model-specs/README.md` §4.1–§4.12 are the
decided defaults, and each named alternative there ships as a documented variant keyword.
The maintainer replied "approve all" in the models-and-publications session, which relayed
the approval here; the README header records it. Items blocked on an author question (§5)
keep the recommended default until the author answers.

Heuristic: default to whatever produced the published figures (usually the released code),
and ship the other reading as a variant. Every default appears in the tutorial's deviations
table.

This reopens and supersedes these parts of D-049 (F-3) for Merks:
- M1: separate 2006 and 2008 parameter sets instead of today's mixed defaults (resolves
  AUDIT P-14);
- M2: 2006 target length 50 px, with 60 px as a variant;
- M3: a soft connectivity penalty E₀ = 5000 on ring-breaking copies of the losing cell
  (once a soft-constraint feature exists), with the hard one-arc veto as a variant;
- M4: a frozen border with J_cB = 100 instead of free walls;
- M5: the paper's field schedule (15 FTCS substeps of Δt = 2 s before the sweep, absorbing
  c = 0 ring) instead of the fewest stable substeps;
- M7: real χ(c,c) and χ(c,M) parameters with an extension/retraction mode switch, which
  replaces `contact_inhibited` and removes the model-named `extension_only` (AUDIT P-15).

It also changes the Akeeb default μ from 30 to 24 (A5).

Status: implementation pending. The feature roadmap that these decisions need (the G1–G21
list and build order in the README) is under review first, so that every model is composed
only from general public primitives.

## D-051 Feature roadmap review: maintainer answers (2026-09-30)

Answers to `research/feature-roadmap-review.md` §7 questions 11, 1, 4, 5, 2 and 12, in
that order below. Questions 3 (Hastings correction for non-symmetric proposal laws) and
6–10 are open. The rest of the review (R0–R16) remains a proposal until each step is taken
up.

1. **Guardrails and R0 renames: adopt now.** Guardrails (a)–(e) go into the test suite,
   together with the family-general replacements for `rule = :merks`, `extension_only` and
   the Act helpers (review §2).
2. **Fractional MCS: allowed.** This amends D-031's "1 MCS = N attempts".
   - An MCS may be declared as a fraction of N attempts, for Jiang 2005's ¼-MCS sweeps.
   - It must cost nothing when unused: the whole-MCS path compiles to exactly today's
     loops, with no extra branch or allocation.
   - It must be easy to author: one keyword on the sweep.
3. **Zajac: build the exact per-copy form** (interface pair trackers with exact ΔH) as the
   reference. The lagged director is a variant.
4. **Coarse field grids: build them.** Fields may live on their own grid, coarser than
   the cell lattice, with restriction and prolongation.
5. **Global connectivity is allowed on the checkerboard.** Most, if not all, features must
   work across both algorithms (sequential and checkerboard). A feature that cannot needs
   an explicit exception here.
6. **Analysis.**
   - A separate composable analysis package only if it has real merit as a reusable
     library.
   - Otherwise analysis lives as clean, readable, teachable Julia in Potts.jl's docs and
     tutorials.
   - Prefer MTK's own path where it is performant: `@observed` quantities evaluated through
     SymbolicIndexingInterface on solutions.
   - Else use the most Julian, teachable code.

## D-052 Acceptance for non-symmetric proposal laws (2026-09-30, maintainer-approved)

Answers `research/feature-roadmap-review.md` §7 question 3. The maintainer approved it in
the models-and-publications session, which relayed it here.

- **Default: plain Metropolis on the model's proposal law, with no correction.** All
  reproduction tutorials use it.
  - The standard neighbour-copy proposal is itself non-symmetric: forward ∝ n_{s′}(i),
    reverse ∝ n_s(i).
  - The published models are kinetic (MCS = time), so a correction would change their
    kinetics.
  - Most of the 12 models carry active drives that break detailed balance anyway.
- **Opt-in Hastings correction as an acceptance type** (algorithm-level, SciML
  problem/solver separation): `acceptance = Metropolis()` (default) or
  `MetropolisHastings()`.
  - Each R10 proposal law defines `proposal_ratio(law, state, move)`. For the standard law
    it is a local neighbour-count ratio.
  - It must cost nothing when unused (the same criterion as D-051 item 2) and work on
    sequential and checkerboard sweeps (D-051 item 5); the ratio is local.
- **Validation:** a known-answer test against the exact Boltzmann distribution, by
  enumeration on a tiny lattice with a pure-energy model. `MetropolisHastings()` must
  reproduce it, and the measurable deviation of plain `Metropolis()` is documented.
- **Timing:** built with R10 (proposal laws), not before.

## D-053 Remaining review answers and agent-driven development (2026-09-30, maintainer)

**Review questions 6–10** (`research/feature-roadmap-review.md` §7): the reviewers'
recommendations are adopted.
- **6. Liveness.** Explicit cell liveness (`alive`, separate from `volume > 0`) is a new
  decision that amends D-035 (id reuse picks dead ids) and D-037 (dead cells contribute no
  energy; empty live cells keep E(volume = 0)).
- **7. Claims.** Cell references widen checkerboard claim sets automatically. Sequential is
  the reference for reference-reading energies, and checkerboard must still be exact under
  the widened claims (D-051 item 5).
- **8. Uptake.** The uptake/secretion operator split runs once per MCS: exactly
  conservative, lagging within the MCS.
- **9. Boolean networks** are MTK discrete-time (clocked, `Shift`) components, per the
  SciML-first rule. A helper that expands a truth table into one is sugar.
- **10. Float32 moments.** On Metal, Float32 moment after-values must agree with the CPU
  statistically (D-029), not bitwise.

**Development mode** (AUTONOMY §7):
- One coordinator session runs a self-paced loop over the ROADMAP Phase 6 queue.
- Implementer agents work in separate git worktrees, two or three at a time. Suites that
  use the GPU run one at a time.
- A separate reviewer agent with a fresh context must approve every diff before it merges
  locally into `monorepo`.
- **Checkpoints:** the maintainer is asked only for the AUTONOMY §3 escalations, a science
  question that no oracle or spec settles, and at the end of each phase.
- **Mandatory safeguards:**
  - acceptance tests are frozen before implementation;
  - a performance gate against a stored baseline;
  - the adversarial reviewer.

## D-054 P6.0a acceptance fixture: free-cell division threshold (2026-09-30, coordinator)

The frozen P6.0a test (`acceptance/p6_0a_division_kinds.jl`) gated free-cell division on
`volume >= 20`. With V₀ = 25, λ = 1, J(free, medium) = 16 and T = 10, a corner copy into
the medium gains about 32 in contact energy for 1 in volume energy. The free cells
therefore shrink to 19–21 by the time the rule first runs, which is after the sweep of
MCS 2. Only some of them divided: 3 of 3 stayed whole on checkerboard, 1 of 3 on
sequential.

This was a mistake in the fixture, not in the implementation and not a science question.
The threshold is now `volume >= 12`. With that change the implementation (`beba0a5`)
passes all 15 checks on both algorithms, and the unchanged tree still fails on the old
"either cells or clusters" error.

The rule for fixtures: a frozen test's division or transition trigger must hold with
margin in the state the rule actually sees. This is the post-sweep state (AUTHORING
§12.7), not the initial state.

## D-055 Cell and cluster division per rule domain (2026-09-30, P6.0a; amends D-036)

1. Each `@divide` rule divides by its own domain, all in one lifecycle pass:
   - `cells(k…)` divides the cell alone;
   - `clusters(k…)` divides the whole cluster of a root of kind k.
2. A kind may be divided by only one domain. Naming it in both a `cells(…)` and a
   `clusters(…)` rule, including the bare forms, is an `ArgumentError` at `mtkcompile`,
   and the message names the kind.
3. A cell divided alone behaves as follows:
   - A member of a multi-cell cluster divides alone, and its daughter joins the parent's
     cluster (for example a nucleus dividing inside its cytoplasm).
   - A lone cell's daughter is a lone cell. Before this, the daughter joined the parent,
     which made a 2-cell cluster.
   - "Lone" is decided by the members alive at planning time. A cytoplasm whose nucleus
     has died therefore divides into two clusters (reviewer's note).
   - Cluster membership is runtime data, so the choice could not be a compile-time error.
4. A dividing cluster takes precedence over its members' own cell divisions in the same
   MCS.
   - Clusters get daughter ids first, in root order, then cells.
   - When capacity cannot fit a cluster, only the root's event is deferred. Its members'
     own `EVENT_DIVIDE` may then use the remaining slots.
5. CorePotts: `EVENT_DIVIDE_CLUSTER` plus the `Lifecycle` keywords `cluster_normal` and
   `cluster_divide!` replace `Lifecycle(; clusters = true)`, which is removed. One
   representation, not a flag and an event code.
6. Division planes: the rules within one domain share one plane, and the two domains may
   differ.

## D-056 The random-box layout is `Scattered`, not `Scatter` (2026-09-30, coordinator; P6.1a)

- **The clash.** Makie exports a `Scatter` plot type. With `using Potts, CairoMakie`, as
  every reproduction tutorial does, a bare `Scatter` is ambiguous and so undefined.
- **The decision.** The layout is `Scattered(n, size; region, kinds, seed, gap)`, a noun
  that parallels `Tiling`. The frozen P6.1a test is amended to match; nothing else in it
  changes.
- **The rule for future public names:** check them against the exports of Makie,
  SciMLBase, ModelingToolkit and Graphs before a surface is frozen.

## D-057 Layout library: values, one extension method, and lattice-aware semantics (2026-09-30, P6.1a)

- **Layouts are host-side values.** Each is a subtype of `AbstractLayout` with one
  method, `paint!(σ, kinds, l, lat::LatticeSpec)`. The method sees the current `σ`, so
  `InsertUntil`, "avoid existing cells" and splits fit as one method each.
- **Public extension API:** `paint!`, `LatticeSpec` and `core_lattice`, together with the
  CorePotts public names `shift`, `relation` and `embed`.
- **`layout(l, x)`** returns `[ownership => σ, kind => kinds]`. `x` may be one of:
  - dims, meaning a closed square lattice with Moore(1);
  - a CorePotts `Lattice`, assumed Moore(1);
  - a `LatticeSpec`, a `PottsSystem` or a `CompiledPottsSystem`.

  Pass the system for hexagonal, periodic, domain or non-Moore lattices. Coordinates are
  lattice indices, axial on hex.
- **Randomness.** Every random layout owns its seed (`StableRNG`, `UInt64`), so adding a
  layer never changes another layer's draws. StableRNGs is a Potts dependency.
- **`overlay(layers...)`:**
  - later layers overwrite earlier ones, and ids follow layer order;
  - fully covered cells are dropped and the rest renumbered;
  - a cell left disconnected under the lattice neighbourhood gets a `@warn`, from a check
    that is linear in the lattice size.
- **`Scattered`:**
  - the gap is Chebyshev, measured both ways round periodic axes;
  - boxes stay inside the region;
  - an area bound gives an early error;
  - random sequential placement can jam near half of the densest packing, so a feasible
    dense request can throw.
- **`Tiling`** drops trailing boxes that would come closer than `spacing` to the first box
  through a wrap.
- **`Frame`** walls only closed axes, so on (Periodic, Closed) it is one frozen cell made
  of two walls. It throws when every axis is periodic.

## D-058 Several relationships per model; shared read claims on checkerboard (2026-09-30, P6.0b; amends D-036)

1. **Relationships.** A model may declare several named `@relationship`s. Each has its own
   adjacency (`links__<name>`), capacity, edge variables, `edges(name)` terms and
   `@link`/`@unlink` rules, and initial pairs are given per name (`:bond => [(1, 2)]`).
   - Edge variables are scoped by relationship, as in `rest(bond)`.
   - An unscoped `x(edge)` binds to the declaring body's only relationship when that body
     is built, before `@extend` merges. It remains an "ambiguous" error only in a single
     body that has several relationships.
   - An edge term or rule reads only its own relationship's edge variables.
   - A relationship may not be named after a scope.
   - Payload values in empty link slots are unspecified: `add_link!` zeroes the payloads it
     is not given.
2. **Claims** (amends D-036's exclusive `link_claims`). `CPMFunction(…; reads)` declares
   cells that a copy reads but does not write. Link partners of relationships with edge
   energies are reads.
   - Each accepted copy raises `claim` on every cell it touches (old, new, claims and
     reads) and `wclaim` on the cells it writes.
   - It commits only if it holds the top `claim` on every cell it writes, and no
     higher-priority copy writes a cell it reads (`wclaim ≤ own priority`).
   - **Exact:** no committed copy's ΔH saw a cell that another committed copy changed. A
     reviewer brute force of 200k trials found no violations, and the tests kill five
     kernel mutations.
   - Readers share. Exclusive partner claims serialised linked chains and slowed
     relaxation: bond distance at 1000 MCS was 15.2, against 13.5 with shared reads and
     11.9 sequential. Equilibria agree within error (16 seeds × 10k MCS).
   - Sequential ignores claims, as before.
   - Models without reads keep the old kernel path, via a type-level switch.
3. **Storage.** Link columns stay flat in `st.cell`, so capacity growth, division,
   checkpoints and device adapt keep iterating flat arrays. Generated code builds a
   zero-cost NamedTuple store view per relationship.
4. **Zero cost when switched off (P6.0b3).** A feature that is off must pass `nothing` to
   device kernels, not a placeholder array. Two dead length-1 buffer arguments cost 3 % on
   Metal, even though the kernel bodies were identical. The A/B against 5258ab9 now gives
   akeeb 0.993, openvt 0.996 and merks 1.001.


## D-059 papers.jl anneals each Graner–Glazier regime under its own Hamiltonian (2026-09-30, coordinator; P6.1b2)

- **The bias.** The frozen `papers.jl` measured every regime on a copy annealed at T = 0
  under the default sorting J. The partial-sorting, checkerboard and reversed-layer runs
  were therefore annealed under a Hamiltonian that was not theirs. The P6.0h reviewer
  measured a bias of 0.005–0.01 toward the effect being tested.
- **The fix.** `anneal(σ, pars)` takes the run's own parameters, with T overridden to 0, as
  PRE §II D2 describes. The measurement helpers pass `pars` through.
- **The check.** All 12 GG checks still pass.

## D-060 P6.1b2 acceptance fixture: a variable shadowed `Base.all` (2026-09-30, coordinator)

- **The bug.** In the frozen `acceptance/p6_1b2_gg_aggregate.jl`, `unlike = all = 0` made
  `all` a local of the testset body. That shadowed `Base.all`, so the file's first `@test`
  threw an UndefVarError on every implementation.
- **The fix.** The variable is renamed `nall`. No target or tolerance changes.
- **The lesson.** Before freezing, the coordinator runs the test file against a stub of
  the API it names, not only against the unchanged tree (where it errors at the first
  undefined name). This catches errors in the fixture itself. AUTONOMY §7.2 is extended to
  require it.

## D-061 Contact energies read site values: `x` and `x′` (2026-09-30, P6.0e)

1. **Naming.** In a `contacts`/`contacts(relation)` term, a bare site or field variable `x`
   means `x[site]`, and `x′` means `x[site′]`.
   - `@variables` binds `x′` for every site or field variable, and `@extend` binds it next
     to every bound site or field name. `lookup(sys, :x′)` resolves it.
   - `_symmetrize` mirrors `site ↔ site′`.
   - `x′` exists only in contact terms. The name is reserved: declaring a quantity named
     `x′` alongside a site or field `x` is an error, in a model body or through `@extend`.
2. **On-copy writes (extends D-045).** A contact pair that includes the target reads the
   value written at the target on copy.
   - `clear_on_ownership_change` counts as an on-copy write for every energy, contact and
     site terms alike, so ΔH uses the default at the target.
   - An on-copy write at the source is rejected for any energy that reads the variable.
3. **Population folds** inside contact terms are neither placed at the pair nor mirrored.
4. **Claims.** Reading `x` at `s′` stays within the contact radius, on sites whose `σ` the
   pair already reads, so no new checkerboard claims are needed. The reviewer confirmed
   this empirically on square, hex and Metal.
5. **Also fixed:** a model with two site terms broke ΔH, because the site-term loop
   reassigned `after`.

## D-062 Frame on a domain lattice (2026-09-30, P6.1a2; addendum to D-057)

On a lattice with a domain mask, `Frame(kind; width)` owns every in-domain site within
Chebyshev distance `width`, in index space and through the wrap on periodic axes, of an
out-of-domain site or a closed lattice edge. A domain frame that would be empty throws
"the domain has no boundary".

- **Why Chebyshev.** It reduces exactly to the unmasked rule, and it equals Moore(1) graph
  distance on square lattices.
- **Hex.** Chebyshev is conservative there: Hex(1) ⊂ Moore(1), so the ring always seals.
  - The reviewer checked it against an independent BFS oracle: 400 trials, 0 mismatches.
  - It is also tested on a concave hex domain and on 40 random 3D masks.

## D-063 Paper-size Graner–Glazier start: a centroidal Voronoi disk without relaxation (2026-09-30, P6.1b2)

- **The generator.** `graner_glazier_aggregate(n; seed)` is `VoronoiBall`: a centroidal
  Voronoi disk of area 40n with 30 Lloyd iterations.
  - Kinds are exactly equal (±1) and randomly placed, which spec 09 §8.4 A-GG5 allows.
  - There is no Potts relaxation. The reviewer measured heterotypic fractions within 0.005
    of a paper-relaxed start at 1, 10 and 100 paper MCS (6 seeds).
  - The area spread is SD 7.6, against 1.6 relaxed. This is stated in the docstring.
- **Connectivity.** `VoronoiBall` cells are connected under the geometry's nearest-neighbour
  steps, derived from `embed`. That is stricter than the lattice neighbourhood.
  - Stray pieces join the neighbouring cell whose largest piece they touch most.
  - A cell's largest piece never moves, so no cell vanishes.
- **Reproducibility.** Each FULL replicate of reproduction 09 draws its own aggregate
  (`seed = replica`).


## D-064 ExplicitImports in every package; Potts keeps the bare `using CorePotts` (2026-09-30, P6.0j)

- **Checks.** The QA of Potts, CorePotts and MakiePotts runs five ExplicitImports checks:
  no implicit imports, explicit imports are public, no stale explicit imports, qualified
  accesses go through owners, and qualified accesses are public.
  - The first four are the acceptance checks. The public-access check runs with a reviewed
    allowlist, and every allowlist entry is commented.
  - The Potts QA loads DynamicQuantities, so `PottsDynamicQuantitiesExt` is always checked.
- **The bare `using CorePotts`.** Potts keeps it, because the loop over `names(CorePotts)`
  re-exports each name, and every name must resolve inside Potts.
  - Every CorePotts name that Potts itself uses is also imported explicitly.
  - The reviewer checked that removing one from the explicit list fails
    `check_no_implicit_imports`, so the bare `using` hides nothing.
- **Owners.** Qualified accesses go through the modules that own the names:
  `SymbolicIndexingInterface.getname`, `Symbolics.rename`, and `TermInterface.maketerm` and
  `TermInterface.metadata`.
  - Each is the same function object as the old path, so behaviour is unchanged.
  - TermInterface is a weakdep and a second trigger of `PottsDynamicQuantitiesExt`. It is
    always loaded through SymbolicUtils, so the extension loads with DynamicQuantities alone.
- **Allowlists match names, not modules.** A future non-public `Foo.zeros` would pass
  silently. Reviewers check new entries by hand.
- **Deferred.** Declaring CorePotts's hooks `public` would shrink the Potts allowlist. It
  is not done yet.

## D-065 Maintainer answers to review questions 6–10 (2026-09-30, maintainer; amends D-053 items 6, 7 and 9)

The maintainer gave these answers in the coordinator session on 2026-09-30. They replace
D-053 items 6–10 where the two differ.

- **Q7, cell references and claim sets: approved, and relaxed.**
  - Sequential is the reference for every energy that reads a cell reference.
  - The checkerboard sweep is validated **statistically** against sequential, as for Y2.
    This replaces D-053 item 7's requirement that the checkerboard stay exact under
    widened claims. Widened claims remain the implementation route, but exactness is no
    longer an acceptance criterion.
- **Q8, uptake split: approved.** The split runs once per MCS (D-053 item 8, unchanged).
- **Q10, Float32 moments on Metal: approved.** Statistical agreement with Float64 (D-029;
  D-053 item 10, unchanged).
- **Q9, Boolean networks: MTK, with no Potts helper.**
  - Boolean and discrete networks are MTK discrete-time (clocked, `Shift`) components,
    extending D-038, with a well-tested lowering into the per-cell phases.
  - **No Potts truth-table expansion helper is built**, which withdraws the "sugar" clause
    of D-053 item 9.
  - Where MTK's discrete support is not usable yet, record the gap and the workaround in
    DECISIONS. Do not design around a Potts-only representation.
- **Q6, explicit liveness: follow standard CPM behaviour, where performance allows.**
  - First survey CompuCell3D, Morpheus and Artistoo: when a cell counts as dead (zero
    volume, explicit removal), whether ids are reused, and how dead cells are excluded from
    energies and populations. The survey is `research/liveness-survey.md` (P6.5a0).
  - Then adopt that behaviour as a new decision that amends D-035 and D-037 and says
    exactly what changes. It replaces the specific semantics of D-053 item 6.
  - Keep our faster mechanism wherever the standard behaviour would cost measurable
    warm-MCS time or allocations, as measured by the performance gate. Record each such
    deviation.
- **Author letters:** the maintainer authorised fetching every openly available source
  on the pre-send checklist from legitimate public sources, with no paywall
  circumvention. The resolved HOLD questions are then dropped or narrowed (P6.0i2). The
  maintainer still sends the letters personally.

## D-067 C7 and X5 changed on new source evidence (2026-09-30, maintainer approved)

The P6.0i2 pre-send checks read sources that were not available when the §4 decisions were
approved. The maintainer approved both changes in the coordinator session on 2026-09-30
("theyre approved").
- **C7, chemotaxis direction (14a, 14c).** Follow the code: the term applies to both
  extension (FRONT → Medium) and retraction (Medium → FRONT), with the same formula.
  - Evidence: CC3D's default `merks` chemotaxis algorithm is used by both codes, which set
    no `<Algorithm>`. See CC3D 3.6.2 and 3.7.9 `ChemotaxisPlugin.cpp`, spec 14 §2.9.4.
    14c runs on CC3D 4.2.3, which was not checked but is very likely the same.
  - The paper's extension-only Eq 7 is a variant.
  - Previously: Eq 7, FRONT → Medium only.
  - The authors are still asked about it (the de Almeida letter, as a provenance question).
- **X5, HMR core model (08 FBCA).** The published Di Filippo 2016 supplementary `mmc1.xls`
  is the default, flagged. It has 274 reactions (272 without `biomass_synthesis` and
  `Ex_biomass[s]`) and 252 metabolites, against the papers' 272 × 240.
  - The authors are asked how they counted.
  - Previously: blocking until obtained.
- **Author-question letters.** They are local, untracked files (`.gitignore`), per the
  maintainer's decision relayed verbatim by the models-and-publications session: "leave
  them as uncommitted references in the local repo". The maintainer chose untrack over
  rewriting history. Commit 6ec712a still contains batch 1.

## D-066 Cell liveness is the standard CPM one: alive ⇔ owns a site (2026-09-30, P6.5a; maintainer signed off 2026-09-30 on X2 and on dropping retain_empty; amends D-035, D-037; replaces D-053 item 6's semantics)

Survey: `research/liveness-survey.md` (CompuCell3D 3.7.9/4.9, Morpheus 2.4.1, Artistoo).
D-065 Q6 authorises adopting the standard behaviour and keeping our faster mechanism
where the standard costs measurable warm-MCS time or allocations. The maintainer confirms
only the **need-based** items: X2, and dropping D-053 item 6's `retain_empty`/explicit
liveness.

Standard: a cell dies at once when it loses its last site or is removed; a dead cell
leaves every energy, population, iteration, link and plot; the last-site copy pays the
full volume ΔH; there is no "dead but present" state.

1. **Alive** ⇔ the cell owns at least one site: `alive(c) ≡ volume[c] > 0`. `alive` is a
   read-only built-in.
   - **Birth** happens in one of three ways:
     - the initial state;
     - a division daughter that receives at least one site;
     - `@create`/`@convert` (R8), which allocate and paint in one host routine.
     A daughter or created cell that receives no site is not born, and its slot stays
     free.
   - **Death** happens when a copy takes the last site (at once); when a lifecycle rule
     removes the cell (its sites go to medium or to `ref`); or when a conversion takes its
     last site. Death is terminal for (slot, generation).
   - There is no dying state and no empty-but-alive state. Morpheus-style shrinkage is a
     `@transition` to a kind with V₀ = 0 plus `@remove … when volume <= n`.
   - D-053 item 6's `retain_empty`/explicit liveness is dropped (need-based: no model
     needs it, and it would change Fortuna's results; survey §5).
2. **Deviations** (survey §4.1):

   | # | Standard | Ours | Kind | Reason |
   |---|---|---|---|---|
   | X1 | Monotone ids | Slot reuse + `generation`; monotone `birth` shown to users | Performance, measured | A dead slot costs ≈ 3.0 ns/MCS (checkerboard), ≈ 1 ns (sequential). Akeeb at 16× capacity: +16.3 % / +5 %. Every capacity growth allocates in a warm MCS |
   | X2 | Unpainted live cells (created cells, empty division children) | None: created and divided cells must receive a site to be born | Need-based, unmeasured; **signed off by the maintainer 2026-09-30** | Keeps liveness = site ownership, with no flag or emptiness checks. The only reference-model occurrence is Akeeb's seeding artefact |
   | X3 | Links dropped at the killing copy (CC3D FPP) | Dropped at the next boundary; dead partner skipped meanwhile | Performance, unmeasured | A drop in the sweep is a hot-loop write that races on the checkerboard. No energy effect |

   The total-H convention (item 4) is not a deviation: no tool has a total H.
3. **Ids (amends D-035).**
   - **Slots.** Reused lowest-first, with `generation` incremented. A slot is free when:
     - it is not alive;
     - it had no event this MCS;
     - it is not the root of a cluster with alive members (as now).
   - **`id`** in model expressions stays **the slot**: the `:cell` index sort, so `x[id]`,
     the cluster env's `:id => r`, and `cluster == id` are unchanged.
   - **`birth`** is a separate read-only built-in: a monotone, never-reused Int32 serial.
     - Its counter `next_birth` is stored in the state and checkpointed. It is not max+1,
       which would reissue a dead cell's serial.
     - Initial cells get 1:n.
     - The allocator (lifecycle plan and R8 routine) assigns `next_birth` and increments
       it.
     - `birth` is excluded from the daughter column copy (`lifecycle.jl:336-339`, like
       `generation`).
     - `with_capacity` grows it (new slots 0).
     - Models without births have no column (`birth ≡ slot`).
   - **User-visible outputs map slot → `birth`:**
     - observables and SII `id`;
     - `cluster`, as `birth[root]`;
     - plots and id-based tracking;
     - PIFF export (`write_piff(…; ids = birth)`).
   - **Saved solutions** store σ with slot ids and save the `birth` column alongside it
     (4 × capacity bytes per save, no per-site work). The σ → birth map is applied lazily
     on read, at O(sites) per accessed frame.
4. **Energies (amends D-037).**
   - ΔH is unchanged. The last-site copy pays the full cell-term change to the empty state.
   - `total_energy` sums:
     - cell terms over alive cells;
     - cluster terms over roots `r` (`cluster[r] == r`) of clusters with at least one
       alive member (a copy-killed root still names its cluster until `_fix_clusters!`);
     - edge terms over links whose two ends are both alive.
     A dead cell contributes nothing.
   - **Self-check**, for a copy whose old owner `o` it kills:

         ΔE(copy) == H(after) − H(before) + E_cell(o, empty state)
                     [+ E_cluster(cluster[o], empty state), if that cluster has no alive member left]
                     + Σ_{n linked to o} E_edge(o, n; d(centroid_o before the copy, centroid_n after the copy))

     - "Empty state" is o's tracked quantities after the copy (volume 0, surface 0, …).
     - The edge credit exists because `centroid_shift` returns 0 for a cell going to V = 0
       (`geometry.jl:146`). `link_delta` therefore leaves o's edges at o's pre-copy
       centroid, while H(after) drops them.
     - The check stays exact.
5. **Folds, geometry, contacts, links, references.**
   - Folds, counts, cell ODEs and updates, triggers, observables and plots range over
     alive cells (unchanged: `volume > 0`).
   - Centroid, position, shape and `major_length` are 0 for dead slots (unchanged).
   - The contact graph is built from σ.
   - **References** are cell variables of a declared reference type (e.g. `partner::CellRef`
     in `@variables`), so the allocator can find them.
     - Daughters copy reference variables like every other cell variable. A `divide!` rule
       may reset them.
     - Dereferencing a dead referent reads as `ref = 0`: kind 0 (medium), volume 0, cell
       variables at their defaults. It costs one `volume[ref]` load and a select, in
       reference-reading code only.
     - So `J[kind, kind[partner]]` silently uses the medium row once the partner is dead.
       Guard with `alive(partner)` where that matters.
   - **Links:** `link_delta` and `total_energy` skip a partner with `volume == 0`. This
     reuses `centroid`'s load and fixes the NaN freeze (P6.0l).
   - **Boundaries.** Dead cells' links are dropped, references to them are reset to 0, and
     dead roots are released:
     - (a) in the lifecycle plan of an event MCS;
     - (b) in R8's shared `@create`/`@convert`/`@retire` host routine (it runs every MCS
       in 14a);
     both before any id is allocated, so a reference never aliases a new cell;
     - (c) at the start of each `@link`/`@unlink` host phase, before links are created,
       so a stale degree or `linked` never blocks creation.
     A relationship with none of these never creates links; the skip suffices there.
6. **`no_extinction`** stays opt-in (D-037; CC3D and Artistoo). Morpheus's always-on veto
   would break the Graner–Glazier λ scan.
   - `no_extinction(k…)` forbids a copy that takes the last site of a cell of kinds k…
     (default: all cell kinds), i.e. `old == 0 || volume[old] > 1 || kind[old] ∉ K`.
   - Used by 10 and 13; offered to 05 and 07 (matrix, fluid); added by Morpheus ports.
   - AUTHORING §5 is corrected.
7. **Reproductions** (survey §5):
   - 14a: FRONT is created by `@convert` and dies when it empties, losing its target as in
     CC3D. The port counts FRONT deaths.
   - 14c: a LAMEL death ends the run.
   - 06: the first dying cell transitions into the necrotic-core kind.
   - 13: `no_extinction` on segments.
   - Spec edits: survey §5.

Why: the standard behaviours are already ours (immediate death, full ΔH, exclusion
through `volume > 0`) or free (the `link_delta` skip, `birth`, host-side cleanup). The one
measurably costly standard, monotone slots, is kept only in its user-visible form.


**Sign-off.** The maintainer approved both need-based items in the coordinator session on 2026-09-30: X2 (a cell must receive a site to be born) and dropping D-053 item 6's `retain_empty` and explicit liveness. The fallback `retain_empty` design stays in `research/liveness-survey.md` §6.2. Akeeb's seeding (V-A1) is handed to the P6.2b V-target audit.

## D-068 Akeeb seeding emulates the authors' CC3D code (2026-09-30, maintainer MD-1)

**Source.** The maintainer's answer, relayed verbatim by the models-and-publications
session from its spec 10 pre-freeze audit.
- The question was: "Akeeb's published runs started with ~382 real leaders + ~8 empty
  'ghost' cells; which should our default reproduce?"
- The answer was "Emulate authors (Recommended)", with this option text: "Default: count a
  missed draw toward the 390 quota without creating a cell (zero cost) — exactly what
  produced the published data. Keep today's retry (390 real leaders) as a variant keyword.
  Also fix the frozen test's issues the audit found (±50 divisions ≈ 4% false-fail; sim
  helper defaulting to μ=30)."

**Evidence.**
- In the authors' code, `CCIecmSteppables.py:68` calls `new_cell` on every draw, `:73–74`
  paint only on a follower pixel, and `:75` recomputes the ratio after a hit.
- A seeding-only simulation (20k repetitions) gives 7.9 ± 2.8 empty and 382.1 ± 2.7 painted
  leaders. The inventory is 390 in 96.1 % of repetitions.

**Decision.**
- `akeeb_state` by default counts a missed draw toward the leader quota without creating a
  cell. Under D-066 X2 a ghost is never alive, so it is not allocated at all.
- Today's retry, which gives exactly 390 painted leaders, stays as a variant keyword.
- The frozen `lib/PottsModels/test/papers.jl` Akeeb testset is edited under this entry:
  - the ±50-division tolerance, which fails falsely about 4 % of the time, is replaced by
    a band derived from the ensemble;
  - the sim helper's default μ becomes 24 (D-050 A5).
- The performance-gate Akeeb case is re-baselined in the same change.

## D-069 Finger detection: port SciPy 1.7 `find_peaks` from source, with no SciPy download (2026-09-30, maintainer)

**Source.** The maintainer's answer, relayed verbatim by the models-and-publications
session.
- The question was: "How should we get reference outputs [for SciPy 1.7 find_peaks]?"
- The answer was "No download: port from source", with this option text: "Port find_peaks
  from SciPy's BSD-licensed source and test against hand-built cases with known answers.
  No external download, but no independent oracle for exactness."

**Decision.**
- Port `scipy.signal.find_peaks` v1.7.x to Julia, reading SciPy's source as text, which is
  not an installation. The port covers:
  - `_local_maxima_1d`, with plateau midpoints;
  - `_select_by_peak_distance`, including its priority order;
  - `_peak_prominences` and `_peak_widths` with `wlen = nothing`;
  - the filter order distance → prominence → width.
- Carry the BSD-3 notice and attribution in the file.
- Then the authors' merge step: keep a peak only if it is more than 15 samples from the
  last kept one (spec 10 §5.3.3).
- **Tests.** Hand-built profiles with analytically known answers:
  - plateaus of even and odd width;
  - equal-height ties under the distance filter;
  - edge samples, which are never peaks;
  - prominence bases with nested peaks;
  - widths at `rel_height = 0.5` with interpolation;
  - the merge rule.
- **Consistency check.** On the authors' released sample data, where the CSVs allow it
  (spec 10 §5.3.4), our metric reproduces their per-run finger counts.
- There is no independent oracle for exactness. That is accepted.

## D-070 Per-rule `Every(n)`; the firing rule alone writes daughter state (2026-09-30, P6.0f)

- **Cadence.** Each lifecycle or link rule has its own cadence, given positionally as
  `Every(n)` or as `every = n`.
  - A rule fires when `mcs % n == 0`. MCS are numbered from 0 and are absolute under
    `remake`, as for `Every` on updates.
  - `Lifecycle.every` is the gcd of the rules' cadences, so the whole lifecycle pass is
    skipped on the other MCS.
  - Only a rule whose cadence differs from the gcd gets a `mcs % n == 0` gate, and its
    daughter state rules get the same gate. `Every(1)`, or a cadence shared by all rules,
    generates no gate.
  - `@link`/`@unlink` now accept a positional `Every(n)`, which they used to drop silently.
- **Several rules for one cell.** When division rules in one domain share a kind, rules
  are tried in model order, a base's before an extension's. The first rule whose
  cadence, kinds and `when` all hold divides the cell, and only its daughter state rules
  run.
  - CorePotts carries the firing rule's index in the event (`Lifecycle(…; rules = true)`,
    `ruled_event`: the event in the low byte, the index above it).
  - Only models with overlapping rules generate this. The others generate the same code
    as before; the reviewer compared canonicalised text for 6 models.
- **`extend`.** Division rules accumulate and are not replaced by target as updates are
  (D-045). An overlapping rule at a different cadence gives a warning, and both rules
  apply.
- **Deferred.**
  - The rule-carrying host plan allocates three temporaries per event MCS. Masking in
    place would avoid them. This is not a warm path.
  - SymbolicUtils operand order shifts with unrelated source edits, so the last bit of a
    float result can change between builds. This predates P6.0f and is tracked here.

## D-072 Reproduction 09 pre-registered: the tutorial page is frozen (2026-09-30, P6.1c)

- **What is frozen.** `lib/PottsModels/reproductions/09_cell_sorting.jl` is added to
  `frozen.toml`. Its pre-registered table (spec 09 §9.1) and verdict code can change only
  under a DECISIONS entry. This commit precedes the first FULL run.
- **CI-binding rows (SMOKE+FULL).**
  - V-GG6: the paired 2 SE rule, with the symmetric-J control.
  - V-PRE13(a): mean F_dM(10³) > 0.01.
  - NC1, three clauses: the size-free heterotypic share of cell–cell bonds, mean
    F_dl/(1 − F_dM − F_lM) at 10³ ≥ 0.40; mean F_dM ≥ 0.01; 0 engulfed.
  - The NC1 clause of V-PRE3(a): F_dM(10³) ≥ 0.01.
- **FULL-only rows.** All other §9.1 rows, including V-PRE3(a) itself. **Parked:** V-PRE6,
  V-PRE17, V-OS3 and V-OS4, plus the ⟨n⟩/μ₂ clauses. **Superseded:** V-GG1–5.
- **Rulings.** These are spec-owner rulings, relayed by the models-and-publications session,
  with calibration by the coordinator's agents.
  - **V-PRE3(a)** is FULL-only. The size-free smoke form failed calibration: on seeds
    1001–1020 the 20-seed mean first drops below 0.1 at the 640 save, and 3 of 5 four-seed
    sets fail "by 500".
  - **NC1** became size-free, because the raw F_dl ≥ 0.35 failed one four-seed set in six at
    64 cells. Calibration on seeds 7001–7024: the six four-seed means are 0.442–0.500, and
    the per-seed values are 0.472 ± 0.051.
  - **Aggregate margin** stays at 10 (`graner_glazier_aggregate(n; seed, margin)`). At
    n = 6 the largest difference from a doubled lattice is 1.10 SE. Dispersal runs
    (V-PRE14/15) need a margin of at least 60.
  - **V-PRE16** is checked in `data/graner/generate.jl`, with a 2 % drift rule on annealed
    copies. It is not part of CI.
  - **Time.** Verdicts are taken at the paper's nominal times, with no time tolerance. The
    global scale s ∈ [½, 2] is information only.
- **Review.** Three rounds (two adversarial reviews plus a coordinator check). The spec owner
  ratified the page.

## D-071 Akeeb adhesion check: mid singles `> 0`, not `>= 2` (2026-09-30, coordinator; P6.2c)

- **The failing check.** `lib/PottsModels/test/papers.jl:158` asserted
  `mean(weak singles) > mean(mid singles) >= 2`. Under D-068's μ = 24 default it fails
  every time on seeds 1:4: mid singles are [2, 0, 2, 0], mean 1.0.
  - It fails in 2 of 10 disjoint four-seed groups (seeds 1:40).
  - The old retry seeding fails it at μ = 24 as well (mean 1.5), and at μ = 30 one group
    in ten failed.
  - So the fragility comes from the μ default, not the seeding. The `>= 2` floor sat about
    0.4 SD below the mid mean of about 2.4.
- **Change.** The check becomes `… > mean(mid singles) > 0`. It keeps the paper's
  ordering: strong adhesion gives no single-cell escape (0 on 40 of 40 seeds), mid gives
  some, and weak gives more (weak > mid in 10 of 10 groups).
  - With four seeds, P(all mid zero) ≈ 2e-4 from the ensemble.
- **Frozen file.** Edited under this entry; its `frozen.toml` decision is D-071.

## D-073 `InsertUntil` and `PottsModels.Analysis` (2026-09-30, P6.2a; addendum to D-069)

- **`InsertUntil`** is a host-side layout layer in Potts, exported together with
  `layout_tally`. It is not DSL.
  - A hit needs a live owner that was painted before the layer, with a kind in `into`.
    Cells the layer inserted are never hit again.
  - `N` and `K` are live counts: a hit that takes a cell's last site removes that cell.
  - The stop rule is checked before the first draw and after each hit only. So under
    `misses = :count` it overshoots by trailing misses, as CC3D does.
  - It throws when the allowed sites run out, instead of looping forever.
  - Draws use `StableRNG(seed)`.
  - Pass a `Rational` `fraction` to emulate a script's ratio loop exactly.
- **`PottsModels.Analysis`** is a public submodule under D-051 item 6, not a separate
  package. It holds:
  - the D-069 `find_peaks`, `peak_prominences` and `peak_widths` port, with SciPy's and
    NumPy's BSD notices;
  - `merge_peaks`, `column_tops` and `trapz`;
  - `cell_graph`, built on `CorePotts.contact_graph`;
  - `reachable`, `components` and `centroids`.
- **Exactness.**
  - The distance-filter tie order follows NumPy 1.21 `aquicksort`, including its heapsort
    fallback. NumPy's quicksort is unstable once there are 17 or more elements, and Akeeb
    profiles have 37–47 local maxima.
  - The reviewer found 0 mismatches against the real SciPy 1.7.3 / NumPy 1.23 code already
    cached on the machine (nothing was downloaded): 8000 `find_peaks` cases and 948 argsorts.
  - Widths match non-FMA SciPy builds bit for bit. The arm64 SciPy build fuses one
    multiply-add, so 539 of those 8000 cases differ in the last bit.
  - `trapz` sums sequentially, which is exact for integer profiles.
- **Author data.** On the authors' four stored profiles we reproduce their finger counts
  (12/12/0/0) and areas exactly. Their released data has no lattice snapshots, so the
  cluster metrics cannot be checked against it.

## D-074 `connectivity(k)` matches CC3D: a copy must leave exactly one component (2026-09-30, maintainer)

- **The defect.** `connectivity(k)` accepted 0 components, so a copy could take a cell's
  last pixel or fill an isolated fragment. The API-synthesis review confirmed this with a
  script.
- **The standard.** The authors' CC3D rule rejects any copy whose result is not exactly
  one component (`!= 1`). The shipped Akeeb model therefore allowed copies that CC3D
  forbids.
- **Decision (maintainer, coordinator session, 2026-09-30, "Match CC3D").** The
  constraint rejects any copy after which a constrained cell is not exactly one connected
  component. That includes taking its last pixel, so a connectivity-constrained cell
  cannot die by copies. This is consistent with D-066, where liveness is unchanged: such
  a cell simply cannot lose its last site under this constraint.
- **Frozen tests.** The frozen Akeeb tests in `papers.jl` are revalidated under this entry
  in P6.0m.

## D-075 The target API (api-synthesis round 3) and its breaking batch (2026-09-30, maintainer)

- **Source.** `research/api-synthesis.md` at round 3, written by the spec-owner session
  and reviewed adversarially three times by the coordinator's reviewer. Round 3 was
  approved for ratification with no blockers (`/tmp/api-synthesis-review-r3.md`).
  The spec-owner session asked the maintainer "How do you want to ratify the nine §8.1
  answers of the API synthesis?" and relayed the answer verbatim: "Ratify all nine
  (Recommended)". The chosen option was: one decision entry for the whole design and its
  breaking batch, built inside the existing Phase 6 steps, with the reviewer's should-fixes
  as acceptance text.
- **§8.1 answers adopted.**
  - **Q1.** The model's default law and its physics live in `@sweep` (`Metropolis`/`Barker`).
    `MetropolisHastings()` is algorithm-only, as in D-052; `@sweep MetropolisHastings` is an
    error. Precedence is `_law(alg, f)`.
  - **Q2.** Rename `CPMProblem → PottsProblem`. The supertype stays `AbstractSciMLProblem`;
    it is not a DE problem. `SciMLBase.isdiscrete(::AbstractPottsAlgorithm) = true`.
  - **Q3.** No `Wall(kind)`. The frozen frame stays, and the ≈ 4 % null-attempt deviation is
    recorded (01), optionally corrected with `attempts`.
  - **Q4.** Units stay check-only (D-039). A documented `lattice_units` helper goes in
    `reproductions/`.
  - **Q5.** The coarse-grid clamp default is `All()`, with `Any()`/`Majority()` one keyword
    away. P6.11 sweeps it in T10, and it is an author question for Jiang.
  - **Q6.** `components`/`Global()` runs on the checkerboard. A deferred windowed-BFS
    kernel works through a compacted list of local-test failures. Beyond the window it
    rejects conservatively and counts the rejection. A late-state benchmark is the gate.
    `window` is on `components`/`Global()`, not `connectivity(k)` (D-074).
  - **Q7.** The `@on_copy` neighbour-target scatter uses a declared write footprint.
    Sequential lands first; the checkerboard form (4 → 9 colours in 2D) comes second,
    behind the interim D-051 item 5 exception.
  - **Q8.** `a` and `b` are reserved globally; the error suggests `a₀`/`b₀`.
  - **Q9.** One breaking batch with no aliases (D-028 precedent), landed across P6.0m/P6.0m2
    and P6.0c.
- **Amendments** (the §6.1 table is authoritative for the wording):
  - **D-016:** the fingerprint also hashes the solver specification (`field_solver`,
    `ode_solver`, `solvers`, `track`), as a canonical spec string.
  - **D-031 F-1/F-2:** new streams `CorePotts.thinning` and `Potts.init.<var>`. A sub-cycle
    index goes into `draw`'s `local_index` slot and `_color_order!` when `attempts > 1`;
    `attempts == 1` stays bit-identical.
  - **D-032 / AUTHORING §12.2:** `centroid` is allowed in energies once R7 lands.
  - **D-035:** plus one device↔host round trip per declared host pass per firing, each a
    named `@schedule` phase.
  - **D-038:** "the problem's `ode_solver`" (default `ExplicitEuler()`).
  - **D-051 item 5:** time-boxed exceptions. `@on_copy` neighbour-target writes and
    `interfaces(k,k)` energies are sequential-only until P6.12/P6.7; `CheckerboardCPM`
    rejects such a model by name. Q6's per-model sequential fallback is covered here too.
  - **D-057:** `paint!(op::LayoutState, l, lat)`; every layer is rewritten in the same
    change.
  - **D-068/D-071:** Akeeb `clock`/`cue` become `at_init` expression defaults at P6.4a,
    with their own `papers.jl` re-baseline (separate from P6.2a2's StableRNG one).
  - **R4:** `components` is also a cell-scope built-in with an exact after-value.
  - **AUTHORING §6 / P6.0c:** `field_solver` (required when a field exists), `ode_solver`
    and a symbolic-keyed `solvers` map become `PottsProblem` construction keywords.
    They are compiled at the existing codegen point, removed from `@sweep`, and are not
    algorithm fields. `remake` is the override. `Adaptive(alg; abstol, reltol)` stays as
    the bundle; `ExplicitEuler(; substeps, lower)`.
  - **Clarify only:** D-052 (law versus correction), D-049 F-1 (proposal in
    `@relations`), D-051 item 2 (Bernoulli thinning on the checkerboard), and P6.5b
    (ownership hooks apply `clear_on_ownership_change` only; `@on_copy` never fires from
    the lifecycle).
  - **Unchanged, applied:** D-029, D-031 F-13 (`PottsStats` names stay), D-046 (`track`
    and `solvers` resolve in Potts; algorithms carry only run-time values), D-058 item 4,
    D-053 item 9 / D-065 Q9, D-066 item 5, D-074.
- **The breaking batch (Q9).**
  - `CPMProblem → PottsProblem`.
  - `field_solver`/`ode_solver` leave `@sweep` and become `PottsProblem` keywords, with
    the `solvers` map. Every Merks call passes `ExplicitEuler(substeps = 2, lower = 0.0)`
    explicitly, and a bare call is a construction error.
  - `track` becomes a construction keyword.
  - The D-016 fingerprint extension; checkpoints taken before it fail by design.
  - `Adaptive` kept as the bundle; `ExplicitEuler(; substeps, lower)`.
  - `a`/`b` reserved; the `Chemotaxis` `when` default; `connectivity` per D-074; the P6.0c
    and P6.5b rewordings.
  - Not in the batch: the `PottsStats` names.
- **New R-items:** R0b, R17 (initialization as the `at_init` host phase, first consumer
  P6.4a) and R18 (named terms). The widened or decided R-items are as in §6.2.
- **Build.** No new step order. §6.4 maps each primitive onto the ROADMAP row that first
  consumes it. The round-3 reviewer's should-fixes are acceptance text on those rows
  (P6.0c, P6.3a, P6.9 and P6.4b in ROADMAP).
- **Coordinator scheduling note.** §6.4 places the rename and `isdiscrete` in P6.0m.
  P6.0m's frozen test and implementation were already in flight, so they land as
  **P6.0m2**, immediately after P6.0m and before P6.0c.

## D-077 MTK discrete-time components (2026-09-30, P6.0k; extends D-038 and D-065 Q9)

- **What.** Boolean and discrete networks are plain MTK clocked Systems (`Shift`) in
  `@components`. There is no Potts helper (D-065 Q9).
  - Each node is a cell or model variable `name₊x`. A Bool node is stored as exact 0/1.
  - One fused phase runs per (scope, clock), after the ODEs and before links and the
    lifecycle. It runs only for live cells of the component's kinds.
- **Semantics: Jacobi.** Every component that ticks at an MCS reads every other
  component's, clock's, scope's and cell's pre-tick values.
  - Scratch slots `x__tick` are published after all ticks when there are several tick
    phases, or when a cell-scope rule reads another cell's slot (`at`/`gather`/`population`
    over a discrete slot). Otherwise slots are written directly.
  - Scratch costs about 45 ns per MCS on the fixture network, within noise on a whole MCS,
    with zero warm allocations.
  - Models without discrete components generate the same code as before (canonicalised).
- **MTK gaps and workarounds** (register: `research/mtk-discrete-components.md` §4):
  - **G1.** Full ModelingToolkit rejects clocked systems and replaces MTKBase's compiler.
    The weak extension `PottsModelingToolkitExt` compiles through MTK's
    `discrete_compile_pass` hook (`PottsDiscretePass(sys)`, re-entering MTKBase's
    `__mtkcompile`), with compat MTK 11.45 and MTKBase 1.77. `check_compatible()` checks
    the hook once per session. Slots are sorted by name, so generated code is identical
    with or without full MTK (pinned by `test/mtk_extension.jl`).
  - **G2.** No `ShiftIndex()`. Use `ShiftIndex(t, 0)` or `ShiftIndex(Clock(n·mcs_duration))`.
  - **G3.** MTKBase compiles `Sample`/`Hold` silently wrong, and hybrid systems are
    unsupported. `D`/`Sample`/`Hold` are rejected in a discrete component. Write two
    components coupled by `@equations`.
  - **G4.** No clock partitioning: one clock per component.
  - **G5.** `DiscreteProblem` throws for Bool unknowns or parameters. This is not on
    Potts' path; tests use hand-written tables.
  - **G6.** `DiscreteProblem` ignores the period. Potts reads `VariableTimeDomain`; the
    period and phase must be whole MCS, with 0 ≤ phase < period.
  - **G7.** Bool symtypes are not enforced by MTKBase. Bool leaves use `_nonzero`
    stand-ins, and a non-Bool rule for a Bool node is rejected.
  - **G8.** MTK initialisation is not run (it is ill-posed for Boolean maps). Nodes and
    lags need defaults or operating-point values.
  - **G9.** Asynchronous updating has no MTK form. Use a per-cell `rand()` coupling with
    `ifelse` rules.
  - **G10.** `x(k+1) ~ f(x(k))` is rejected. Write `x(k) ~ f(x(k-1))`.
  - **G11.** Array variables become one scalar slot per element (`name₊z_i`,
    `name₊z_i_j`), and duplicate slot names are an `ArgumentError`. Element lag slots have
    no default (as G8), and the operating point takes elements, not the array.
  - **G12.** Use `Clock(dt; phase)`; there is no positional phase.
  - **G13.** An indexed node read was Real-typed. A Bool node read at an index is now
    Bool-typed (`_nonzero(at(x, j))`).
  - **G14.** `Clock(n)` ticks one MCS later than `Every(n)`, because MTK clock time has
    t = 0 as the initial state. `Clock(n; phase = 1)` aligns them.
  - **G15.** An under-determined node surfaces MTK's `ExtraVariablesSystemException`. It is
    wrapped as "every discrete variable needs an update `x(k) ~ …`".
- **Review.** Three adversarial rounds; round 3 approved.
- **Follow-ups (P6.0k2):**
  - F1: `Pre` of a discrete node is rejected with a confusing message.
  - F4: the narrowed catch still relabels internal Potts `MethodError`/`BoundsError`.
  - F6: cosmetic double `_nonzero`.
  - Cell ODEs reading other cells' ODE state are Gauss–Seidel and race on the GPU (N3),
    as its own item.

## D-076 P6.0m semantics and the `a`/`b` re-freezes (2026-09-30, coordinator; implements D-074 and D-075 Q8)

- **Chemotaxis `when` (D-075).** `Chemotaxis(c; strength, response, kinds, when)` defaults
  to `when = (new != 0)`, so a retraction (where the medium gains) gets 0.
  - `when = true` means every copy, retractions included. Any other condition selects
    exactly its copies; for example, `old == 0` selects extensions only.
  - The gate is `isempty(kinds) ? when : (kind[new] ∈ kinds) & when`, so with `kinds`
    given, retractions stay 0 whatever `when` says.
  - The frozen `p6_0m_defects.jl` has a header comment that says "default `when = true`".
    This entry supersedes that comment. Its assertions already match D-075, so it is not
    re-frozen.
- **Connectivity (D-074).**
  - `connectivity(k)` (`rule = :local`) is `local_components == 1`, and CorePotts
    `locally_connected` is `old == 0 || local_components == 1`. Zero pieces (the last
    site, an isolated fragment) are rejected like two.
  - `rule = :arc_or_pair` keeps TST's `ConnectivityPreservedP` semantics
    (`ring_arcs <= 1 || ring_cells == 2`; zero arcs pass). D-074 covers the local rule
    only; changing Merks' ring rule is the maintainer's call.
- **`a`/`b` reserved globally (D-075 Q8, coordinator's reading of "globally").** No kind,
  parameter (vector and kind parameters included), structural parameter, variable,
  observed quantity, relation, relationship or component may be named `a` or `b`.
  - It is enforced in `@potts_model` (`_declare!`) and in the programmatic `PottsSystem`
    (inner constructor `_check_reserved_names`), which also covers `extend`, `_replace`
    and component flattening.
  - The error suggests `a₀`/`b₀`.
  - Component-internal names (`comp₊a`) and local bindings inside expressions are
    unaffected.
  - `src/precompile.jl` renames its site variable to `mark`.
  - Open nit: `@extend a = Base()` still binds a local `a`; it is harmless, because
    `_edge_scope` rebinds it.
- **Fresh integrals (D-042).** When an update block writes a variable of `x` bare, a read of
  `integral(x)` in that block sees the new values.
  - The integral is recomputed after the writing stage and before the next reader. A
    gated reader gets a gated refresh.
  - There is an end-of-block refresh when equations, the lifecycle, link rules, discrete
    ticks (D-077) or the temperature read it.
  - Integrals whose operands no update writes cost no extra pass.
- **Re-freezes.** Two frozen acceptance files declared kinds named `a`/`b`, which D-075 Q8
  now rejects. Both are re-frozen under this entry as pure kind renames: no count,
  tolerance, seed, run length or assertion changed. The review verified both.
  - `acceptance/p6_0f_rule_cadence.jl` (was D-053): kinds `a, b` → `ka, kb`. The new
    sha256 is `9bf38772…0821`.
  - `acceptance/p6_0a_division_kinds.jl` (was D-054): `:a` → `:ka` at line 72. Without
    this rename, the `@test_throws ArgumentError` would pass on the reserved-name error
    instead of on the division conflict it tests. The new sha256 is `438fff83…5544`.
  - The re-freeze commits follow the first fix commit, 9ddb3b3, rather than preceding it.
    9ddb3b3 does not yet reserve kind names, so each commit is green.
- **Akeeb.** The frozen `papers.jl` band was revalidated under D-074, and all checks
  passed:
  - band: 40/40 seeds, mean divisions 583.6 against 585.0 on base;
  - singles: 40/40;
  - motility: 12/12;
  - adhesion regimes: identical to base.

## D-078 P6.0c solver placement: the semantics settled in review (2026-10-01, P6.0c; implements D-075 AUTHORING §6, amends D-016 and D-038)

- **Placement.** `field_solver`, `ode_solver` and `solvers` are `PottsProblem` construction
  keywords. They are resolved in Potts (`_resolve_solvers` → `SolverSpec`, one solver per
  integrated variable, by name) and compiled at the one codegen point (`_problem_function`).
  - `@sweep` rejects them, and any unknown keyword. CorePotts algorithm types carry none
    (D-046).
  - `field_solver` is required when the model has an integrated field, even if `solvers`
    covers every field, and is an `ArgumentError` otherwise.
  - `ode_solver` defaults to `ExplicitEuler()`; `substeps = nothing` means 1 for ODEs. It
    is accepted, with no effect, on a model without ODEs.
  - A `solvers` key is a variable, a name, an MTK component variable (`comp.x` /
    `Symbol("comp₊x")`) or a component (all its integrated unknowns). A field key takes
    only `ExplicitEuler`.
  - Duplicate keys (including one given through a component), parameters and
    non-integrated variables are `ArgumentError`s.
  - `track` moves to P6.3a.
- **Several solvers stay Jacobi** (D-038, D-077). A scope's ODE unknowns are grouped by the
  solver's canonical string, one phase per group, in order of first appearance.
  - With one group, the phase writes directly and the generated code is unchanged.
  - With several, each phase writes scratch `x__ode`, and one `CopyPhase` per unknown
    publishes after the scope's last group. Every rate then reads the start-of-step value
    of its own cell's (or the model's) unknowns.
  - Cell groups publish before model groups run, and cross-cell reads within a group stay
    Gauss–Seidel (D-077 N3, P6.0n).
  - After-MCS order is unchanged: updates, then field steps, then cell ODEs, then model
    ODEs, then discrete ticks, then links.
  - `_ode_layout` adds or removes exactly the scratch slots. It is applied at
    construction, at a solver `remake`, and to every `u0` through `remake_state` (symbolic
    maps and `CPMState`s, in `remake` and `reinit!`).
  - Declared names ending in `__ode`, `__tick` or `__next` are rejected.
- **`remake`.** `remake(prob; field_solver | ode_solver | solvers)` goes through CorePotts
  `remake_function(f.sys, prob; kw...)`. The default is an ArgumentError naming the
  keywords.
  - Potts rebuilds `f` and re-lays out `u0`, keeping p, seed/replica/repeat (the RNG key)
    and the frozen mask.
  - `remake(prob; p | u0 | seed)` never regenerates code.
  - Cost on Merks 100²: about 0.3 s codegen plus 0.4 s JIT for a new spec, a few ms for a
    spec already compiled.
- **D-016, amended.** The fingerprint is `_code_hash` of every generated function, seeded
  by two strings:
  - a canonical structural string (lattice dims, boundaries, domain, geometry, spacing,
    neighbourhood and `T`, by content), never by `hash` of package structs, which falls
    back to `objectid`;
  - when anything is integrated, the canonical solver string: fully qualified types,
    primitives and ranges by `repr`, closures by their captures, sorted dicts, sets and
    kwargs. It depends on solver package versions.

  `_code_hash` strips all line numbers, including those inside macro calls. It reads
  `+`/`*` calls flattened across same-operator nesting, with operands in printed order:
  Symbolics' term order and grouping depend on the build and change rounding only.

  So the same source at another path or build fingerprints alike. The coordinator verified
  this at merge against a `git archive` copy, for 7 problems including Merks. Checkpoints
  from before P6.0c fail by design (D-075 Q9).
- **Adaptive.** The integrator's `p` is set before `reinit!`. Before, its initial-dt guess
  evaluated the previous cell's tuple on the CPU, and a stale host snapshot on a device.
  This changes CPU `Adaptive` trajectories within solver tolerance; Metal now matches the
  CPU exactly. Fixed-step results are unchanged.
- **Ensembles.** `solve(ens, ::CPMAlgorithm)` with no ensemble algorithm runs
  `EnsembleThreads` on the CPU and `EnsembleSerial` otherwise, forwarding `backend`. It is
  not piracy and adds no ambiguities.
- **Merks.** It needs `field_solver = ExplicitEuler(substeps = 2, lower = 0.0)`. Its results
  are bitwise unchanged: the five digests recorded on 1092ada match.
- **Review.** Three adversarial rounds.
  - Round 1 blocker: split solver groups were Gauss–Seidel.
  - Rounds 2–3 blocker: build-dependent fingerprints. The last residual, nested `+`
    grouping, was fixed by the coordinator with the round-3 reviewer's verified patch.
  - Follow-ups are in P6.0c2.

## D-079 P6.0l: links to a copy-killed partner (2026-10-01, P6.0l; implements D-066 item 5)

- **The skip.**
  - `link_delta` loads the partner's volume once. It skips the partner when the volume is 0, and otherwise computes the centroid from that same load (`_centroid`), so a race can never divide 0 by 0.
  - `total_energy` sums an edge only when both ends have volume > 0.
- **Boundary (c).** Each `@link`/`@unlink` host phase first drops every link of a volume-0 cell, before any condition is evaluated or any link created.
- **Boundary (a) is met by slot reuse.** The lifecycle plan clears the link rows of every daughter slot before any sweep, so a stale link never reaches a new occupant. Otherwise, links of a copy-killed cell persist, and are skipped, until a (c) boundary or reuse. The store is a fixed `maxdeg × capacity` matrix, so this does not grow it.
- **Checkerboard.**
  - Generated models claim link partners (`link_claims`), so there is no race.
  - A hand-written model without `link_claims` may read a racing partner's moments one colour stale, but never 0/0.
- **Open: D-066 item 4** (P6.0r).
  - Cell and cluster terms of `total_energy` still sum over every slot.
  - The killing copy's ΔH differs from the H difference by exactly item 4's edge credit (reviewer probe: 4.56 and 146.55, error ≤ 3e-14). Copies after the death match exactly.
  - The self-check helpers do not credit it yet.
- **Unchanged code.** The generated code of the six published models is unchanged once operand order is canonicalised (D-070).
- **ROADMAP correction.** Before this fix the solve ended with `Failure` (`STATUS_NONFINITE`) within about one MCS of the death, rather than freezing silently as the ROADMAP row said.

## D-080 P6.0m3: `integral(Pre(x))` (2026-10-01, P6.0m3; refines D-042, D-076)

- **In an update block,** `integral(Pre(x))` is the fold of x's block-start values over σ as the block sees it (post-sweep in `@after_mcs`). It is its own cell slot, refreshed once at the start of the after-MCS phases; in `@before_mcs` the MCS-boundary refresh serves it.
- It creates no `x__pre` snapshot and no dependency on x's writer. `_to_snapshots` never rewrites inside integrals.
- An integral reading block-written variables both through `Pre` and bare is an `ArgumentError`, because no single refresh point gives both.
- **Outside update blocks** (equations, division conditions and rules, link rules, discrete ticks, temperature, `@observed`, `sol[…]`), `integral(Pre(x))` is an `ArgumentError`. Before P6.0m3 it read the block-start fold through the shared slot in equations and the lifecycle, but the post fold in observed queries, while a bare `Pre(x)` there is the stored value. Rejecting it is safer than either meaning; keep the fold in a cell variable (`s ~ integral(Pre(x))` in the block).
- `Pre(x, k)` inside integrals is unaffected.
- Generated code is unchanged for models without `integral(Pre(…))`: 75 of 81 fingerprints identical; the 6 that changed all use `integral(Pre)`.
- Review: approved in round 1; the coordinator corrected the AUTHORING wording and the mixed-integral hint. Follow-ups: P6.0t (refresh waste), P6.0u (temperature location nit).

## D-081 P6.0d: the frozen-kind mask follows lifecycle events (2026-10-01, P6.0d; coordinator)

- **Where.** The mobility mask is refreshed by CorePotts' integrator after `run_lifecycle!` on every MCS that had lifecycle events (transitions, divisions, removals), through the existing `remake_frozen(f.sys, prob, state)` hook. Not in Potts' generated lifecycle: CorePotts' own `Lifecycle(trigger; kind)` transitions must be covered, and P6.4c's `@transition` then inherits the fix.
- **Cost.** Nothing on quiet MCS (`run_lifecycle!` already returns early); one O(sites) pass on MCS with events, which already synchronise with the host (D-035).
- **Count.** The number of mobile sites may change, so it can no longer be a constant of the integrator context; `reinit!` accepts a state whose frozen-site count differs.
- **Callbacks.** A `DiscreteCallback` that writes `kind` directly is not tracked; it must call the public refresh (or `reinit!`). Not pinned by the frozen test.
- **Acceptance** (frozen `p6_0d_frozen_kind_mask.jl`): a cell that becomes frozen by a transition never moves again; a released cell moves; the negative control (a transition to an unfrozen kind) keeps moving. Sequential and Checkerboard. The fixture installs a CorePotts `Lifecycle` with `remake(prob; f = g)` because Potts has no symbolic transition before P6.4c.
- **Round 2–3 and merge** (from the reviews; supersedes the Cost and Callbacks bullets above where they differ).
  - **Hooks.** `frozen_kinds(sys)` (a tuple of Int32 kinds: the standard rule — a site is frozen when its owner's kind is listed or it lies outside the domain) implies `frozen_varies(sys)`. The default `remake_frozen` applies the standard rule, so `remake`, `init` and checkpoint resume see the state's own mask; `PottsProblem` builds the mask when `frozen` is omitted and rejects a different `frozen` when frozen kinds are named. A custom `remake_frozen` must also define `frozen_varies(sys) = true`; `init` warns once when it does not. Potts defines only `frozen_kinds`.
  - **Device cost.** Models whose mask cannot vary (no `[frozen]` kind: every published and gate model, domain-only and user static masks) never refresh. Otherwise each event MCS runs one device kernel; its two counts travel in entries 2–3 of the lifecycle's `count` and are read only with the next lifecycle read-back (12 B instead of 4 B on that one MCS; D-089 moves them off the read-back entirely). `stats.attempts` for the MCS that ran with the old count is corrected exactly; `solve!`, `checkpoint` and any direct `refresh_frozen!`, `set_state!` on `kind`, `u_modified!` or `reinit!` flush pending counts. On a device no mobile-site list exists (`MaskMobility(frozen, nothing)`; the count lives on the host).
  - **API.** `refresh_frozen!`, `frozen_sites(prob, u)` (MakiePotts frames use it per saved state) and `u_modified!` (re-exported from SciMLBase) are exported; `frozen_varies`/`frozen_kinds` are public hooks. `PottsStats.refreshes` is new, so checkpoints from before this item do not load. A lattice that becomes fully frozen mid-run makes 0 attempts per MCS.
  - **Review.** Three implementer rounds; the coordinator applied the final read-back fix (ee2331b: 4 B with its sync unless counts are pending). Fingerprints of every published model unchanged; CPU warm timings within noise.

## D-082 P6.2a2: `akeeb_state` on `InsertUntil` and StableRNG (2026-10-01, P6.2a2; amends D-068, D-075)

- **Construction.** `akeeb_state` is `layout(akeeb_layout(...))`: an internal follower-slab layer (`_AkeebSlab`, using the D-057 `paint!` API, because `Tiling` cannot express the clipped right column with x-fastest ids) overlaid with `InsertUntil(:leader; into = [:follower], fraction = 1//4, misses = :count | :retry, region = (2:X, 2:slab−1))`, plus clocks from `StableRNG(seed + 1)` with the old recipe. `akeeb_layout` is exported and validates the lattice (width, rank, height above the slab).
- **Counted inventory.** `only(last(layout_tally(akeeb_layout(...), lattice)))`.
- **Split warning.** The overlay's split-cell warning is expected for the published slab; `akeeb_state` silences it with `Logging.with_logger(NullLogger())`, which would also hide any other log raised inside that `layout` call (none today; errors still throw).
- **Same law as before.** MersenneTwister → StableRNG leaves the 99×60 division onset unchanged (120 seeds each): first division at MCS 184.0 ± 20.4 vs 186.1 ± 20.3; no division by MCS 200 in 28/120 seeds for both; 48.8 vs 49.4 divisions by MCS 300. The smoke tests move from 200 to 300 MCS, removing a latent flake of about 23 % per seed.
- **Published ensemble.** Under StableRNG 589.7 ± 14.7 divisions (seeds 1:40, range 557–616), inside the frozen band [535.8, 634.2]; seed 1 gives 595 divisions and 196 singles.
- **Gate.** `akeeb_99x60` warm cost unchanged in-process (ratio ≤ 1.006); no re-baseline.
- **Known limitation.** StableRNG streams for seeds `s` and `s + 1` differ by a draw-wise constant shift. No coupling was measurable here (3000 seeds), but sub-stream seeds should come from a stable mixer, not `seed + k`: P6.0w.

## D-083 P6.0r: a killing copy's ΔH drops the dying cell's links (2026-10-01, P6.0r; maintainer; amends D-066 item 4)

- **Maintainer decision** (2026-10-01, asked by the coordinator): "Yes, ΔH = H change (Recommended)".
- **ΔH.** For a copy that kills its old owner `o` (o's last site), `link_delta` evaluates o's edges at the pre-copy state only and removes them: the edge term goes from E(before) to 0. So for every copy

      ΔE(copy) == H(after) − H(before) + E_cell(o, empty state)
                  [+ E_cluster(cluster[o], empty state), if that cluster has no alive member left]

  with no edge credit. In linked models with E_cell(empty) = 0 (e.g. `λ·volume²`), ΔH equals the H difference exactly. The cell and cluster credits stay as in D-066: ΔH pays the full cell-term change to the empty state.
- **Dynamics.** A linked cell under spring tension can now be copied away (its springs vanish with it). No published model uses links, so no published result changes.
- **`total_energy`** sums cell terms over alive cells and cluster terms over roots with an alive member (one marking pass, not O(n²)); free slots contribute nothing.
- **Self-check helpers** (`lib/PottsModels/test/runtests.jl`, `test/symbolic.jl`, `test/audit.jl`) add the cell and cluster credits for killing copies and no edge credit.
- **Cost.** One volume load of `o` (shared with `centroid_shift`) and one branch per link of `o`; a killing copy evaluates fewer terms than before.
- **Acceptance:** frozen `p6_0r_killing_copy_energy.jl` (brute force over every copy of a linked state; Sequential and Checkerboard trajectories through a killing copy; dead cells and clusters leave H; a stretched one-site cell is killed in a run on CPU and Metal; negative controls).

- **Fingerprints** (merge, from the review). `total_energy`'s generated code is part of the D-016 hash, so every published model's fingerprint changes with this item; checkpoints taken before it fail to load, by design. The ΔH change itself lives in `CorePotts.link_delta`, which is not hashed: a linked model's fingerprint is unchanged although its dynamics changed. No stored checkpoints exist.
- **Review.** Approved in round 1. `link_delta` cost in-process, base vs HEAD (64 cells × 4 bonds, 72²): sequential 59.38 vs 59.43 ns/site, checkerboard 61.00 vs 61.36, zero warm allocations. Killing copies brute-forced on hex Hex(2) periodic (surface, `major_length`, links), 3D Moore(1) and dead-root clusters: worst gap ≤ 2.4e-12. The coordinator added a free-slot `total_energy` test and fixed a docstring and a test comment (b3c9559).

## D-084 P6.0k2: `@components` rejections and fixes (2026-10-01, P6.0k2; amends D-077)

- **F7, rejected component features.** Before compiling, a component System with MTK `initialization_eqs`, `discrete_events`, `continuous_events`, `jumps` or `brownians` is an `ArgumentError` naming the component, the field and a workaround (`brownians` was added at merge from the review: they were silently dropped, giving deterministic trajectories). After compiling, a binding whose left side is, or whose right side reads, a coupled parameter is an `ArgumentError`. `guesses` stay ignored (Potts runs no MTK initialisation; documented). Other bindings were already rejected elsewhere; their messages not naming the component, and MTK `tstops`/`assertions` being ignored, are P6.0u.
- **F1.** `Pre(name)` of a component variable is substituted whole; for a discrete slot `Pre(x)` is the slot itself (`lower` already lowers `Pre(x)` to `x`, D-077 Jacobi), so `Pre(grn.x)[j]` and `Pre(grn.x[j])` compile and match the plain reads.
- **F6.** `lower` collapses `_nonzero(at(_nonzero(v), j))` (also under `Pre`); the inner value is always a Bool.
- **F4.** Only MTK's compile call is wrapped (`_mtk_compile_call`). An error whose innermost frame outside Base and the stdlib is Potts' `src/` or `ext/` propagates unchanged; others are relabelled "ModelingToolkit cannot compile" with the G15 hint. This is "who raised it", not "whose bug it is": a Potts misuse that MTK rejects is still relabelled. Julia 1.12 records stdlib frames under the build machine's path; the check matches `share/julia/stdlib/` (fixed at merge from the review).
- **Code.** Fingerprints of every published model and the P6.0k fixtures are byte-identical. Build time for component models +1–3 % (noise level); published models have no components.
- **Observation.** The `Clock(2)` and `ShiftIndex` fixtures fingerprint the same: P6.0p.

## D-085 P6.0v: GPU host-transfer counters and audit (2026-10-01, P6.0v; user request)

- **User (2026-10-01):** every synchronise, host↔device copy or host-side work during a Metal MCS must be either unavoidable or removed. P6.0v is the audit and the instrumentation; P6.0v1–v3 remove what the audit finds (ROADMAP).
- **Counters.** `PottsStats` gains `syncs` (explicit `KernelAbstractions.synchronize`), `transfers` (host↔device copies; one contiguous array = 1, and each array leaf of an `Adapt.adapt(Array, …)` snapshot = 1) and `transfer_bytes` (`sizeof` of the device array copied). They are summed by `merge` and restored with checkpoints. Every such call in the step path goes through one helper that counts. Device→device copies and device `fill!` are not counted; on the CPU backend nothing is counted.
- **Scope.** `step!` and the paths it reaches (lifecycle, `HostPhase`, `_AdaptiveODE`, refresh), plus saves and `integ.u` (counted; tests assert lower bounds only for those).
- **Frozen acceptance** (`p6_0v_transfer_counters.jl`): exact long-term targets only. CPU counters are 0 on every gate model. On Metal, a quiet MCS costs 0/0/0 B on Graner–Glazier, Wortel Act and Merks, and exactly 1 sync / 1 transfer / 4 B (the D-035 event-count readback) on OpenVT, Akeeb and a division fixture. Event and `HostPhase` MCS: invariants only (≥ 1, non-decreasing), because P6.0v1/v2 change them. Exact current-path counts live in an ordinary, non-frozen regression test that later rows update.
- **Audit document** `docs/design/research/gpu-host-transfer-audit.md`: every call site with when it fires, how much it moves, whether it is necessary, and its device-side replacement; codegen quality on Metal; the quiet-MCS baseline per gate model.
- **Review and merge.** Two review rounds plus a polish commit. A QA guard fails on any raw `synchronize`/`Array(`/`copyto!`/`unsafe_copyto!`/`Vector(`/`convert(Array` outside the counting helpers, against a `file => count` allowlist with reasons. On Metal, a test-only counter on `Metal.wait_cmdbuf!` checks that GPU waits = `syncs + 2·transfers` on quiet and event MCS of every gate model; Merks (6 implicit waits per MCS from Metal.jl's device→device `copyto!`) is `@test_broken` until P6.0v3, and a Metal.jl version other than 1.10.0 fails loudly. Partial read-backs count `n·sizeof(T)` bytes, so a quiet lifecycle MCS stays 1 / 1 / 4 B. **Implicit waits** (device→device `copyto!`, `UInt8` `fill!`, pointer conversions) are syncs under the user's standard and go to P6.0v3 (rule P6.0v8). D-089 later sets the quiet-MCS target to 0 / 0 / 0 (P6.0v1).

## D-086 P6.0n: cell ODEs are Jacobi across cells (2026-10-01, P6.0n; amends D-078, D-077 N3)

- **Supersedes** D-078's "cross-cell reads within a group stay Gauss–Seidel (P6.0n)".
- **Which reads.** A cell ODE rate may read other cells' ODE unknowns: an indexed read `y[j]` (including inside a gather), or a population fold left in the kernel because it reads `time`.
- **Start-of-step state.** Every such read sees the state at the start of the MCS's ODE step, held over all stages and substeps, under both algorithms, on the GPU, for every solver (adaptive included) and whatever the cell labels.
- **Scratch trigger.** `_ode_reads_other_cells` flags an `at`/`at2` whose indexed variable is a cell-ODE unknown (except a literal `x[id]`), a gather through the `at` nodes in its body, and an unhoisted `population` whose body reads one. When it fires, the cell scope writes scratch `x__ode` even with one solver group. Without such reads and with one group, code and fingerprint are unchanged.
- **Own reads.** Only bare `x` and a literal `x[id]` outside folds read the cell's advancing stage value. Index expressions also see the stepped locals (`w[f(y)]`). Every other indexed or fold read sees the held start-of-step value, including one that lands on the current cell (`y[max(id, 1)]`, a gather's `y[owner[n]]` with `owner[n] == id`, the own term of a fold left in the kernel).
- **Unchanged.** Model ODEs still see the cells' new values (D-077 N3). Hoisted folds are computed once before the cell ODEs.
- **Review.** Two rounds; round 1 found that index expressions had silently switched from the stage value to the held value (fixed). Fingerprints of every published model and of the cell-ODE fixtures without cross-cell reads unchanged; Metal device code of the frozen fixtures unchanged between rounds. Follow-up: P6.0x (gather allocation in cell-ODE rates, pre-existing).

## D-087 Initial-state follow-ups approved (2026-10-01; user; amends D-075 §3.3)

- **User decision** (2026-10-01), on the coordinator's two recommendations from `research/initial-state-review.md`: "i like both recs".
- **Also relayed verbatim by the peer session** (spec owner) from the user's answers: (1) "Approve (Recommended)" for the `merks_state` port (delete the hand loop; Merks uses `Scattered` with StableRNG and gets the P6.1a7 mask speed-up; gates are statistical, re-run, not bit-matched); (2) "Replace, with doc recipes (Recommended)" for `BrickWall`/`Plane`/`Spheres` (removed as named layers; the docs show each as a short recipe).
- **`merks_state` → `Scattered`** at P6.3d: `Scattered(282, (7,7); region, kinds = [:endothelial], seed, gap = 1)` replaces the hand-written loop. Same algorithm (draw-for-draw identical under a shared StableRNG); the stream moves from MersenneTwister to StableRNG, so each seed gives a different layout with the same law. The gate's Merks case changes its initial state: re-check the gate (no re-baseline unless it fails, D-048) and re-pick test seeds where needed.
- **General layers replace named ones** (amends D-075 §3.3): `BrickWall` becomes `Tiling(size; stagger, widths, partial = :wrap)` at P6.4d (confirm 04's layout reproduces exactly); `Plane`/`Spheres` become `Fill(region)` and `Objects(Sphere(…), points)` at P6.5c. No named aliases: the docs show each as a short recipe (e.g. a staggered `Tiling` for a brick wall).

## D-088 P6.0e2: primes of non-site quantities are Potts errors (2026-10-01, P6.0e2; amends D-061)

- `x′` is bound only for a site/field variable `x`. Reading `x′` where `x` is any other declared or `@extend`-inherited quantity (cell or model variable, parameter, kind, observed quantity, relation or edge variable) is an `ArgumentError` naming `x′` and saying "primes exist only for site/field variables"; cell variables get the hint `x[owner′]`.
- **Where.** The generated constructor runs its section code under `try`/`catch` and translates an `UndefVarError` for a name ending in `′` (`Potts._prime_error`, with a name ⇒ description table built at expansion, and the `@extend` bases). Local names `x′` (`let`, generators, closures, keyword names) are never affected; other errors and ordinary typos are rethrown unchanged; the happy path pays nothing. Round 1's static scan of the sections was dropped because it rejected such locals.
- **Declarations.** Every `PottsSystem` construction (macro, `extend`, components, programmatic) runs `_check_primed_names`: a declared `x′` beside a site/field `x` is rejected. Lone primed declarations stay legal (coordinator scope).
- **Residual.** An untranslated `x′` error from a hand-written (non-`@potts_model`) `@extend` base is labelled with the outer model's description: P6.0u.
- **Code.** Fingerprints of every published model unchanged; constructor time within noise.

## D-089 No synchronize on a quiet MCS: lifecycle planned on the device (2026-10-01; user; amends D-035, D-085)

- **User decision** (2026-10-01), asked by the coordinator after the P6.0v audit: "Remove it, device-side (Recommended)".
- **Rule.** On a GPU backend, lifecycle events are planned and applied on the device every lifecycle MCS, with no host decision and no read-back of the event count. Events keep their exact MCS (no backend difference). A quiet MCS of every model costs 0 syncs / 0 transfers / 0 B. D-035's "one 4-byte readback per checked MCS" is withdrawn for GPU backends; the CPU path is unchanged.
- **Consequences.**
  - P6.0v1 builds the device planner (daughter-id allocation, rule-carrying events, cluster handling, link updates and tracker updates on the device) and drops the trigger read-back.
  - Frozen target (b) of `p6_0v_transfer_counters.jl` (1 / 1 / 4 B per quiet lifecycle MCS) changes to 0 / 0 / 0 B: P6.0v1 re-freezes that file under this decision (D-060 style; only (b)'s numbers change).
  - P6.0d's deferred mask counts (D-081) must move off the read-back too: they stay on the device until a host read that already happens (save, `solve!` end, `checkpoint`), and `stats.attempts` on a device is exact only there.
  - The lifecycle statistics (`stats.lifecycle`) are read at those same points.


## D-090 P6.0s + P6.0v7: a fair machine lock; Metal timings to GPU completion (2026-10-01; coordinator, from the P6.0v audit)

- **Fair lock (P6.0s).** `tools/exclusive.sh` becomes a FIFO ticket queue: waiters are served in arrival order, so a waiter queued before an A/B runs before the A/B's second round (holding one lock for all A/B rounds cannot satisfy this: a waiter would wait for the whole A/B). All lock and queue state lives under paths starting with `/tmp/potts-exclusive`. Mutual exclusion, exit-status pass-through and the stale rule (a dead holder's state older than 3 h no longer blocks; live holders and waiters refresh their tickets) are kept.
- **Metal timings (P6.0v7).** Whenever a gate or `ab_one` measurement runs on a device backend, the timed expression is `step!` followed by `KernelAbstractions.synchronize(backend)`. Before this, Graner–Glazier and Wortel Metal numbers measured host enqueue only (gate 15 vs 86–140 ns/site with synchronize for GG; 46–60 vs 150–210 for Wortel), so earlier Metal A/B verdicts on those two models said nothing about GPU cost. CPU rows are unchanged. The Metal rows of `benchmark/baseline.toml` are re-measured once, under one lock.
- **Frozen acceptance** `benchmark/test/p6_0s_v7_tooling.jl` (listed in PottsModels' frozen.toml by relative path): ticket fairness against a sandboxed `ab.jl`, mutual exclusion, exit status, stale rule; a mock-device synchronize check for `gate.jl`'s `measure`; a structural check on `ab_one`; and a Metal part comparing GG 72 timings with `step!` + `synchronize`.
- **Review and merge.** Two review rounds. Round 1 found waiter starvation by dead tickets and stray queue entries; round 2 (approved) makes a ticket stale after 5 min without refresh (the lock keeps the 3 h rule), creates no files with `touch -c`, prunes stale non-directories, ignores non-numeric names, checks the keeper's parent and traps HUP/QUIT/PIPE. The coordinator added the two optional nits: the keeper skips a tick when `ps` fails, and queue ids have no leading zero. A waiter frozen for more than 5 min (sleep, SIGSTOP) loses its place and re-queues; exclusion holds.
- **Transition.** Metal rows now measure per-MCS latency to completion; Metal gate flags stay advisory and `ab.jl` decides. Right after the merge `ab-base` moves to the merge commit (an older base would compare enqueue against completion timing), and live worktrees merge `monorepo` or call the main checkout's `tools/exclusive.sh` by absolute path (old-script waiters can starve). P6.0v3 follow-ups: normalise Metal flags by the run's median Metal ratio; add a throughput row timing k MCS per synchronize.

## D-091 P6.1a6: the layout protocol (2026-10-01, P6.1a6; amends D-057, D-075, D-082)

- **Surface** as written in the header of `lib/PottsModels/test/acceptance/p6_1a6_layout_protocol.jl` (frozen): `paint!(op::LayoutState, l, lat)` with opaque `op` and the accessors `new_cell!`, `assign!`, `owner`, `kindof`, `ncells`, `record!`; lattice queries `size`, `isperiodic`, `indomain`; `layout(l, x; report = true)`; `Tiling(partial = :skip | :clip)`; `splits = :warn | :allow`; `remake` on layers. `paint!(σ, kinds, l, lat)` and `layout_tally` are removed with no alias (D-028).
- **Coordinator rulings on the test author's open points.**
  - Report rows carry `type::Symbol` (`nameof` of the leaf layer's type) besides the six ROADMAP fields; more properties are allowed.
  - Under `partial = :clip` a region reaching past the lattice is clipped to region ∩ lattice; under `:skip` it still throws (D-057).
  - The accessors are public (`public`), not exported. `owner` must not collide with the DSL's `owner`/`owner′`: the implementer checks the `@potts_model` expansion and the exported names, and renames only if a collision is real (recorded here if so).
  - **Width check.** A composed layout carries no lattice, so `layout(akeeb_layout(; lattice = (99, 60)), (500, 300))` no longer throws: the 99-wide slab is painted and the rest stays medium. `runtests.jl`'s "wrong width" assertion becomes that documented behaviour; the 3D and "below the slab" assertions stay if the general layers still raise them, otherwise they move into `akeeb_layout`'s own argument check.
- **Re-freeze (D-060 style).** `p6_2a_akeeb_analysis.jl` and `p6_2a2_akeeb_inventory.jl` change only their API calls (`layout_tally` → `layout(…; report = true)`); expected values unchanged. New hashes: `1f6ef1aebf04c33c89de8632137818c8f8dd5c4bf18cc7c84d244ec5729f7462` and `d0e36abb98abc68a2f0cbbeb0087eab71a459f0e3c3f51d00b9052e156e5d513`.
- **Expected values.** The 16 Akeeb digests are today's (ec544d8) outputs: the port must reproduce Akeeb's layouts bit for bit.
- **Review and merge.** One round, approved. Beyond the spec: `record!(…; counted = painted)`; under `fraction`, `InsertUntil` reports `requested = counted`; `assign!`, `owner` and `indomain` take a `CartesianIndex`; `remake` of a custom layer or an overlay throws. No `owner` collision (the DSL's `owner` is a codegen key). `Logging` left PottsModels' deps. Painting is at parity or faster except 1×1 tiling (+1.4 ns per box of accessor overhead; accepted). Coordinator doc fixes: `paint!` docstring, `assign!` does not wrap, a delegating layer calls `record!` last.

## D-092 P6.0v2: ODE and `HostPhase` copy only the columns they use (2026-10-01, P6.0v2; coordinator; refines D-085)

- **Frozen acceptance** `lib/PottsModels/test/acceptance/p6_0v2_column_copies.jl`, wired into `test/gpu.jl` (`P60v2OnMetal`). On a device, the per-MCS (syncs, transfers, bytes) of an adaptive-ODE, a `HostPhase` and an `@link` fixture are steady, identical between fixtures that differ only in unused cell/model/site quantities and parameter tables, independent of lattice size where σ is not read, and at most columns read + 2 × columns written + 16 B (up to four 4-byte scalar read-backs; changing the slack needs a DECISIONS entry).
- **`HostPhase(f!; every = 1, reads = nothing, writes = nothing)`** (public, additive). Entries are `:σ` or cell-column names. `writes` columns are copied down and back; `reads` columns down only; `nothing` keeps the whole-state behaviour. An unknown name is an `ArgumentError` on every backend by the first MCS the phase runs. Leaves not declared are unspecified inside the body. Potts declares the reads and writes of its generated `@link`/`@unlink` phases. Model and site quantities are not declarable yet (no current host body needs them); P6.0z revisits the surface.
- **In scope:** parameter tables are not copied per MCS (adapt `p` once, or copy only the tables read; audit A3); the static domain mask is cached on the host rather than copied per MCS (audit A4/H3).
- **Review and merge.** Two rounds. Round 1 found that host phases had been handed a cached host copy of `p` (stale after an in-place parameter write; body writes lost on a device): round 2 passes the live `p` again and caches only the static domain mask. Sentinel tests pin the cell helpers' read sets and the scanned reads of adaptive phases. Writing a `reads`-only or undeclared leaf is undefined (documented). R4 is filed as P6.0v2b; the second, idle sync of an MCS with two adaptive phases goes to P6.0v3.
- **Not in this item:** audit R4 (custom-rule `refresh_frozen!` snapshot) moves to P6.0v1's lifecycle work if it touches the same path, else stays filed under P6.0v2 as untested follow-up; an adaptive group reading another group's column (`x__ode` scratch) is allowed by the bound but not tested.

## D-093 P6.0w: sub-stream seeds through a stable mixer (2026-10-01, P6.0w; coordinator; amends D-082)

- **Helper** (internal): `Potts._substream_seed(seed, stream) -> UInt64 = _splitmix64(_splitmix64(UInt64(seed)) ⊻ UInt64(CorePotts.stream_id(stream)))`, one standard SplitMix64 step each; the stream name goes through `stream_id` (FNV-1a), not `hash`. Pinned exactly so a seed gives the same state on every Julia version. Every seed derived from another seed uses it; arithmetic on a seed (`seed + k`) is rejected by the frozen source scan. A future `layer_rng(seed, stream)` wraps this helper.
- **Akeeb.** `akeeb_state`'s clocks move from `StableRNG(seed + 1)` to `StableRNG(_substream_seed(seed, :clock))`: each seed gives different clocks with the same law; σ and kinds are unchanged (the 16 P6.1a6 digests hold). The frozen `p6_2a2_akeeb_inventory.jl` clock oracle is re-frozen (D-060 style; only the oracle's stream changes). The `papers.jl` Akeeb band is revalidated with a fresh ensemble as in P6.2a2 (D-082), not re-baselined unless it fails (D-048).
- **Not in scope.** Top-level layer seeds (`Scattered`, `InsertUntil`, `VoronoiBall`) still pass `StableRNG(seed)` through, so layouts at consecutive top-level seeds stay draw-coupled (a property of StableRNG; mixing them would change every layout). Documented as a known limitation; P6.0z may revisit with `layer_rng`. Merks' `MersenneTwister` goes with P6.3d (D-087).
- **Review and merge.** One round. The seed re-pick in `mechanisms.jl` was replaced by a correct attribution (the coordinator): `@divide` resets both clocks, so `clock == 0` at a save marks exactly the cells that divided that MCS; every newly split cell is one of them (123 of 123 over seeds 1:30; the majority-of-sites check missed non-convex mothers whose sweep-gained sites go to the daughter). The guardrail ignores the one internal name `_substream_seed` until P6.0z's `layer_rng`. The p6_2a2 re-freeze also fixes a stale comment. Akeeb divisions over 80 seeds: mean 585.8, SD 18.7 (band 585.0 ± 3×16.4; no re-baseline, D-048).
- **Frozen acceptance** `p6_0w_substream_seeds.jl`: the helper, the source scan, decorrelation of first draws across consecutive seeds (with `seed + 1` as the failing control), and `akeeb_state` determinism and law.

## D-094 P6.1a7: `Scattered` overlap test on an occupancy mask (2026-10-01, P6.1a7; coordinator)

- **Frozen acceptance** `p6_1a7_scattered_mask.jl`: σ, kinds and the report row identical to a5a2819 over 26 cases × gap ∈ {0, 1, 2} × 5 seeds (2D closed and periodic on all or one axis, 3D, hex, edge regions where the gap dilation wraps, dense near-jam requests, the D-087 Merks request) and 3 layered cases; the jam error names the same failing box; the 10 000-draw limit is pinned from both sides.
- **Timing.** `layout(…)` as a whole (it sets up `record!`'s leaf context), min over runs after warm-up: 10⁴ cubes of 5³ at 200³ ≤ 50 ms, closed and fully periodic (the periodic bound goes beyond the ROADMAP line so the wrap has no slow path); time per box at 4·10⁴ squares (3000²) ≤ 2.5 × that at 4·10³ (949², same density). Each timed σ is checked against its digest.
- **Report `misses`.** `Scattered` still reports 0; rejected draws are documented in the case table only.
- **Review and merge.** One round, approved: 2·10⁶ random decisions and 10⁵ random layouts identical to the pairwise test; 10⁴ cubes of 5³ at 200³ in 17 ms (closed and periodic), per-box scaling 1.2.

## D-095 Early cut-over to GitHub Potts.jl (2026-10-01; user; overrides AUTONOMY §5's all-pass gate)

- **User decisions** (2026-10-01), relayed verbatim by the peer session and confirmed by the user in the coordinator chat ("Yes, all of it (Recommended)"; "Now, at current monorepo (Recommended)"): "we should force pr merge to Potts.jl , renaming the folder names to have the .jl suffix and lining up with the names"; merge style "PR, merge commit (Recommended)"; rename "Neither, follow SciML"; old repos "Now"; lab audience "Mixed"; docs online: "we want them online".
- **What happens.** The monorepo becomes `PraneethMerugu/Potts.jl` `main` through a PR merged at once with a merge commit (no CI wait, no force push; D-025 stands). The old `main` stays an ancestor (unrelated histories joined with `--allow-unrelated-histories`, keeping the monorepo tree). Package folders keep their names (`lib/CorePotts`, `lib/MakiePotts`, `lib/PottsModels`, SciML style); only the repository is Potts.jl. CorePotts.jl, MakiePotts.jl and PottsModels.jl are archived read-only with a README pointer, after every local branch was pushed as an `archive/*` or `legacy/*` tag.
- **Consequences.** The ROADMAP is not complete and there is no CI yet: later merges land on `main` through ordinary pushes or PRs, never force pushes. `docs/references/` (copyrighted PDFs) and author letters stay untracked. The docs deploy to GitHub Pages.

## D-096 P6.0v1: the lifecycle on the device (2026-10-01, P6.0v1; coordinator; implements D-089)

- **Re-freeze of `p6_0v_transfer_counters.jl`** (D-060 style): target (b) becomes 0 syncs / 0 transfers / 0 B per quiet lifecycle MCS (D-089); testset (c) reads lifecycle counts through `checkpoint(integ).stats` and drops the event-MCS lower bounds (a device-planned division may move nothing); `p60v_step_deltas` classifies a window as quiet from checkpoints around it, not per-step stats. Nothing else changes.
- **Frozen acceptance `p6_0v1_device_lifecycle.jl`** (wired into `test/gpu.jl` as `P60v1OnMetal`). On Metal: (i) every quiet lifecycle MCS of every published lifecycle model and of the fixtures costs 0/0/0; (ii) a plain-division event MCS costs 0/0/0 and is identical across lattice size, number of cell quantities and capacity; cluster and link event MCS are identical across lattice size (O(events); the device link graph stays P6.0v5 backlog); (iii) results match the CPU oracles (counts, kinds, generations, copied quantities, clusters, links, trackers recounted from σ), with daughters allowed to permute among the same lowest-first slots and deferral compared by counts; OpenVT agrees with the CPU in law over 24 seeds; (iv) `stats.lifecycle` and `stats.attempts` are exact at the read points — a save, `integ.u`/`current_state`, `checkpoint`, and the end of `solve!` — and may lag between them (not pinned for `reinit!`, `set_state!`, `merge`); (v) OpenVT and Akeeb make zero `Metal.wait_cmdbuf!` calls over 4 quiet MCS (Metal pinned 1.10.0), with a control that the wrapper counts a checkpoint's wait.
- **Review and merge.** Two rounds. Round 1: a `divide!` rule that links mother and daughter raced the newborn's link cleaning; the Int32 moment-scratch guard reported late and stuck. Round 2 approved: copies and link cleaning run before the rules (a barrier; 6 staged launches), a cell whose `m2[k,k]` exceeds `typemax(Int32)` is deferred on the device (counted as deferred, warned once per read point; it divides only on the CPU) with id allocation and holds still in lockstep with the host planner, and the first launch falls back fused → staged → host with one warning. `cluster_normal` contract on the device: `σ` is the cell-labelled σ, and `volume`/`anchor`/`m1`/`m2` hold the cluster's values at every index; a portable rule reads them at the root and not `σ` (documented in `Lifecycle`). Akeeb on Metal: `ab.jl` 0.695 against fd84ba91 (10 rounds). Merged with D-098's `side = 7` edit of `p6_0v_transfer_counters.jl`; `frozen.toml` lists that file under D-096. The same merge passes `side = 7` to the Merks fixture of `p6_0v1_device_lifecycle.jl` (D-098's 10² seeds no longer fit 6 cells in 32²; D-060 style, nothing else changes).

## D-097 Reproduction 09 shows replicate 1 as a video (2026-10-01; user; amends D-072)

- **User decision** (2026-10-01): "instead of pictures of the state, lets show videos in the docs"; asked whether to change the frozen `reproductions/09_cell_sorting.jl`: "Yes, apply the video change (Recommended)".
- **Change.** The "Snapshots of replicate 1" figure becomes a video: replicate 1 is re-solved with 100 log-spaced saves (same problem, `replica = prob.replica + 1`, the full build's start) and recorded with `record_potts`; an `@assert` checks that its last state equals the ensemble's replicate 1 at the last save time (saving does not change a run). The ensemble, every table, V-target and number are unchanged. Re-frozen (D-060 style; new hash in `frozen.toml`).

## D-098 Merks 2006 parameter set as the defaults (2026-10-01; user; implements D-050 M1, M2, M5 values)

- **User decision** (2026-10-01): asked what tomorrow's docs should do after the shipped defaults (A = 50, L = 30, 2 field substeps) lost the network the paper shows: "Also change defaults tonight".
- **Change.** `MerksVasculogenesis` defaults are the Merks et al. (2006) set in lattice units: V₀ = 100, λ = 50, λ_L = 5, L = 50 (paper text; `longcells.par` has 60), χ = 1000, T = 50, Dc = 0.75, σc = δc = 5.4·10⁻³ (α = ε = 1.8·10⁻⁴ s⁻¹ × 30 s), J = [0 20; 20 40], recommended solver `ExplicitEuler(substeps = 15, lower = 0.0)`; `merks_state` seeds 10² cells. A 500² run of 282 cells forms the paper's polygonal network by ~1000 MCS and holds it to 6000 MCS; the old defaults fragment. Remaining differences (docstring): hard connectivity veto vs the E₀ penalty; free walls vs a frozen J_cB = 100 border; zero-flux vs an absorbing c = 0 field boundary. The 2008 variant inherits these values; pass the 2008 values as keywords (the full split stays P6.3d).
- **Frozen acceptance** `merks_2006_defaults.jl`: the default values, and a network oracle (200², 100 cells, 3000 MCS, seeds 1–3: largest component ≥ 0.9 of endothelial sites and ≥ 3 lacunae; the old defaults passed explicitly stay < 0.7 per seed and < 0.5 on average).
- **Re-freeze (D-060 style).** `p6_0c_solver_placement.jl` and `p6_0v_transfer_counters.jl` pass `side = 7` to their small `merks_state` fixtures (10² seeds no longer fit their cell counts); nothing else changes.
- **Gate.** `merks_100` now seeds 25 cells of 10² (same ≈ 25 % cover) with 15 substeps; its CPU baselines are re-set to 286.4 / 287.9 ns/site (sequential / checkerboard, measured under the lock): the whole ≈ 3× is the 15 field substeps (≈ 16 ns/site each). At merge the Metal row measured 1.51× its old baseline, inside the common-mode band of the other Metal rows under load (1.32–1.89), so it was not re-baselined. **Correction (2026-10-02, P6.0v1 merge):** that reading was wrong. On an idle machine the row measured 4.06× (729.75 ns/site) while every other Metal row was 0.77–1.21, and `ab.jl` gives the same ≈ 1000 ns/site for the pre-P6.0v1 base, so the cost is the 15 substeps on Metal (per-substep device copies and launches, P6.0v3/P6.0v8), not load. `merks_100.metal` is re-baselined to 729.75. Faster field substeps are filed under P6.0v3.

- **Gate.** `merks_100` now seeds 25 cells of 10² (same ≈ 25 % cover) with 15 substeps; its CPU baselines are re-set to 286.4 / 287.9 ns/site (sequential / checkerboard, measured under the lock): the whole ≈ 3× is the 15 field substeps (≈ 16 ns/site each). At merge the Metal row measured 1.51× its old baseline, inside the common-mode band of the other Metal rows under load (1.32–1.89), so it was not re-baselined. Faster field substeps are filed under P6.0v3.

## D-099 P6.0aa: `:arc_or_pair` exempts a two-cell ring only without medium (2026-10-02, P6.0aa; coordinator, from the topology audit)

- **Rule.** `connectivity(k; rule = :arc_or_pair)` accepts a copy when the losing cell forms at most one arc on the target's ring, or when exactly two cells and no medium are on the ring (TST `ConnectivityPreservedP`, which the Act papers cite). Out-of-domain sites on a `Closed()` face are not medium. The old rule ignored medium and accepted copies at cell–cell–medium junctions that split cells.
- **Frozen acceptance** `p6_0aa_arc_or_pair_medium.jl`: hand-built rings on 12² Periodic and Closed lattices and `WortelAct(connected = true)`: the junction cases are refused, the no-medium pair, one-arc, three-cell and last-site controls are unchanged, a closed edge is not medium, and single-cell retractions equal an independent arc count. On the old code the junction and edge-medium cases fail and the controls pass.
- **Consequences.** `test/symbolic.jl` (~1792) and `mechanisms.jl` (~408) assert the old rule and are updated with the fix. Default `WortelAct` (`connected = false`) and every published gate are unaffected.
- **Review and merge.** One round, approved: `_owners`' out-of-domain sentinel (−1; engine σ is always `Int32`) leaves `ring_arcs`, `ring_cells` and `local_components` identical to before over ≈ 575k random proposals on square, hex, mixed-boundary and masked lattices; `ring_medium` matches an independent count; Metal suite and `WortelAct(connected = true)` agree with the CPU. Splits in multicell `WortelAct(connected = true)` runs (adhering cells, J_cc = 10): 167 → 7 over 12 seeds × 1000 MCS (sequential), 9 → 1 (checkerboard); no speed change. **Closed edges differ from TST:** TST pushes its frame value (σ = −1) as a distinct cell, so old cell + other cell + frame with ≥ 2 arcs is refused there and accepted here, and old cell + frame alone with ≥ 2 arcs is accepted there and refused here. The frozen test pins this file's reading (out-of-domain is neither medium nor a cell); the docstring states the difference; P6.0ae decides whether to count the frame as a cell. TST also applies the rule as a ΔH penalty (`conn_diss`, default 2000), not a veto — the E₀ drive of P6.3a. The exported `ring_*` functions assume a signed σ (an unsigned array would wrap the sentinel); the engine never passes one.

## D-100 P6.0ad: `Barker` carries its offset (2026-10-02, P6.0ad; coordinator)

- **Law.** `Barker(; offset = 0)` (and `Barker(offset)`) applies the offset as Metropolis does, as a shift of ΔH: with `x = ΔH − offset`, accept with probability `1/(1 + e^{x/T})` for `T > 0`; at `T ≤ 0` accept if `x < 0`, and a tie `x == 0` with probability ½ — so at `T ≤ 0` the two laws coincide for every offset, as the manual states. `@sweep Barker(; offset)` and `SequentialCPM`/`CheckerboardCPM(; acceptance = Barker(; offset))` carry it; before, the offset was accepted and silently dropped. `offset = 0` is today's Barker bit for bit.
- **Frozen acceptance** `p6_0ad_barker_offset.jl`: exact thresholds at 7 (ΔH, T, δ) points in Float64 and Float32, the T ≤ 0 equality with Metropolis, the offset reaching the law through `@sweep` and the algorithm keyword, trajectories equal to a reference law and shifted in the right direction on both algorithms, and `offset = 0` equal to the old law.
- **Device.** Like Metropolis, a `Barker{Float64}` is narrowed to the device float type off the CPU.
- **Review and merge.** One round, approved: a brute-force grid in Float64 and Float32 (ΔH, T over ±0, ±Inf, NaN, extremes; offsets 0, ±1, 2.5, 10³⁰) matches the reference with 0 mismatches, `offset = 0` is bit-identical to the old law and Barker equals Metropolis at T ≤ 0 for every offset; `accept` and the warm sweep allocate nothing for `Barker{Int}`, `{Float32}`, `{Float64}`; on Metal a Float64 offset is narrowed to `Barker{Float32}`, and CPU and Metal agree in law over 16 seeds. Coordinator nits: the manual's detailed-balance sentence holds without an offset; AUDIT note updated.

## D-101 P6.0v3 + P6.0v8: no GPU wait in a quiet MCS; launch fusion (2026-10-02, P6.0v3; coordinator, from the P6.0v audit)

- **Targets.** On Metal, a quiet MCS of every gate model (Graner–Glazier 72, Wortel Act 100, Merks 100 with 15 substeps, OpenVT 100, Akeeb 99×60) makes 0 counted syncs, 0 transfers, 0 B and 0 actual GPU waits (`Metal.wait_cmdbuf!` wrapped). Every device→device copy in the step path (field substeps, generated copy phases) waits 0 times, whatever the substep count (today 2 per copy: Merks makes 30 waits per MCS). Launches per quiet MCS fall within [floor, bound] from audit §8.1/§10/§11: GG 8, Wortel ≤ 33 (≥ 32), Merks ≤ 38 (≥ 23), OpenVT 9 and Akeeb 13 (a model cell phase fused into the lifecycle kernel, F1; today 10 and 14). Two consecutive adaptive-ODE host phases make one sync, not two.
- **Invariants.** Results unchanged: CPU bitwise against explicit-Euler and swap oracles and recorded Merks digests (32², 15 substeps, seed 7); Metal bitwise equal to the CPU Float32 run; no Float64 in the Float32 builds' parameters, state, context or kernel functions on Metal.
- **Frozen acceptance** `p6_0v3_launch_fusion.jl` (wired into `test/gpu.jl` as `P60v3OnMetal`). On the base: Merks waits, the copy-wait fixtures, OpenVT and Akeeb launch counts and the two-adaptive-phase sync fail; every control passes.
- **Implementation.** `_device_copy!`/`_device_fill!` KA kernels on a device (Base calls on the CPU) for field substeps, `CopyPhase`, `CellReduce` and `ContactPhase`; a public `Lifecycle(…; before)` hook runs the model's last after-MCS cell update in the trigger's work item when Potts proves (`_reads_own_only`, `src/codegen.jl`) that the trigger reads that update's written columns only at its own cell, else the update stays its own launch; an adaptive-ODE host phase directly after another skips its sync (the first ends with its uploads); T3's `fill!` replaced by two count slots alternating by round, the trigger zeroing the next one; wrapping conversions where a bound holds. X4 (typed literals in generated code) is deferred: it would change every model's fingerprint.
- **Review and merge.** One round, approved: fused runs bitwise equal to an unfused twin on Metal and CPU (OpenVT, Akeeb, `Every(2)`, every fallback form, a mid-run state callback, `reinit!`, checkpoint resume; 252 comparisons), no false positive found for `_reads_own_only`, the skipped sync safe with a device phase between two adaptive phases. A/B on Metal: Merks 0.188 (≈ 980 → 200 ns/site), Wortel neutral (0.998 reversed); CPU unchanged (OpenVT 0.996). Notes: `generated_code` lists the unfused phases; the host trigger now wraps its result with `% Int32` (a hand-written CPU trigger must return an integer); empty copies and fills launch nothing (coordinator).

## D-102 P6.0y: the automatic explicit-Euler substep count keeps a margin and counts linear reaction (2026-10-02, P6.0y; coordinator)

- **Criterion.** Explicit Euler with substep τ = dt/n multiplies a Fourier mode by g = 1 + τ(Dμ − k); the checkerboard mode has μ = −Σ_d 4/h_d². With Λ = D·Σ4/h² + k and ρ = τΛ, every mode is stable iff ρ ≤ 2. The old count `ceil(dt·D·Σ2/h²)` reaches ρ = 2 exactly (the checkerboard never damps) and ignores reaction, so diffusion with decay blows up (e.g. 2D, D = 0.5, k = 0.2: ×1.21 per MCS).
- **Requirement.** The automatic count (`ExplicitEuler()` without `substeps`) satisfies (M) ρ ≤ 1.8 (|g| ≤ 0.8 per substep), (K) Λ includes a bound on |∂f/∂c| of the field's linear reaction (`−k c` and an indicator-weighted `−k c (kind == medium)` both bound by k), and (C) n ≤ max(1, ceil(dt·Λ)) (no more than the ρ ≤ 1 count; performance over exactness). An explicit `substeps = n` stays a minimum as today; counts above the new automatic count keep their values bit for bit (Merks' 15 included).
- **Frozen acceptance** `p6_0y_stable_substeps.jl`: the count is read from the dynamics (the smooth mode's measured factor) on 1D/2D/3D periodic DSL models, and the field must match the closed-form two-mode solution; pure diffusion over 72 (D, dt, h) points, five diffusion–decay cases (uniform and matrix-only), a live-cell fixture whose L2 norm must not grow, and bit patterns for explicit counts and Merks. Model fingerprints are not pinned (the substep function is rewritten). On the base, (M) and the decay cases fail; explicit counts pass.
- **Implementation.** `stable_substeps(D, dt, h, k) = max(1, ceil(dt·(D·Σ4/h² + k)/1.8))`, recomputed from the live parameters each MCS (host only, allocation-free); k bounds |∂f/∂c| of the reaction (Δ of the field itself replaced by L; other fields' Δ are frozen during this field's step and count as sources) via `Symbolics.derivative` and an interval-style `_abs_bound`: parameters by `abs`, comparisons and `rand()` by 1, kind tables by their live max |entry|, `ifelse` by its larger branch. A reaction whose rate depends on state (nonlinear in c, `mcs`, another variable) counts k = 0 with a build-time warning unless `substeps` is given; a negative diffusion coefficient warns (anti-diffusion is ill-posed). Fields without Δ also get a count.
- **Review and merge.** Three rounds. Round 1: `rand()` in a reaction no longer built; per-kind decay fell back to k = 0. Round 2: a cross-diffusion term `−Dx·Δ(u)` cancelled the field's own coefficient (n = 1, 2·10¹⁴; also on the base). Round 3 approved: no silent unsound case found across sign changes under `remake`, indicators, `ifelse`, kind tables, helpers and nested forms; Merks (explicit 15) and every docs example unchanged; bare `ExplicitEuler()` on Merks 3 → 4. **Merge re-freeze (D-060 style):** the substep function is part of a field model's fingerprint, so Merks' fingerprint changes (0x0febe8d2ccb7e62c → 0xe8c37fa651d985f6); `p6_0x_gather_ode_alloc.jl` pins it and is re-recorded for that one constant, listed under D-102.

## D-103 P6.0x: a gather in a cell-ODE rate allocates nothing (2026-10-02, P6.0x; coordinator)

- **Problem.** A cell ODE whose rate contains a site-neighbourhood gather (`sum(volume[owner[n]] for n in Moore(1)(42))`, a conditioned `maximum` over neighbours, a `count` over a `@relations` ring) allocates 480–1472 B per warm MCS with the fixed-step solvers. Inference is concrete; the bytes come from building and passing the `rhs` closure, which holds heap references (272 B per cell per call), not from dynamic dispatch as the ROADMAP row guessed.
- **Frozen acceptance** `p6_0x_gather_ode_alloc.jl`: zero warm bytes per `step!` for three gather shapes × Float64/Float32 × `ExplicitEuler()`, `ExplicitEuler(substeps = 4)`, `RK4()` × `SequentialCPM`/`CheckerboardCPM`; no-gather controls zero today; final values bitwise unchanged over 10 MCS (including `Adaptive(Rodas5P())`); fingerprints of models without a gather unchanged (two fixtures and four published models). Adaptive solves allocate with or without a gather and are not targeted.
- **Implementation.** For a fixed-step ODE system whose rates contain a gather, each rate evaluation (Euler's stage, RK4's four) is written out in place instead of calling the per-cell `rhs` closure (`_ode_expand`, `src/codegen.jl`); other systems keep the closure, so their generated code and fingerprints are unchanged.
- **Review and merge.** Two findings, resolved by the coordinator without a code change. (1) The cause is the closure itself, not the gather: inside a RuntimeGeneratedFunction, Julia 1.12 lowers it to an opaque closure that is built on every call whenever the rate is not inlined. Rates without a gather allocate too (a Hill gene circuit 128–576 B per MCS, a 5-level `ifelse` chain 544 B, a 16-term sum 320 B, model ODEs with population folds 240–640 B), and the same rates **fail to compile on Metal** (`jl_new_opaque_closure_jlcall`). Forcing expansion fixes all of them bitwise, but changes the fingerprints this file pins, so it is P6.0ag under a new decision. (2) This change also fixes Metal compilation for gather ODEs (every gather fixture failed at the base; now bitwise equal to the CPU Float32 run). Bitwise equality held over 204 adversarial runs (names colliding with generated locals, nested and multiple gathers, model ODEs); first-solve time unchanged; RK4 cell-phase code grows ≈ 10× in LLVM lines for a three-ODE, four-gather model.

## D-104 P6.0ag: every fixed-step ODE system is expanded in place (2026-10-02, P6.0ag; coordinator, from the D-103 review)

- **Problem.** Any fixed-step ODE rate the compiler does not inline goes through a per-cell `rhs` opaque closure built on every call: 48–640 B per warm MCS on the CPU and a Metal compile failure (`jl_new_opaque_closure_jlcall`), with or without a gather — a Hill gene circuit, a 5-level `ifelse` chain, a 16-term sum, a population fold, at cell and model scope.
- **Change.** Every fixed-step system (cell and model ODEs) is expanded in place, as D-103 does for gather systems. Fingerprints of models with ODEs change by design; `p6_0x_gather_ode_alloc.jl`'s fingerprint pins for its no-gather fixtures are re-recorded (D-060 style, nothing else changes); models without an ODE keep theirs.
- **Frozen acceptance** `p6_0ag_ode_expand_all.jl` (wired as `P60agOnMetal`): zero warm bytes for 8 shapes × Float64/Float32 × `ExplicitEuler()`, `ExplicitEuler(substeps = 4)`, `RK4()` × both algorithms; on Metal every shape compiles, runs and equals the CPU Float32 run bitwise, except the Hill shapes within 4 ulp (the device's `x^4`, `exp`, `sin` differ by 1–3 ulp from the CPU's); CPU values bitwise unchanged (96 values); GranerGlazier and Merks fingerprints unchanged; a gather ODE and plain controls on Metal. On the base 92 of 96 allocation targets and all 24 Metal targets fail.

## D-105 Generated sums are ordered by build-dependent hashes; P6.0ag's model-scope pins within 8 ulp (2026-10-03; coordinator, from the P6.0ag implementation; amends D-104)

- **Finding.** Symbolics orders the terms of a sum by hashes that differ between package builds (`_commutative_order!` already sorts `+`/`*` operands for fingerprints for this reason, but not in the generated code). So the generated arithmetic of a rate with several terms can change order after a rebuild of identical source, and its floating-point result by a few ulp. Observed: `p6_0ag_ode_expand_all.jl` item 3 failed by 1–3 ulp on its model-scope shapes (population folds plus long sums), with the failing set moving between rebuilds (5 → 1 cases), and the code before the change failed it too. Within one build, results are deterministic.
- **Re-freeze (D-060 style).** Item 3 compares model-scope shapes within `rtol = 8eps(T)`; cell-scope shapes stay bitwise. Nothing else changes; `frozen.toml` lists the file under D-105.
- **Follow-up.** P6.0ah: make the generated term order canonical (sort commutative operands in `lower`/codegen as the fingerprint does), so results are bitwise reproducible across builds; then the tolerance can return to bitwise.
- **Review (P6.0ag, approved).** Cause confirmed and sharpened: the hashes of Potts-registered operators (`population`, `gather`, `at`) change with each package build's module id, and Symbolics orders terms by them; Base operators (`sin`, `exp`) hash stably. So the scope is "rates with Potts-registered operators", at cell or model scope — not "model scope": across two builds of identical source, 13 of 188 models' raw generated code differed (all identical after `_commutative_order!`) and 37 of 752 results moved by a few ulp, including the cell-scope `P60nMixed`. The p6_0ag cell shapes happen to use only Base operators, so item 3 stays sound. Other frozen bitwise pins on ≥ 3-term rates with those operators are latent cross-build flakes until P6.0ah. The generated code's operand order also varies between calls within one session (two-operand swaps only, exact in floating point; results matched 752/752 within a build). Closure removal is safe (752/752 bitwise with forced expansion on the base); Metal suite completes; "every GPU wait is counted" passes 21/21 (the "Broken" seen was a `@test_skip` without Metal).
- **Merge with P6.0y.** P6.0y changed Merks' fingerprint (D-102); both `p6_0x_gather_ode_alloc.jl` (now listed under D-104, carrying both its D-104 and D-102 re-records) and this file's Merks pin (item 5) are re-recorded to 0xe8c37fa651d985f6 (D-060 style).

## D-106 P6.1e: `graner_glazier_aggregate`'s default margin is 60 sites (2026-10-03, P6.1e; coordinator, from the paper run)

- **Change.** The default empty margin around the aggregate becomes 60 sites (was 10) on the same periodic lattice, sized `L = 2⌈√(40n/π)⌉ + 1 + 2·margin`. A 10-site margin lets a long sorting run drift onto the lattice edge and across the seam (n = 200: at 22 800 MCS for one seed) and, in the 10⁴-paper-MCS paper run, join its periodic image; the paper run already passes `margin = 60`. Explicit `margin = m` is unchanged bit for bit. This is a geometry default, not model science (D-050 is silent on the margin; the paper does not state its boundary).
- **Frozen acceptance** `p6_1e_gg_margin.jl`: default margin ≥ 60 measured from σ and constant in n (n ∈ 50, 200, 1000 × 3 seeds), default = explicit `margin = M` bitwise; explicit margins 10 and 60 match digests recorded on b011b772; a 25 000-MCS run at the default never puts a cell on the outermost rows/columns, with a margin-10 control that does. The frozen `p6_1b2_gg_aggregate.jl` builds at the default; its 12 assertions pass with margin 60 (checked by shim), and it is not re-frozen.
- **Cost.** Default lattices grow (n = 1000: 247² → 347²); non-frozen tests that only need a small aggregate pass `margin` explicitly. Reproduction 09's full build passes `MARGIN = 10` explicitly and is unaffected; whether its 1000-cell replicates reach the edge is a question for P6.1b.
- **Review and merge.** A four-file change (default, docstring with the side formula and the reason, two non-frozen tests, the GG page); reviewed by the coordinator. Frozen P6.1e 92/92 and P6.1b2 12/12; PottsModels, Potts and docs exit 0; reproduction 09's reduced build unaffected (its default-margin start only feeds area statistics, 0.028 s).

## D-107 P6.0ah: generated code does not depend on operator hashes (2026-10-03, P6.0ah; coordinator, from D-105)

- **Requirement.** The generated code of every rate, update and energy is a function of the model alone: the order of commutative operands and the numbering of hoisted population folds (`__odepop1`, …) must not depend on any hash (Potts-registered operators' hashes change per package build; Base functions' could change too). Results are then bitwise identical across package builds, repeated builds in one session, and calls of `generated_code`. Values may move once by a few ulp from today's order; fingerprints of models that hoist two or more folds may change once.
- **Frozen acceptance** `p6_0ah_canonical_term_order.jl`: simulates another build in one process by salting `Base.hash` for `population`, `gather`, `at`, `at2`, `sin`, `cos`, `exp` (inert at salt 0; a negative control shows a salt reorders a sum); requires `generated_code` identical under salts 1–4 and over repeated builds, fingerprints and RK4 states bitwise identical under salts, GranerGlazier/Merks/`P60ahAt` fingerprints unchanged; an opt-in cross-build check (`POTTS_CROSSBUILD=1`, two processes with fresh depots, ≈ 3.5 min) compares code and results of two real builds. On the base: 162/192 code comparisons, 32/128 result comparisons and the repeated-build check fail; cross-build 48/96 entries differ.
- **After merge.** Item 3 of `p6_0ag_ode_expand_all.jl` can return to bitwise (a D-060-style re-freeze under this decision, in the same merge if the values are recorded from the canonical order).
- **Implementation.** One canonical pass in `lower`: the operands of a Symbolics sum or product are lowered and sorted by their generated code text (`_code_key`, memoised per expression so nesting stays linear); hoisted folds, gather relations and integral names are numbered by `_symkey`, a printed form with sorted operands whose ties are broken by the bound variables' names (model-deterministic: `_GATHER_COUNT`, reset per build, counts in source order). A fold inside `integral(...)` stays inside it (the integral of a fold failed to build, also on the base). Item 3 of `p6_0ag_ode_expand_all.jl` is bitwise again (96 values re-recorded; 11 moved by ≤ 2 ulp); no pinned fingerprint changed; integral tracker names changed (internal; old checkpoints are refused by the fingerprint check).
- **Review and merge.** Two rounds. Round 1: equal folds over different bound variables tied in the key, so their numbering still followed hash order; keys were quadratic in nesting depth. Round 2 approved: a 211-model salt sweep over Potts operators, Base math and `+ * - / ^` gives identical code except one constant printed `39`/`39.0` when Base arithmetic hashes are salted (matters only if those change, e.g. across Julia versions); real cross-build 100/100 and 506/506; names deterministic under `@extend`, `extend`, re-evaluation, builds inside functions and `remake`. Build cost: published models unchanged, flat 400-term sums 1.5× in `generated_code` (problem build still 5–7× faster than the base). Follow-ups: P6.0ai (an integral of a fold re-evaluates the fold at every site: 150× at 400², 1600 cells), P6.0aj (concurrent model builds on threads are not deterministic: `_GATHER_COUNT` is a shared global; predates this item).

## D-108 P6.0af: the device lifecycle's mid-sequence handover; `generated_code` shows fusion (2026-10-03, P6.0af; coordinator, from the D-101 review)

- **Handover.** When the staged device form fails after some of its kernels were enqueued (k = 1: the trigger with the fused `before`; k = 2: also the planner), the host planner takes the MCS without re-running `before` and without counting this MCS's divisions twice. Today k = 2 double-counts (Akeeb 85 vs 72 divisions: the planner kernel already added them to `dv.acc`). Test-only hook `CorePotts._STAGED_FAULT_AFTER = Ref(0)`: with k > 0, the staged form's first launch enqueues k kernels and then throws as if the next launch failed (once per integrator). A failure after the partition kernel (k ≥ 3) would hand a modified state to the host planner; the implementer either makes every kernel of a form launchable before any is enqueued (so a launch failure can only occur at k = 0) or documents why k ≥ 3 cannot happen.
- **`generated_code`.** Gains `lifecycle`: `nothing` without divisions, else a NamedTuple with at least `trigger` and `before`; when fused, the update is in `lifecycle.before` and not in `phases`; fingerprints unchanged.
- **Frozen acceptance** `p6_0af_lifecycle_followups.jl` (wired as `P60afOnMetal`): k ∈ (1, 2) on a counter fixture (also `Every(2)`), OpenVT 60² and Akeeb 60×40, seeds 1–2, fused+fault = unfused+fault bitwise and = an unfaulted device run in σ and every column except `anchor`/`m1`/`m2` (trackers checked against a recount from σ), equal division counts, a negative control that re-runs `before`; a Metal variant; `generated_code` for fused and unfusable models with pinned fingerprints. On the base: the hook is missing and (b) fails; with the hook emulated, only the k = 2 division count fails.
- **X4** (typed literals) stays deferred in the row.
- **Review and merge.** Two rounds. Round 1 approved with notes: a launch failure after the partition kernel (which writes σ) would have handed a partly divided state to the host planner; that failure is now rethrown (`_StagedFailedMidway`, CorePotts test with k = 3) and k ≤ 2 still hands over; the compile-on-empty-range comment names it a backend property (verified on Metal.jl 1.10, from source for CUDA.jl); the handover MCS counts its enqueued kernels in `stats.launches`.

## D-109 P6.0aj: a model build keeps its state per build (2026-10-03, P6.0aj; coordinator, from the D-107 review)

- **Requirement.** A `@potts_model` constructor's build state belongs to that build: the bound-variable and draw counter (`_GATHER_COUNT`), the lattice dimension read by `centroid()`/`displacement(c)` (`_DIM`) and the `@extend` nesting depth (`_NESTING`), task-local or carried in the macro's build state, so builds on several threads, or tasks that yield mid-build, cannot reset or share each other's numbering. A nested `@extend` base still continues the outer model's numbering. Bound-variable names and draw numbers are then a function of the model's source alone. The scope is wider than the row's `_GATHER_COUNT`: the test author found that a shared `_DIM` makes concurrent `centroid()` builds throw, which the row's accept line (same code as built serially) covers.
- **Frozen acceptance** `p6_0aj_concurrent_builds.jl` (freeze 7cf0cdab): models built as tasks (4 × 20, with mid-build `yield()`) and under `Threads.@threads` (4 × 32; meaningful with `julia -t 4`, as PottsModels is tested) match a serial build in every `generated_code` expression, the problem fingerprint and the set of bound names, with no name reused within a model and no build error; WortelAct (both), AkeebInvasion, GranerGlazier, Merks and fixtures with gathers, folds, `rand()`, `centroid()` and a nested `@extend`. On 2f54c1e9 the task part fails every round on 1 thread (12/20 differ) and both parts on 4 threads.
- **Review and merge.** Two rounds. Round 1 approved: 225 systems' serial generated code identical to 2f54c1e9; `@extend` chains, builds that throw and models built inside a body checked. Round 2 (from a round-1 note, a defect already on the base): a model built inside an `@extend` base's body reused the shared state and reset its lattice dimension; the nesting depth became a one-shot flag set just before the base's constructor (its arguments evaluated first), so only the base continues the outer build. The build state is a `ScopedValue` (task-local outside a constructor, which user code cannot reach).

## D-110 P6.0ai: population folds inside `integral` are hoisted (2026-10-03, P6.0ai; coordinator, from the D-107 review)

- **Requirement.** In `integral(expr)`, a population fold that reads neither the enclosing cell nor the site is computed once per MCS in a model-scope slot, as `_hoist_populations` does outside integrals, instead of at every site of every tracker. The tracker is named after the operand with the slot substituted, and the name stays canonical (D-107). Folds that read the site, in their body or their condition, stay per site. Results may change only by rounding.
- **Frozen acceptance** `p6_0ai_integral_fold_hoist.jl` (freeze aaa8dcf8): 200², 400 cells, a site field `w`, two trackers holding three folds; the unfactored and hand-factored models give equal σ and tracker values (1e-12 relative, matching a per-cell oracle) over 10 MCS on Sequential and Checkerboard, and cost within 1.2× per warm MCS (Sequential; minimum of 5-step samples over 10 alternating rounds; best of 3 attempts); the unfactored model's code, fingerprint and column names are unchanged under the P6.0ah salts and repeated builds. Negative control: three site-reading folds (40², 16 cells) match their per-site oracles. A fold that reads the enclosing cell cannot be written in the DSL today. On 2f54c1e9 the cost ratio is 22× idle (28.8 vs 1.27 ms), everything else passes.
- **Review and merge.** Two rounds. Round 1: the hoist correct on CPU and Metal (staleness, gated readers, `Pre`, nested folds, `sites`, division, checkpoints; 79 of 81 systems' generated code byte-identical to 2f54c1e9, the other two hoisted by design); should-fix: observed integrals wrote the slots of the observed state, and three refresh points had no test. Round 2: `_fresh_integrals` copies the slots; a test per refresh point (each fails with its slot phase removed) and a Metal test. Only outermost folds are candidates: a site-independent fold nested inside a site-reading fold, and a fold drawing `rand()` (a fresh draw per site), stay per site; slots are named by content (`__ifold_<hash>`). Merge: the gate's Metal Merks row read 1.04 over 8 rounds; the implementer showed identical source in two checkouts differs by up to ±4% on Metal (per-checkout compiled caches, rebuilt often in the shared depot), removed the one runtime-visible addition (a `_Seq` phase wrapper) so models without a fold in an integral get exactly the base's phases and types, and later A/B gave Merks 0.944, GG 0.978, Wortel 0.974. Checkpoints of models with a fold inside an integral written before this change fail with the fingerprint-mismatch error.

## D-111 P6.0ab: kind tables from parameters; `observe` by name (2026-10-03, P6.0ab; coordinator, from the docs authors' reports)

- **Kind tables.** A kind-table default (`J[kind, kind] = …`, `V₀[kind] = …`) may have entries that are expressions of other parameters. It is evaluated like a scalar computed default (`V₀ = 2A₀`): at problem build from the operating-point and default values, and again by `remake(prob; p)` and the integrator setters (`setp`, `integ.ps[x] = v`) whenever the table itself is not set explicitly; an explicit value overrides the expression. Values are converted to the problem's scalar type, so the parameter type and the compiled code do not change. A contact table built this way is checked for symmetry on its values (`ArgumentError`).
- **`observe` by name.** `observe(prob_or_sol, name::Symbol)` resolves `name` to the model's quantity of that name (`@observed`, declared variable, built-in or parameter) and equals `observe` on that quantity; an unknown name raises an `ArgumentError` that names it.
- **Frozen acceptance** `p6_0ab_api_defects.jl` (freeze e9825717): hand-computed energies for the defaults, after `remake`, a constructor keyword and an integrator setter; equality with a twin written in numbers; observe by Symbol on `sol` and `prob` for an `@observed`, a cell variable, a built-in and a parameter; negative controls (asymmetric table, unknown name).
- **Review and merge.** Two rounds. Round 1: code correct (chains, mixed entries, Float32 kept, operating point/keyword/`remake`/setters, checkpoints, fingerprints of every PottsModels system unchanged; `observe` by name through divisions and component names); should-fix: the docs said an explicit table "keeps" its numbers, but any later change of another parameter re-derives it (the rule for scalar computed defaults too, already so on the base). Round 2 documents that, the declaration order, and `observe`'s resolution order (variable or `@observed`, built-in, parameter), and the unknown-name error points to a vector quantity's components and to `sol.t`. Follow-ups P6.0ak (re-derive only on a change of an input) and P6.0al (one name in two categories).

## D-112 P6.0ak: explicit parameter values survive unrelated changes (2026-10-03, P6.0ak; coordinator, from the D-111 review; amends D-111)

- **Rule.** A *change* is the set of parameters named by one `remake(prob; p = map)` or one integrator setter (`integ.ps[x] = v`, `setp`). A computed parameter (a scalar default that is an expression of parameters, or a kind table with expression entries) is re-derived by a change iff it is not named in the change and one of its expression's inputs is named in the change or is re-derived by it (transitively). Every other parameter keeps its current value, so an explicit value (from `remake`, a setter or the operating point) survives every change that does not touch its inputs; a change of an input re-derives it and overrides the explicit value (give it again in the same change to keep it). In a chain α → β = 2α → γ = β + 1, a change of α re-derives β and γ even when β was explicit; a change of β re-derives γ; an unrelated change touches neither. A parameter object given whole (`remake(prob; p = ck.p)`) sets every value. Problem build is unchanged; values keep the problem's scalar type. Amends D-111's "whenever the table itself is not set explicitly" and the parameters page.
- **Stateless.** A computed parameter never set explicitly always equals its expression under this rule, so no per-parameter flag is needed: the result depends only on the current values and the change.
- **Frozen acceptance** `p6_0ak_explicit_parameters.jl` (freeze e8e894e1): hand-computed energies and values on a two-cell fixture for explicit tables and scalars under unrelated and input changes, through `remake`, setters, the operating point, a checkpoint (`remake(prob; p = ck.p)` and continuation) and Float32, with chains through a scalar and a table; negative controls (input changes re-derive, computed defaults follow their inputs, asymmetric/unknown/mis-sized values rejected, the source problem unchanged). On eee2dec3: 36 of 92 fail, each a kept value re-derived.
- **Review and merge.** Two rounds. Round 1: the rule correct (vector inputs, chains, `@extend`, key types, ensembles, checkpoints); should-fix: a `setp` with several names was applied one name at a time, so its result depended on the order. Round 2: a CorePotts hook `set_parameters` and a batched `ParameterSetter` (`SII.setp` with a list on an integrator, problem, function or model description) make such a list one change, validated all-or-nothing; an unknown name is an `ArgumentError` when the setter is built. Unrelated changes are 2–3× faster (early return), input changes ~12% slower (input scan). Follow-ups P6.0ap.

## D-113 P6.0al: one name, one category (2026-10-03, P6.0al; coordinator, from the D-111 review)

- **Context.** `@potts_model` already rejects a second declaration of a name in another category within one model (`_declare!`), but `extend` merged by name only within each category, so a base parameter `x` and an extension variable `x(cell)` coexisted (`observe`/`getu` returned the variable, `lookup` the parameter), and a component's namespaced quantity (`clk₊yy`) could coexist with a parameter of that name.
- **Rule.** Kinds, parameters (vectors by their vector name), variables (all scopes), observed quantities, relations, relationships and components share one namespace. A name in two categories is rejected when the `PottsSystem` is built (next to `_check_primed_names`), whether it came from one model, `@extend`, `extend` or a programmatic build, with an `ArgumentError` naming the name and both categories; a component's namespaced quantities are claimed too (rejected by `mtkcompile` at the latest). Redeclaring a name in its own category stays an override in which the extension wins (parameter defaults, variables, observed quantities, relations, extended kinds). `lookup`, `observe` and `getu` then agree on every name.
- **Frozen acceptance** `p6_0al_name_categories.jl` (freeze 5cd60580): 19 cross-category clashes (through `@extend`, `extend` in both orders, a programmatic `PottsSystem`, component names) rejected with the right message; same-category overrides and every PottsModels system still build; the five within-model rejections of today as regression guards. On eee2dec3 the 19 are accepted silently.
- **Review and merge.** Three rounds. Round 1: vector component names (`bias_1`) were not claimed, so a base vector parameter and an extension variable `bias_1` disagreed between `lookup` and `observe`. Round 2: component names claimed, a scalar named like a component is a clash even in its own category, the base side named in the message; `extend` now replaces a vector as a whole. Round 3: a shorter override vector would drop elements the base still reads (an internal `FieldError` at `solve`), so an extension's vector may be longer than the base's, not shorter. `@structural_parameters` stay outside the namespace (constructor keywords, never looked up by name).

## D-114 P6.0am: an `@extend`-bound name redeclared keeps its own default (2026-10-03, P6.0am; coordinator, from the P6.0al test author)

- **Context.** `@extend λ = base = Base()` assigns the base's symbolic `λ` to the constructor's local `λ`, which is also the constructor keyword `λ = nothing`; a redeclaration `@parameters λ = 3.0` then reads `λ === nothing ? 3.0 : λ` and takes the base's symbol as its default, so `PottsProblem` throws "does not reduce to numbers". The same holds for kind tables, and a keyword `Ext(; λ = 5)` is overwritten by the binding.
- **Rule.** Binding a base name never changes what a redeclaration means (D-113: the extension wins). A redeclared parameter or kind table takes the extension's default unless a constructor keyword is given; a redeclared variable takes the extension's default; a bound name that is not redeclared keeps the base's value (including values passed to the base call). A computed default that reads a bound name reads the model's one value of that name — the base's if not redeclared, the extension's (or its keyword's) if it is, regardless of declaration order — and is re-derived as usual (D-112).
- **Frozen acceptance** `p6_0am_extend_bound_override.jl` (freeze e2214d70): 62 tests with hand-computed energies; on a1c3ed57, 34 fail ("does not reduce to numbers" or a symbolic default); controls (unbound `@extend`, the base, a binding without redeclaration) pass.
- **Review and merge.** One round, approved (two `@extend`s binding one name, chains C→B→A with redeclarations, models in modules, `let` and functions, unusual names, computed defaults; fingerprints of the PottsModels systems unchanged). Follow-ups before merge: a regression test for a redeclared bound vector parameter, and declared names may not start with `#` (they would collide with the hidden keyword locals). A keyword for a bound name the extension does not redeclare stays a `MethodError` (overrides go through the base call).

## D-115 P6.0an: `remake` with a NamedTuple (2026-10-03, P6.0an; coordinator, from the D-112 review)

- **Context.** `remake(prob; p = (λ = 3.0,))` on a model's problem fell through to CorePotts' identity `remake_parameters`: `prob.p` silently became the one-field NamedTuple and the run failed later ("no field `V₀`"); any non-map value (`3.0`, `(3.0,)`, `[1.0, 2.0]`, `Any[:λ => 3.0]`) was taken as the parameter object the same way. A NamedTuple `u0` to `remake`/`reinit!` threw where symbol pairs work.
- **Rule.** On a model's problem, a NamedTuple `p` is a parameter map equal to the pairs of its fields: one change under D-112 (named values set, computed parameters re-derived iff an input is named, the scalar type kept, tables checked, an unknown field an `ArgumentError` naming it); one naming every parameter sets every value, `(;)` changes nothing. A vector or tuple of `Pair`s is a map too; a `PottsParameters` is a whole object; any other value is an `ArgumentError`, never a silent replacement. A NamedTuple `u0` (to `remake` or `reinit!`) is an operating point equal to its pairs. This holds wherever `remake` runs (ensemble `prob_func` included). A hand-written CorePotts problem (no model) keeps CorePotts' contract: `remake(prob; p = x)` replaces the parameter object with `x`.
- **Frozen acceptance** `p6_0an_remake_namedtuple.jl` (freeze 21e9525a): hand-computed energies on the P6.0ak fixture for NamedTuple ≡ pairs ≡ Dict, chains, whole tables, all-names and empty NamedTuples, Float32, NamedTuple `u0` in `remake` and `reinit!`, setters after a NamedTuple remake, an ensemble `prob_func`; negative controls (unknown name, variable name, mis-sized and asymmetric tables, non-maps, source problem unchanged); the hand-written CorePotts contract as a regression guard. On a1c3ed57, 41 of 54 recorded results fail or error, each from the fall-through; 114/114 against stubs.
- **Review and merge.** Two rounds. Round 1: maps, empty maps, symbolic keys, `remake(prob)` keeping `p`, checkpoints, rejections all correct; should-fix: a whole `PottsParameters` was accepted unchecked (another model's object failed later; a Float32 object turned a Float64 problem into Float32). Round 2: a same-type object is returned as given (the checkpoint fast path); otherwise its names must match (an `ArgumentError` names the differences) and its values are converted through the NamedTuple path. As in SciML, `p = missing`/`nothing` keeps the parameters and `u0 = missing`/`nothing` keeps the state (`reinit!` resets to the problem's state); any other `u0` that is not a state, pairs, a `Dict` or a NamedTuple is an `ArgumentError`.

## D-116 P6.0ap: parameter-setter loose ends (2026-10-03, P6.0ap; coordinator, from the D-112 review)

- **Context.** `setp(integ, [:λ, :w])` (a parameter and a state) set λ and then threw a `MethodError`; `SII.setsym(integ, [names…])` applied the names one at a time (order-dependent); `SII.remake_buffer(prob, prob.p, keys, vals)` overflowed the stack (SII's untyped fallback and its deprecated `Dict` method call each other); `setp`/`getp`/`integ.ps[x]` on a hand-written CorePotts problem threw `MethodError: symbolic_container(::Nothing)`.
- **Rule.** A `setp` list naming a state is an `ArgumentError` when the setter is built, pointing to `setu`/`setsym`; nothing is set. `SII.setsym(integ, list)` sets the list's parameters as one change (D-112, as `setp`) and its states as `setu` does; a single name is unchanged, an unknown name is an `ArgumentError`, and a rejected parameter value leaves the parameters unchanged. On a model's problem, `SII.remake_buffer(prob, prob.p, keys, vals)` returns a new parameter object equal to `remake(prob; p = Dict(keys .=> vals)).p` (same type, original untouched; an unknown key or a variable is an `ArgumentError`). On a hand-written CorePotts problem whose parameter object is a NamedTuple, its fields are its parameters by name: `getp`, `setp` (one name or a list) and `integ.ps[x]` work on an integrator (values converted to the field's type), `getp` works on the problem, `setp` applied to the problem is the "immutable, use `remake`" `ArgumentError`, a missing field is an `ArgumentError`; a parameter object that is not a NamedTuple has no names (`ArgumentError`).
- **Frozen acceptance** `p6_0ap_setter_loose_ends.jl` (freeze 0a38091e): hand-computed values and energies on the P6.0an fixture plus a cell variable; mixed `setp` on integrator, problem, function and model; `setsym` (parameters, states, mixed, tuple and symbolic lists, all-or-nothing); `remake_buffer` ≡ `remake` with a Dict; hand-written `getp`/`setp`/`ps` with the run using the new value; negative controls. The stack overflow is detected with a `which` check, never triggered in-process. On e006198b, 44 of 67 fail; 82/82 against stubs.
- **Review and merge.** One round, approved (every `setu`/`setsym` use checked: none with lists outside the new tests; states-only, symbolic-array, single-element and device cases unchanged; no ambiguities with SII/MTK/SciMLBase; `setp_oop`/`setsym_oop` now work on a model's problem). Follow-ups before merge: `remake_buffer` on a hand-written NamedTuple parameter object (reached by `setp_oop` now that such problems have names) no longer overflows; a read-only built-in in a list setter is reported as read-only. A mixed `setsym` is all-or-nothing for its parameters only (they are set first).

## D-117 P6.0ao: computed defaults that call functions or read kind tables (2026-10-03, P6.0ao; coordinator, from the D-112 review)

- **Context.** A computed default was accepted only if substituting the parameter values folded it to a number, so `w = sqrt(a₀) + π`, `exp`/`log`/`abs`/`min`/`max`/`floor`/`mod`/`rem`, `ifelse` and `c ? a : b`, a function registered with `@register_symbolic`, a kind-table read (`V₀[2]`, `J[P, Q]`) and kind tables whose entries call functions failed with "does not reduce to numbers"; `div`/`÷` threw a `MethodError` on `Num` at model build; a table entry reading another table (`R[kind] = [0, V₀[1] − 1]`) lost its index (table literals were not rewritten).
- **Rule.** A computed default (scalar or kind-table entry) is evaluated numerically: parameter values substituted, then evaluated with Julia's functions (Base math, `div`/`÷`, comparisons, `ifelse`, `π`/`ℯ`, registered functions) and kind-table reads. A kind-table read takes kind numbers as everywhere in a model (medium = 0, then `@kinds` order; a kind's name is its number): with `@kinds medium P Q`, `V₀[2] ≡ V₀[Q]`. Values are converted to the problem's scalar type. Re-derivation (D-112) sees through calls and reads.
- **Errors.** A default that cannot be a number is an `ArgumentError` naming the parameter: it reads a variable or built-in (`volume`, `kind`), draws (`rand()`; a default must be deterministic), or reads a kind outside the table. A function failing on the values raises at build or on `remake`, never a silent NaN.
- **Frozen acceptance** `p6_0ao_computed_defaults.jl` (freeze e82dc3f6): hand-computed values and energies on the P6.0ak fixture for Base functions, constants, `ifelse`/ternary/`&&`, `floor`/`mod`/`rem`, `div`/`÷`, a registered function, `V₀[2]`, `V₀[P]`, `J[P, Q] + J[0, 1]`, a table with `sqrt` entries, a table reading a table, chains, D-112 re-derivation and explicit-value survival (remake, operating point, setters), Float32 (to 4 eps); negative controls (`volume`, `kind`, `rand()`, out-of-range kind, a domain error, unknown or asymmetric values). On e006198b, 3 of 4 sub-testsets error for the stated reasons; 105/105 against stubs.
- **Review and merge.** Two rounds. Round 1: the evaluator correct on CPU (chains, lazy `ifelse`, nested table reads, D-112 re-derivation through `_div` and `at`, Float32, NaN, Int parameters; build and `remake` without computed defaults unchanged); blocker: `÷`/`div` on Float32 went through Base's Float64 `div` and did not compile on Metal; should-fix: `÷` in a field rate lost the automatic substep bound. Round 2: `_intdiv` has a Float64-free float method (`round((a - rem(a, b)) / b)`; matches Base while the Float32 quotient is exact, below 2^24, and the sign of a zero result may differ), integer and mixed methods, a zero derivative, and counts as a host op in substep bounds; a model may not define its own `div`/`÷`; a Metal test checks `÷` on parameters, variables, literals and the Int32 volume. A failing call on literal numbers only raises at model build.

## D-118 P6.0p: the fingerprint includes the tick cadence (2026-10-03, P6.0p; coordinator, from the P6.0k2 test author; amends D-016)

- **Gap.** The fingerprint hashed the generated code plus the lattice, spacing, neighbourhood, `T` and solver, so cadences kept outside the generated code were not hashed: the MTK clocks of discrete components (`_Gated` every/offset; `Clock(2)` fingerprinted the same as `ShiftIndex(t, 0)`, and `Clock(1)` at `mcs_duration` 0.5 the same as at 1.0); `@divide … Every(n)` when every rule shares one cadence (`Lifecycle.every`; no gate is generated); `@link`/`@unlink … Every(n)` (`HostPhase.every`). Update cadences already carry their gate in the code. The scope is wider than the row's clocks: the test author found the same gap for `@divide` and `@link`.
- **Rule.** The fingerprint also hashes the resolved cadence of every gated phase, the lifecycle pass and the host phases (every/offset in MCS after `mcs_duration`, or the clock spec). A model whose cadences are all the default (every = 1, offset = 0) keeps its fingerprint, so every published PottsModels system and every model without clocked components is unchanged. A checkpoint does not load into a problem with another schedule (`ArgumentError`, the existing fingerprint check).
- **Frozen acceptance** `p6_0p_cadence_fingerprint.jl` (freeze 3da6f97a): clock periods and phases at cell and model scope, the P6.0k network, `mcs_duration`, `@divide`/`@link` cadences; checkpoints refused across schedules (in memory and on disk) and accepted with the same schedule; controls against clock-time and division-count oracles; 11 fingerprints pinned on 4e81e1eb. On 4e81e1eb 36 of 80 fail (all targets); 80/80 against a stub.
- **Review and merge.** Two rounds. Round 1: the walk reaches every gated phase, host phase and the lifecycle pass; a period-1 clock with a phase is rejected when the clock is built, so it cannot be mis-gated; hashes are stable across sessions and computed once per problem; should-fix: the `Adaptive` ODE solver keeps `dt = mcs_duration` as solver data, so `mcs_duration` 1.0 and 0.5 fingerprinted alike and a checkpoint crossed them. Round 2: a non-default `mcs_duration` is hashed too (pins unchanged). The acceptance law's offset (`Metropolis`/`Barker`) is not fingerprinted either: P6.0aq.

## D-119 P6.0q: a fold reading `time` in a cell ODE runs on Metal (2026-10-03, P6.0q; coordinator, from the P6.0n test author)

- **Finding.** A population fold whose body reads `time` is not hoisted (`time` is not in the model environment); the cell-ODE kernel computes it per cell from the cells' start-of-step ODE state (Jacobi, D-086). A fold reading only `mcs` is hoisted to a model slot; in a rate with both kinds, only the `mcs` one is. Within MCS n's ODE step, `mcs` = n−1 and `time` is the stage or substep time. The `InvalidIRError` (`jl_new_opaque_closure_jlcall`) reported in the row came from the per-cell `rhs` closure that D-103/D-104 removed: on 4e81e1eb the P6.0n fold fixture and the time, mcs, both and two-fold variants under `ExplicitEuler()`, `ExplicitEuler(substeps = 4)` and `RK4()` run on Metal bitwise equal to the CPU Float32 run. No source change.
- **Frozen acceptance** `p6_0q_time_fold_metal.jl` (freeze f39569c8): a regression guard (CPU against a Float64 Jacobi oracle in Float64 and Float32 under Sequential and Checkerboard, negative controls; Metal against CPU Float32 within 4 ulp), wired into `test/gpu.jl` as `P60qOnMetal`.

## D-120 P6.0t: integral refreshes only for readers after the sweep (2026-10-04, P6.0t; coordinator, from the P6.0m3 review)

- **Rule.** The start-of-after-MCS integral refresh covers only integrals read after the sweep (after-MCS updates, equations, lifecycle, discrete and link rules) that the after block does not dirty; integrals read only by the before block or the temperature are fresh from the previous boundary (`end_mcs`/`at_init`). An integral read only by `@observed` has no cell column and no refresh in any phase; observed queries (`sol[:x]`, `observe`) compute it from the saved state (with fold slots where it has hoisted folds), in the problem's scalar type. Values seen by every reader are unchanged. Fingerprints change only for models with such integrals; the PottsModels systems and integral models without such readers keep theirs.
- **Measured** on 432a0a74: 8 observed-only integrals on 128×128 cost 3.6× per warm MCS (2.17 vs 0.61 ms).
- **Frozen acceptance** `p6_0t_integral_refresh.jl` (freeze f020226e): phase tuples of the `PWaste` probe and a mixed-reader fixture (exact refreshed columns and layout), the observed-only model's phases equal to the model without `@observed`, values of every reader against oracles from saved states on Sequential and Checkerboard (before-block, after-block, temperature twin, observed via `sol[:x]`/`observe`), zero warm allocations, per-MCS cost with 8 observed-only integrals ≤ 1.1× without, 8 fingerprints pinned. On 432a0a74, 19 of 109 fail (all on the waste); a prototype passes 109/109.
- **Review (P6.0t, approved, round 2).** Round 1 found (a) an integral read only inside a population fold of a cell-scope discrete component lost its refresh after the sweep — the readers were collected from the compiled ticks, whose folds are slots — so that component ran one MCS behind; readers are now collected from the uncompiled statements; and (b) moving `@observed` to the end reordered the stored integrals (and the fingerprint) of models without observed-only integrals; the old gather order is kept and observed-only operands are appended. Both have non-frozen regression tests that fail on the round-1 commit. Stored integrals keep their order, layout and fold-slot names; observed-only fold slots come last and stay zero in saved states (scratch for observed queries). Measured: 8 observed-only integrals cost 0.97–1.06× per warm MCS (was 3.6×). At merge, the five PottsModels pins in this file that D-122 moved (GranerGlazier, WortelAct, WortelAct connected, MerksVasculogenesis, OpenVTGrowingMonolayer) were re-pinned to the D-122 values (pin lines only; sha256 updated).

## D-121 P6.0aq: the fingerprint includes the acceptance law (2026-10-03, P6.0aq; coordinator, from the P6.0p review; amends D-016, after D-118)

- **Gap.** The `@sweep` acceptance law (`Metropolis`/`Barker`) and its `offset` are solver data in `CPMFunction.acceptance`, outside the generated code, so every law/offset combination fingerprinted alike and a checkpoint loaded across them. Temperature and `combine` are lowered into the generated temperature function (already hashed); `mcs_duration` is hashed since D-118; the T ≤ 0 tie rule is fixed, not a parameter.
- **Rule.** The fingerprint also hashes a non-default acceptance law (anything other than Metropolis) and a non-zero offset; the default (Metropolis, offset 0, given or omitted) keeps its fingerprint, so every PottsModels system is unchanged. A checkpoint does not load into a problem with another law or offset (`ArgumentError`).
- **Not in the fingerprint.** The algorithm (`SequentialCPM`/`CheckerboardCPM`) and its `acceptance`/`proposal` keywords are run choices made at `init`, like the backend: a checkpoint may continue under another algorithm, a statistical not exact continuation (D-063).
- **Frozen acceptance** `p6_0aq_acceptance_fingerprint.jl` (freeze 763e2a2d): six law/offset variants pairwise distinct in Float64 and Float32; checkpoints refused across them in memory and on disk and accepted with the same law; controls on accepted-copy counts, temperature/`combine` hashing and cross-algorithm continuation; default fingerprints pinned. On 432a0a74, 44 of 116 fail (all targets); 116/116 against a stub.
- **Follow-up.** `@relations proposal`/`contact` are not fingerprinted either (P6.0ar).
- **Review (P6.0aq, approved, round 1).** All five `SweepSpec` fields are now covered (temperature and combine through the generated code, `mcs_duration` by D-118, law and offset here); `CPMFunction` has one construction site, so `remake` is covered; `-0.0` equals the default; NaN gets its own stable fingerprint. Nits recorded as P6.0as: a NaN offset is accepted by `sweep_spec`, and a user closure as `combine` hashes by its compiler-generated name, which may differ across sessions. A Float32 offset below Float32 precision fingerprints apart from the default although it runs identically — safe (refuses a loadable checkpoint), kept.

## D-122 P6.0ar: the fingerprint includes the proposal and contact neighbourhoods (2026-10-04, P6.0ar; coordinator, from the P6.0aq test author; amends D-016, after D-121; re-pins D-104/D-107/D-108/D-118/D-121 fixtures)

- **Gap.** `@relations proposal` and `@relations contact` were not hashed: proposal omitted, `Moore(1)` and `VonNeumann(1)`, and contact `VonNeumann(1)`/`Moore(1)`/`Moore(2)`, all fingerprinted alike, so a checkpoint loaded across copy neighbourhoods and across contact neighbourhoods although the contact one changes the energy.
- **Rule.** The fingerprint also hashes the proposal and contact neighbourhoods, each resolved on the problem's lattice (`CorePotts.relation(spec, lattice)`: canonically ordered offsets and weights) and hashed with its role, only when the resolved relation differs from its default — `VonNeumann(1)` for the proposal, the lattice's `neighborhood` for the contact. A spec that resolves to the default fingerprints like omission (`VonNeumann(1)`, `NeighborOrder(1)`, a permuted `Stencil`, `Moore(1)`/`Hex(1)` on a hexagonal lattice); weights hash by value, so a weight closure is session-stable. A checkpoint does not load into a problem with another proposal or contact neighbourhood (`ArgumentError`).
- **Model vs run.** `@relations proposal` is part of the model and fingerprinted; the algorithm's `proposal` keyword (`SequentialCPM(; proposal)`) stays a run choice under which a checkpoint may continue (D-121).
- **Re-pinned.** The default proposal is `VonNeumann(1)`, not the lattice neighbourhood, so no rule keeps both the models declaring `proposal = Moore(1)` and the fixtures omitting it on their old pins. The fewest pins move by hashing only non-defaults: GranerGlazier, WortelAct, WortelAct connected, MerksVasculogenesis, OpenVTGrowingMonolayer and the `P60AF_FP_COUNTER` fixture get new pins in the earlier frozen files (`p6_0p`, `p6_0aq`, `p6_0x`, `p6_0ag`, `p6_0ah`, `p6_0af`), whose sha256 entries are updated under this decision. Only fingerprint pins change; no dynamics. AkeebInvasion, SingleDivisionFixture and every fixture without `@relations` keep theirs.
- **Frozen acceptance** `p6_0ar_neighbourhood_fingerprint.jl` (freeze 2dd345e2): pairwise-distinct fingerprints across proposal and contact neighbourhoods (square 2D Float64/Float32, a VonNeumann-neighbourhood lattice, hex, 3D), explicit default equal to omission, checkpoints refused in memory and on disk and loaded across explicit default/omission, energy and acceptance controls, a lattice-geometry negative control, unchanged pins, and the five moved systems differ from their old pins. On f137f929, 113 of 291 fail (all targets); a prototype passes 291/291.
- **Follow-up.** Named relations (`@relations far = Ball(2.0)`) and inline gather relations (`Moore(1)(42)`) collide the same way (P6.0at).
- **Review (P6.0ar, approved, round 2).** Round 1 found that resolving the default relations threw on a thin periodic lattice (width 1 or 2) where a model declares a non-aliasing `Stencil` and used to build; the default is now resolved leniently (an unresolvable default differs from any declared relation), with a non-frozen regression test. Accepted, safe direction: relations compare bitwise, so a `-0.0` weight or a constant `Weighted` equal in energy to the unweighted spec fingerprints apart and refuses a checkpoint that could have loaded.

## D-123 P6.0as: `@sweep` validation and `combine` identity (2026-10-04, P6.0as; coordinator, from the P6.0aq review; amends D-016/D-121)

- **Gap.** `sweep_spec` accepted a non-finite `offset`: NaN makes every acceptance comparison false, ±Inf accepts or rejects every copy. The cell-scope temperature interpolates the `combine` object into the generated code and the fingerprint hashes its printed form. A named function prints its module path and name and a callable struct its type and fields — both stable across sessions — but an anonymous function or closure prints as a compiler-generated, session-counter name (`var"#2#3"()` vs `var"#23#24"()`) and its body is never hashed: the same model is refused across sessions, and two different anonymous functions can collide across sessions, letting a checkpoint load across them.
- **Rule.** `offset` must be finite: NaN, Inf and -Inf are an `ArgumentError` from `@sweep` (`sweep_spec`), for Metropolis and Barker, Float64 and Float32. `combine` must have a stable identity: a named function (a constant global binding, identified by module path and name) or an instance of a named callable type (identified by its printed type and fields). Concretely, `combine` is rejected (an `ArgumentError` from `@sweep` naming `combine`, whatever the temperature's scope) when its printed form — exactly what the fingerprint hashes — contains a compiler-generated name (`var"#`): an anonymous function, a closure, a local named function, a function in a gensym'd module, or a wrapper holding one (`Base.Fix2(anon, 1)`, a struct with an anonymous-function field, `min ∘ anon`); stable wrappers such as `min ∘ max`, `splat(min)` and `Base.Fix2(min, 1)` are accepted. `offset` must be a `Real` that is finite after conversion to Float64; to carry parameters, define `f(a, b) = …` or a callable struct. Generated code for named `combine` is unchanged, so every fingerprint and pin stays. A named function's body is not hashed: redefining it under the same name is the user's contract, as for any user function. Docs that showed an anonymous `combine` (the CC3D `ArithmeticAverage` translation) use a named function.
- **Frozen acceptance** `p6_0as_sweep_validation.jl` (freeze dd644a5f): non-finite offsets rejected and finite ones accepted (0, -0.0, 2, -1.5, 2.0f0, 1e300); the four unstable `combine` forms rejected at cell, copy and Barker scope; named and callable-struct `combine` fingerprint alike in a perturbed subprocess whose checkpoints load here, another struct's refused; no `var"#` in the temperature code; negative controls; unchanged pins. On b14a81cd 38 of 160 fail (all targets); a prototype passes 182/182.
- **Follow-up.** `mcs_duration` is not validated either (NaN or ≤ 0) (P6.0av).
- **Review (P6.0as, approved, round 2).** Round 1 found the first check (type name and global binding) wrong both ways — it accepted `Base.Fix2(anon, 1)`, a struct holding an anonymous function and gensym'd-module functions, and rejected `min ∘ max`, `splat(min)` and singleton `<: Function` structs; the check now tests the printed form, with a non-frozen regression test that fails on the round-1 commit. Non-Real offsets give the same `ArgumentError`; a finite `BigFloat` that overflows Float64 is rejected (coordinator, round-2 nit). A Pluto workspace function is accepted but tied to its notebook session (documented).

## D-124 P6.0at: the fingerprint includes named and inline gather relations (2026-10-04, P6.0at; coordinator, from the P6.0ar test author; amends D-016, after D-122; re-pins D-121/D-122 fixtures)

- **Gap.** A named relation (`@relations far = Ball(2.0)`, read by `contacts(far)` or a fold `for n in far(site)`) and an inline gather relation (`Moore(1)(42)`, numbered `gather1`, `gather2`, … by the compiler, D-107) reach the generated code only as fields of the run context (`ctx.far`, `ctx.gatherN`). Their resolved offsets and weights are runtime data, so the code hash sees the name and which statement reads which gather, but not the relation itself. Measured on e4b6ab51, these fingerprinted alike and let a checkpoint load across them although the energy or the dynamics differ: `contacts(far)` with Ball(2.0)/Ball(3.0)/Moore(2)/Weighted 2 vs 3; a named fold in an energy, cell ODE or drive; an inline `Moore(1)(40)` vs `Moore(2)(40)` in an energy, cell ODE, drive or site update.
- **Rule.** The fingerprint also hashes every named or inline gather relation that the generated code reads (a `ctx.<name>` read in a recorded function other than `lattice`, `contact` and `surface`). Each is resolved on the problem's lattice (`CorePotts.relation(spec, lattice)`: canonically ordered offsets, weights by value) and keyed by its context name, in sorted order. There is no default to skip. Specs that resolve alike fingerprint alike: `Ball(1.5)`, `Moore(1)` and a permuted Stencil on a square lattice; `Hex(1)` and `Moore(1)` on a hexagonal lattice; `NeighborOrder(3)` and `Moore(1)` in 3D; `NeighborOrder(2)` and `Moore(1)` inline; a permuted inline Stencil. A checkpoint does not load into a problem with another such relation (`ArgumentError`). Proposal and contact keep their D-122 rule.
- **Already in the code, not hashed again.** The relation's name (renaming `far` changes the fingerprint, as renaming anything the code reads does) and the use site of each inline gather.
- **Not in the fingerprint.** A relation that nothing reads; a relation read only by `@observed` quantities (observed functions are built at query time and are not fingerprinted; they change no dynamics and no saved state); `surface` (not declarable, always the lattice neighbourhood).
- **Re-pinned.** A gather has no default, so every system that reads one moves: WortelAct (both variants; its drive folds an inline `Moore(1; include_self = true)`) and the P6.0ah fixture `P60ahAt` (an inline `Moore(1)(42)`). Their pins in `p6_0aq`, `p6_0p`, `p6_0t`, `p6_0x` and `p6_0ah` (9 lines) are re-pinned under this decision by the implementer (pin lines only; sha256 updated), as are the same systems' pins in any frozen file merged meanwhile (e.g. `p6_0av`), at merge. Only fingerprint pins change; no dynamics. GranerGlazier, MerksVasculogenesis, OpenVTGrowingMonolayer, SingleDivisionFixture, AkeebInvasion, XPlain/XPair (the ROADMAP's example was wrong: they read no gather) and every relation-free fixture keep theirs.
- **Frozen acceptance** `p6_0at_relation_fingerprint.jl` (freeze a5a2ed6f): twins pairwise distinct per usage (contacts, named fold in an energy, cell ODE, drive, inline gather in an energy, cell ODE, drive and site update; square 2D Float64/Float32, hex, 3D); alike-resolving specs equal; unused and observed-only relations not hashed; checkpoints refused in memory and on disk, and loaded across alike or unread relations; energy, ODE and site-update controls; renaming and use-site controls; unchanged pins; the moved systems differ from their old pins. On e4b6ab51, 82 of 274 fail (all targets); a prototype passes 274/274.

- **Review (P6.0at, approved, round 2).** Round 1 approved: every relation read in codegen is a literal `ctx.$rel` (folds, contacts), so the walk misses none; every use site (division and link `when`, model ODE, temperature, constraint, field PDE, Adaptive cell ODE) moves the fingerprint; printing is session-stable (Int32 offsets, Float32 weights); no double hashing with D-122; about 6 µs per build. Its nit (a relation named `spacing` or `lattice` hit a `FieldError` in the new loop) is fixed in round 2: those names, with `mobility`, are refused in `mtkcompile` with CorePotts' reserved-names error. At merge the coordinator re-pinned WortelAct (both variants) in `p6_0as` and `p6_0au`, merged meanwhile. Follow-up P6.0ax (an inline gather in a division `when`, pre-existing).

## D-125 P6.0au: `integral` is not available in drives and constraints (2026-10-04, P6.0au; coordinator, from the P6.0t review)

- **Gap.** `_check_geometry` rejected `integral` only in energies, and `_integrals_folds` never gathered it from `@drive` or `@constraint`, so it had no cell column. A plain `integral(u)` failed during lowering with the generic "is per cell" message; inside a population fold over cells (`sum(integral(u) for c in cells if c == new)`, also in `Chemotaxis` arguments) the model and problem built and the first `solve` failed with `FieldError: … no field integral_…`.
- **Rule.** Drives and expression constraints are evaluated per copy attempt inside the sweep (`_delta_H_expr`; the constraint test), where σ changes at every accepted copy, while an integral is refreshed only between sweeps. As in energies, any `integral(…)` in a `@drive` (including `Chemotaxis` arguments) or an expression `@constraint` is an `ArgumentError` at build (`mtkcompile`) naming `integral`, the statement, and the workaround: keep it in a cell variable updated `@before_mcs` (`s ~ integral(x)`) and read `s[new]`, `s[old]`. `connectivity` and `no_extinction` carry no user expression. Integrals in updates, equations, the lifecycle, link rules, discrete ticks, the temperature and `@observed` are unchanged; no fingerprint changes.
- **Frozen acceptance** `p6_0au_integral_readers.jl` (freeze f100885b): rejections for 4 drive forms (plain, cell fold, a block next to an accepted drive, `Chemotaxis` strength), 3 constraint forms (plain, cell fold, next to `connectivity`/`no_extinction`) and `integral(Pre(u))` in a drive; the `@before_mcs` workaround as a constraint and as a drive against an oracle from saved states on Sequential and Checkerboard (the vetoed cell never gains a site, a control without the veto grows); integrals elsewhere still work; energies still reject; integral-free cell folds in drives and constraints as a negative control; 11 fingerprints pinned. On e4b6ab51, 41 of 113 fail (all on the gap); a prototype passes 113/113.
- **Follow-up.** `@on_copy` right-hand sides reading an integral run during the sweep and read the value from the last boundary (P6.0aw).
- **Review (P6.0au, approved, round 1).** No bypass found: `Chemotaxis` (`when=` and field argument), `ifelse`, `@extend` bases and extensions, functional `extend`, 3D; no false rejection (a variable named `integral_u`, integrals in ODEs and `@after_mcs`, model-scope folds). The documented workaround runs as written on Sequential and Checkerboard. A copy-scope temperature may read `integral` directly (start-of-MCS value, kept on purpose); the drive page says so (coordinator, merge).

## D-126 P6.0av: `@sweep mcs_duration` validation (2026-10-04, P6.0av; coordinator, from the P6.0as test author; amends D-118/D-123)

- **Gap.** `sweep_spec` stored `Float64(mcs_duration)` unchecked, and every reader trusts it: the `Adaptive` interval `[mcs, mcs + 1) × mcs_duration`, the `ExplicitEuler`/`RK4` step, the field step's substep count, the clock cadence `dt / mcs_duration`, and the fingerprint. Measured on ab26cd37 for `D(y) ~ -y`: NaN or ±Inf builds; `Adaptive` then throws `NaNTspanError` at the first solve, Euler and RK4 return Success with y = NaN, the auto-substep field step throws `InexactError`. 0 freezes time (Success, y = 1); −1 runs time backwards silently (`Adaptive` y = e³). A non-Real value (`:a`, `1 + 1im`, `"1"`, a symbolic parameter) throws a `MethodError` or `InexactError` naming neither `@sweep` nor `mcs_duration`. `big"1e400"` is stored as Inf and `big"1e-400"` as 0.0.
- **Rule.** `mcs_duration` must be a `Real` that is finite and > 0 after conversion to Float64. Anything else is an `ArgumentError` from `@sweep` (`sweep_spec`) naming `mcs_duration`, so building the system throws, not `PottsProblem` and not the first `solve`, for Metropolis and Barker, whether the value is a literal, a constructor keyword or comes through `@extend`. Rejected: NaN, ±Inf (Float64 and Float32), 0, −0.0, negative values, a `BigFloat` that overflows or underflows Float64, non-Real values and a symbolic parameter (the duration is a number of the sweep, not a model parameter). Every positive finite value (Int, Float32, Rational, BigFloat, 1e300, floatmin) is accepted as before and stored as `Float64(mcs_duration)`. Generated code and fingerprints are unchanged, so every pin stays. `PottsProblem`, `remake` and `solve` do not take `mcs_duration`, so `@sweep` is its only public entry point. Coordinator: the `offset` (D-123) and `mcs_duration` checks also live in an inner `SweepSpec` constructor, so a hand-built `SweepSpec` passed to `PottsSystem(; sweep)` cannot bypass them (the messages stay those of `@sweep`).
- **Frozen acceptance** `p6_0av_mcs_duration.jl` (freeze 6372ed38): invalid durations rejected at build per law, as literals, structural keywords, in field and clock models, as a symbolic parameter and through `@extend` (own `@sweep` and inherited base keyword); the same values rejected by `Potts.sweep_spec`; accepted values stored exactly; hand-checked runs at md = 0.5 (Euler 0.125, RK4, `Adaptive` e^−1.5, md = 2 e^−6, field 144·0.975³, clock ticks [0, 0, 1, 1, 2]); `PottsProblem`, `remake` and `solve` refuse the keyword; negative controls; unchanged pins (14 fixtures and every PottsModels system). On ab26cd37 95 of 176 fail (all in the rejection section); a prototype passes 231/231.
- **Review (P6.0av, approved, round 1).** The round-2 implementation also moved the D-123 `combine` check into the `SweepSpec` constructor (coordinator), so a hand-built spec cannot skip any of the three checks; `methods(SweepSpec)` is the inner constructor alone; serialization round-trips; fields stay Float64, pins unchanged. Coordinator nits at merge: the rejected value's type is in the message (a `Num` wrapping 0.5 printed as "got 0.5"), docstring order. At merge, WortelAct's pins in `p6_0av` re-pinned under D-124.

## D-127 P6.0b2: re-declared edge variables keep their relationship; operating-point edge values seed initial links (2026-10-04, P6.0b2; coordinator, from the P6.0b review; amends D-058)

- **Gap.** `_bind_edge_scope` bound an unscoped `x(edge)` to its body's only relationship before `@extend` merged, and `extend` keeps the extension's variable of each name. An extension that re-declared a base edge variable to change its default (`@variables rest(edge) = 9.0`, the D-114 idiom) while adding one relationship of its own (`tether`) moved `rest` to `tether`; `mtkcompile` then failed on the base's own term ("edges(bond) reads `rest`, an edge variable of relationship `tether`"); with no own relationship over a two-relationship base, or with two own, it was "ambiguous"; an explicit `rest(tether)` moved the payload silently when no base term read it. Separately, `_initial_state` skipped edge variables, so `:rest => 9.0` (or `[1.0, 2.0]`) in the operating point was accepted and ignored.
- **Rule.** (1) An unscoped `x(edge)` in an extension body that re-declares an inherited edge variable keeps the inherited relationship, whatever relationships the body declares; only its default (D-114) is the extension's. A new unscoped edge variable keeps D-058 (the body's only relationship; "ambiguous" with several). An explicitly scoped re-declaration naming another relationship is an `ArgumentError` when the extension is built (`@extend`/`extend`), naming the variable and both relationships: a payload column belongs to one relationship (as a name keeps its category, D-113). (2) An edge variable's operating-point value is its initial value on every initial link of its relationship (both ends, converted to `T`), at construction and in `remake(prob; u0 = op)`. It must be a number; anything else is an `ArgumentError` naming the variable (per-link values are not guessed). Links created by `@link` start at the declared default (compiled into the rule). The operating point is state and never changes the fingerprint; generated code and every pin are unchanged; no runtime path changes, so no gate run.
- **Frozen acceptance** `p6_0b2_link_followups.jl` (freeze 55c75d6b): re-declarations with one, two or no own relationships (and `@extend rest = …`) matched against explicitly scoped oracles by edge-variable sets, initial payloads, hand-computed total energies (3264 + 72 + 6, …) and fingerprints; the extension's own term reading the re-declared variable; explicit re-scope rejected at build (read and unread bases); D-058 controls; operating-point values (Int, Float32, per relationship, no initial links, `remake`, kept through a run, `selfcheck`); `@link`-made links at the default; non-numbers rejected; fingerprints pinned. On 18861b25, 25 fail and 2 error of 56 (all targets); a prototype passes 77/77 and the Potts and PottsModels suites.
- **Review (P6.0b2, approved, round 2).** Round 1 found that functional `extend` disagreed with `@extend` for a body built on its own (its unscoped `rest(edge)` was already bound to the body's only relationship, then rejected as a re-scope). An implicit D-058 binding is now marked internally (`implicit_relationship`, not DSL, not hashed: marked and unmarked bodies fingerprint alike) and re-bound to the base's relationship by `extend`; the mark is dropped after each merge, so only the extension's own variables are re-bound. Also: two `@extend` bases declaring one edge variable on different relationships is a clear "rename one" error; re-declaring an inherited edge variable as a cell variable (or the reverse) is an `ArgumentError` at build, not a `KeyError` at `mtkcompile`; an operating-point edge value may be a parameter expression, evaluated at construction (a later `remake` of parameters does not re-seed it). A chained functional `extend(extend(x, a), b)` with conflicting bases still gets the re-declaration wording (nit).

## D-128 P6.0v2b: a custom frozen rule declares the leaves it reads (2026-10-04, P6.0v2b; coordinator, from the P6.0v2 review; audit R4; refines D-081/D-092)

- **Gap.** A custom-rule `refresh_frozen!` (`remake_frozen` without `frozen_kinds`) snapshots the whole state to the host on a device: σ, every cell column, every model, site and history leaf, so per-refresh bytes grow with quantities the rule never reads. A custom rule is host code and cannot be scanned for its reads.
- **Rule.** `CorePotts.frozen_reads(sys)` (public, not exported, beside `frozen_varies`/`frozen_kinds`; default `nothing`) is a tuple of Symbols, each `:σ` or a cell column name, as in `HostPhase(...; reads)` (D-092). With a declaration, a device refresh copies only those leaves to the host, then the mask up; what the rule sees in undeclared leaves is unspecified. `nothing` keeps the whole-state snapshot. A name that is neither `:σ` nor a cell column is an `ArgumentError` by the first refresh, on every backend. The standard rule ignores the hook and still runs on the device. Model and site leaves cannot be declared; a rule that reads them uses the fallback. No gate model uses a custom rule, so warm steps are unchanged.
- **Frozen acceptance** `p6_0v2b_frozen_refresh_bytes.jl` (freeze ed72ba35): on Metal, per-refresh (syncs, transfers, bytes) of a declared custom rule steady and identical between twins differing only in unused cell, model and site quantities, bytes ≤ σ + read columns + nsites (mask up) + 16 B; the standard rule twin-invariant and ≤ 16 B for a direct call; the undeclared fallback's twins differ (negative control); masks hand-checked (16, then 32 frozen sites) and equal to today's on the CPU. On 18861b25, 3 of 70 CPU and 6 of 90 Metal tests fail (all the gap); a prototype passes 74 CPU and 94/94 Metal.
- **Review (P6.0v2b, approved, round 2).** Round 1 found that a repeated name (`(:σ, :stiff, :stiff)`) passed `init` and failed on Metal at the first refresh with an `ErrorException` (duplicate `NamedTuple` field); a declaration must now be a tuple of distinct Symbols, checked at `init` and every refresh on every backend. Undeclared leaves are the live device arrays (docstring): reading them on the host errors on scalar indexing, and `Array(...)` works but is an uncounted transfer; making them absent was considered and not done, to keep the `HostPhase` (D-092) precedent. Metal per refresh: declared (1, 3, 1408) for both twins; undeclared (1, 6, 1792) / (1, 11, 3460); standard rule (0, 1, 12).

## D-129 P6.0aw: `integral` is not available in `@on_copy` right-hand sides (2026-10-04, P6.0aw; coordinator, follow-up of D-125)

- **Gap.** `_dry_lower` checked drives and expression constraints with `_check_copy_integral` (D-125) but lowered an `@on_copy` right-hand side without it. A bare `integral(u)` failed with the generic "is per cell" message. Inside a fold over cells (`sum(integral(u) for c in cells if c == new)`, also with `Pre(u)`), site-scope (`x[target] ~ …`) and cell-scope (`y[new]`/`y[old] ~ …`) on-copy updates built and ran on Sequential and Checkerboard, writing the integral as refreshed at the start of the MCS while σ moved at every accepted copy. When an energy read the written cell variable (D-045), that stale value entered ΔH.
- **Rule.** An `@on_copy` right-hand side runs at every accepted copy inside the sweep, while an integral is refreshed only between sweeps. As in drives and constraints, any `integral(…)` in it (bare, in a fold, with `Pre`, at any scope) is an `ArgumentError` at build (`mtkcompile`, hence `PottsProblem`) naming `integral`, the statement (`@on_copy`) and the workaround: keep the integral in a cell variable updated `@before_mcs` (`s ~ integral(x)`) and read `s[new]`, `s[old]` — the same start-of-MCS value, explicitly. The message is D-125's, with "every accepted copy" in place of "every copy attempt". Integrals in updates outside the sweep (`@before_mcs`, `@after_mcs`, including integrals of variables that `@on_copy` writes), equations, the lifecycle, link rules, discrete ticks, `@observed` and the temperature (D-125 review) are unchanged. No fingerprint changes.
- **Frozen acceptance** `p6_0aw_on_copy_integral.jl` (freeze 4bee5b45): 7 rejected forms (3 site-scope, 4 cell-scope including a write an energy reads), each at `mtkcompile` and `PottsProblem`; the `@before_mcs` workaround read by a site and a cell `@on_copy` against a hand oracle on Sequential and Checkerboard, with margins that separate a stale from a fresh read; negative controls (integral-free `@on_copy`, an `@after_mcs` integral of an on-copy-written variable); 5 fingerprints pinned (WortelAct's at its pre-D-124 value: re-pin at merge if P6.0at lands first). On bff31b39, 72 of 396 fail (all the gap); a prototype passes 396/396.
- **Review (P6.0aw, approved, round 2).** Round 1 found that an `integral` in the left-hand-side index (`y[ifelse(…integral…, new, old)] ~ 1.0`) bypassed the check (an internal `FieldError` at `PottsProblem`, or a silent stale read when the integral was also gathered); the check now covers both sides of an on-copy statement. Manual pages (variables table, drive note) name on-copy updates. At merge, WortelAct's pins in `p6_0aw` re-pinned under D-124.

## D-130 P6.0c2: canonical solver strings, session-bound closures and reserved suffixes (2026-10-04, P6.0c2; coordinator, from the P6.0c round-3 review; amends D-016/D-078, after D-123)

- **Gap.** Measured on c0f80561: (a) `_canonical_value` printed a non-scalar value nested deeper than 8 levels, or a cyclic one, by its type alone, so `Adaptive(Rodas5P(); isoutofdomain = Guard(nest(12, 1.0)))` and the same with `2.0` fingerprinted alike; given to two unknowns through `solvers`, they shared one group and the second solver was silently dropped. (b) A closure or anonymous function in an `Adaptive` solver (a keyword such as `isoutofdomain`, or an algorithm field such as `step_limiter!`) printed by its compiler-generated name (`var"#2#3"{…}`) and its body was never hashed: three fresh processes, two with the same script and one with another closure body at the same position, all fingerprinted `0xc32461b1959c28dc`, and a checkpoint loaded across all of them. (c) `_check_internal_suffix` missed vector names (`@variables v__ode(cell)[1:2]`, `@parameters d__tick[1:2]`), `@observed` names and component observed names (`comp₊w__ode`); component unknowns, discrete nodes and component parameters were already rejected.
- **Rule.** (1) A value nested deeper than the canonical printer's cap (8 levels), or a cyclic value, is an error when its canonical string is built, never a truncation; for a solver, `PottsProblem` and `remake` throw an `ArgumentError` naming `Adaptive` and, for a keyword, the keyword. Grouping by `isequal` is rejected: a fingerprint cannot depend on it. (2) A closure or anonymous function in an `Adaptive` solver is accepted (coordinator, AUTONOMY §2 principle 1: idiomatic SciML; unlike D-123's `combine`, which enters generated code and stays rejected). When the canonical solver string contains a compiler-generated name (`var"#`), the fingerprint also hashes a per-session token drawn when Potts loads (`__init__`). Within a session the same closure, or one of the same type and captures, fingerprints alike and its checkpoints load; different closures fingerprint apart. Across sessions the fingerprint always differs, so a checkpoint never loads into another session (the fingerprint `ArgumentError`) and cannot collide with another session's closure. Named functions, callable structs and stable wrappers (`Returns(false)`) fingerprint as before and load across sessions; to resume in a new session, use one of these (documented). The canonical string and solver grouping are unchanged; the token enters only the fingerprint hash. (3) Every declared name is checked for `__ode`, `__tick` and `__next`, including vector names, `@observed` names and component observed names; the `ArgumentError` at build or `mtkcompile` names the quantity and the suffix. A name that contains a suffix elsewhere (`v__oder`, `ode__d`) is accepted. (4) `tools/fingerprint_compare.jl [A] [B]` compares the fingerprints of the published systems and ODE fixtures between two checkouts (B defaults to a `git archive HEAD` copy of A): the merge check of D-078. (5) AUTHORING §6 and INTERNALS §1.6 state the after-MCS order: updates, field steps, cell ODEs, model ODEs, discrete ticks, links; then the lifecycle and the boundary. No closure-free canonical string changes, so every pin stays.
- **Frozen acceptance** `p6_0c2_canonical_followups.jl` (freeze 4a25bad4, re-frozen c7ec6f61 for rule 2): depth-12, depth-30, cyclic and algorithm-field values rejected via `ode_solver`, `solvers` and `remake`; 7 closure forms build via all three; in-session identity, distinctness and checkpoint loads; three fresh subprocesses whose same-source and other-body closures fingerprint apart and refuse each other's checkpoints; stable solvers alike in a perturbed subprocess and load; suffix rejections with regression guards and accepted-name controls; the tool exists and parses; 19 unchanged pins. On c0f80561, 31 of 199 fail (all targets); a prototype passes 200/200.
- **Review (P6.0c2, approved, round 1).** Every compiler-generated form tried prints with `var"#` (anonymous, module and local closures, `@eval` gensyms, nested in `Fix1`/`ComposedFunction`/generators); only `Base.Experimental.@opaque` does not, and it fails loudly at the depth cap. Realistic SciML values (`ContinuousCallback` of named functions, `AutoFiniteDiff`, Krylov linsolves) build and are not session-bound. Published models reach canonical depth 2; a closure-weighted gather capturing a dict of vectors, 5. Token: the child task leaves the caller's own `rand` stream unchanged but shifts the seeds of tasks spawned afterwards (comment corrected); with a seed set before loading, uniqueness rests on `time_ns()` and `getpid()`. Nits applied: deep values outside the solver path (gather-spec ordering, `_symkey`) are an `ArgumentError` naming the part; the compare tool removes its archive copy and warns on a dirty tree (tracked files). Pre-existing, filed and folded into P6.0z (D-134): a closure-weighted lattice neighbourhood is not hashed by value (P6.0az).

## D-131 P6.0ay: the P6.0t cost check is structural, with a loose paired timing backstop (2026-10-04, P6.0ay; coordinator, from the P6.0au merge; re-freezes D-120's `p6_0t_integral_refresh.jl`)

- **Gap.** D-120's frozen cost check (8 observed-only integrals cost per warm MCS `to <= 1.1 * tl`, minimum of 3 interleaved rounds) failed under parallel agent load (1.854 vs 1.545 ms at the P6.0au merge; 1.075 vs 0.975 ms at the P6.0av merge; twice in implementer runs at load average 11–27) and passed alone each time. A failure there also aborted `lib/PottsModels/test/runtests.jl`'s bare `include` chain, so every later frozen file went unrun.
- **Rule.** The cost testset (both algorithms) checks the cost structurally, on the problem `init` runs: the phase types and refreshed integral columns of `prob.f.phases` (before_mcs, after_mcs, end_mcs, at_init) with the 8 observed-only integrals equal those without them, and after_mcs refreshes exactly one column; the `integral_*` cell columns of `prob.u0` are equal, and there is one. Timing stays as a backstop: 15 paired rounds (both models timed back to back, order alternating; 20 warm MCS, best of 3), minimum ratio ≤ 1.5 (the waste is ≈ 3.6×). Only that testset and header item 3 change in the frozen file (sha256 updated, decision D-131); D-120's other checks, fixtures and pins are unchanged. Timing-ratio defect checks in frozen files should be structural where the defect is structural, with any wall-clock bound loose enough to hold under parallel load.
- **Frozen acceptance** re-freeze 4aec8a82 (+ header item 3, coordinator). On d23c9202 (P6.0t's parent) 9 of 12 fail on each algorithm (after-block refreshes 9 columns instead of 1; 9 columns instead of 1; timing minimum ratio 1.99–2.90 under load); on c0f80561 12/12 pass on each algorithm at load averages 12–60 (paired ratios 0.99–1.04).
- **Suite.** PottsModels' test files and acceptance files now run as one testset per file inside an outer testset with Aqua (80ecf09e, not frozen): a failing or load-erroring file is recorded, later files still run, and the run still exits 1. The first `@testset "PottsModels"` block stays top-level.
- **Review (P6.0ay, approved, round 1).** Reproduced 9 of 12 failing on d23c9202; the structural checks run on what `step!` executes (`integ.f.phases`) and fail loudly, not silently, under a harmless rename (anchoring length checks); per-file testsets keep top-level definitions global, count `@test_broken`, and exit 1 on a failure. Nits for a future re-freeze: the structural checks repeat per algorithm; a lifecycle-equality guard would close the one path only the timing backstop sees.

## D-132 P6.0ax: inline gathers outside the copy step are numbered (2026-10-04, P6.0ax; coordinator, from the P6.0at review; amends D-107, after D-124)

- **Gap.** Inline gather relations are named `gather1`, `gather2`, … (D-107) by scanning `all_exprs` in `mtkcompile`, which covers only the copy step and the boundary updates, ODEs, fields, ticks and temperature. Six sites lower gathers but were not scanned, so their spec had no name. Measured on fe057508: `KeyError: key <spec> not found` at build for a division `when`, a division state rule, a `@link`/`@unlink` `when` and an `edges(rel)` energy, and at the first `observe` for an `@observed` quantity. The named fold of the same spec worked at every site; a spec shared with a scanned site already worked (one relation). No site silently read another's relation.
- **Rule.** Every inline gather the compiler lowers is numbered. The scan covers `all_exprs`, then division `when`s, non-`Split` division rules, link rule `when`s, edge energies, `@on_copy` update indices, and observed quantities last. Earlier numbers are unchanged, so every model that built before keeps its fingerprint. An inline gather behaves exactly like the named fold of the same spec. Gathers at the new generated-code sites are fingerprinted under D-124. A gather read only by `@observed` is not fingerprinted, and adding an `@observed` quantity never renumbers the gathers of the generated code. (It can still change the fingerprint, and the trajectory under a fixed seed, when written before other statements: gather bound-variable names, population variables and `rand()` addresses share one build counter, `_next_number!`; pre-existing, folded into P6.0z per D-134. The frozen file's header states the stronger claim; its tests place observed quantities last.) `along` with a non-constant expression stays unsupported, named or inline (not a gather question).
- **Frozen acceptance** `p6_0ax_gather_scan.jl` (freeze 4c11770a): hand-checked values at each site on static fixtures (division MCS, rule values, link and unlink times, edge and observed values), with negative controls; inline equals named under a fixed seed (Sequential and Checkerboard); distinct relations when several sites read different specs; D-124 distinctness at the new sites (Float64 and Float32), alike-resolving specs alike, observed-only gathers not fingerprinted; checkpoints refused across them; 21 unchanged pins. On fe057508, 61 of 140 error (all KeyError at the gap); a prototype passes 242/242.
- **Follow-up.** CheckerboardCPM's preflight refuses a relation that reaches beyond the footprint even when only an MCS-boundary rule reads it (e.g. a named `Ball(2.0)` in a division `when`; pre-existing, named and inline alike): P6.0ba.
- **Review (P6.0ax).** Round 1 changes requested: an inline gather in an `@on_copy` update index was not numbered (`KeyError` at build) and its read reach was missing from the footprint; this decision overstated `@observed` fingerprint stability (the shared build counter, folded into P6.0z). Fixed in dfbbbcb0 (one `scanned` list drives tracker flags and numbering; footprint scans on-copy indices). Round 2 approved: no model that built before changes fingerprint or trajectory; the only behaviour change is a corrected (larger) footprint read reach for a named relation read in an on-copy index.

## D-133 P6.0u: remaining `@components` gaps and review nits (2026-10-04, P6.0u; coordinator, from the P6.0k2, P6.0e2, P6.0d and P6.0m3 reviews; amends D-084, D-088, D-081, D-080)

- **Gap.** Measured on fe057508: MTK `tstops` and `assertions` on a component System (also in a subsystem) were accepted and ignored. Component bindings Potts cannot evaluate failed without naming the component (`y(t) = 2k`, `y(t) = 2z` → "cell/model variable `comp7₊y` has no initial value"; `initial_conditions = [y => 2k]` → "`2k` does not reduce to a number …"; `k2 = 2k` → "unknown symbol `k2` in …"; discrete `X(t) = !Y` → "`net7₊X` has no initial value"). An `x′` `UndefVarError` raised inside a hand-written (non-`@potts_model`) `@extend` base was relabelled with the outer model's (or another base's) description of `x`. `init` warned about `frozen_varies` even when a system defined `frozen_varies(sys) = false` on purpose. The temperature's `integral(Pre(x))` error had no location.
- **Rule.** (1) At `mtkcompile`, a component whose System (including subsystems) carries non-empty `tstops` or `assertions` is an `ArgumentError` naming the component and the field, like the F7 fields; an empty list is accepted. (2) Every rejected component binding (an MTK binding of a variable or parameter, or an `initial_conditions` value that is an expression), cell or model scope, continuous or discrete, is an `ArgumentError` naming the component ("component `c`" or the location "@components cells|model c") and the bound name, at build or at `PottsProblem`. Plain values and `guesses` are unchanged; missing values of the model's own quantities never mention a component. (3) An error raised inside an `@extend` base's constructor propagates as the base raised it: the extension's prime translation applies only to its own section code (a `@potts_model` base translates with its own description; a hand-written base's `UndefVarError` stays one); the extension's own primes and primes of names bound from a base are still translated. (4) `init` warns only when `remake_frozen` is overridden and `frozen_varies` is CorePotts' default method; a `frozen_varies` method defined outside CorePotts (also on a supertype, also `false`) silences it. (5) The temperature's `integral(Pre(x))` error ends with the location "in @sweep" (Metropolis and Barker). Generated code and fingerprints are unchanged.
- **Frozen acceptance** `p6_0u_components_gaps.jl` (freeze 272a6c73): 72 tests — targets per gap (8, 5 per scope, 3, 3, 2), negative and unchanged-message controls (a `@potts_model` base's own description, the extension's own and inherited primes, the default-`frozen_varies` warning, `integral(w)`, the `@equations` location, a Potts parameter without a default, F7 `continuous_events`), 7 fixture fingerprints pinned. On fe057508, 26 of 72 fail (all targets); a prototype (+28/−4) passes 72/72, and p6_0k, k2, e2, m3, am and d pass on it.
- **Known limitations (P6.0u review; not filed, D-134).** A discrete component with a lag of a lag (`C4(k) ~ C4(k-1) + C4(k-2)`) fails with "cell variable `comp₊C4ₜ₋₁` has no initial value"; numeric array parameters in a component (`@parameters pa[1:2] = [0.1, 0.2]`) fail early with `MethodError: Float64(::Vector{Float64})`. Both look pre-existing; a reproduction that needs either reopens it.
- **Review (P6.0u, approved, round 2).** The implementer narrowed the prototype's blanket binding rejection, which would have refused three things that work today (an unused bound parameter, a bound observed variable, an expression initial condition on an observed variable): only bindings of quantities Potts reads are rejected. Round 1 found that a bound parameter no component equation reads but the model reads as `comp.k2` still gave "unknown symbol … declare it"; let-through bindings are now recorded and any model read of one (energy, coupling, observed, constraint, drive, fold, update, temperature) is the binding error naming the component. `@extend` base errors use a per-call `Ref` and a `_BaseCall` wrapper (no global; base arguments evaluated outside it, so the extension's own primes in them stay translated); a prime error inside a closure the extension passes to a hand-written base is reported as the base's (accepted). `tstops` via public `get_tstops`/`get_systems`.

## D-134 Step 0 is frozen; reproductions start after P6.0g and P6.0o (2026-10-04, maintainer)

- **Decision (maintainer, verbatim intent):** "freeze P6.0; fingerprint corner cases go to P6.0z or are dropped as best-effort; after P6.0g and P6.0o, start the paper reproductions".
- **Applied (coordinator).** No new P6.0 rows; review findings outside an item's scope are noted in the item's decision or folded into P6.0z instead of filed. Items already in flight finish: P6.0c2, P6.0u, P6.0ax (a build failure, not a fingerprint case). Fingerprint corner cases (P6.0az, and any later ones) go to P6.0z: fixed there if cheap, else documented as best-effort; the fingerprint stays a best-effort guard against loading a checkpoint into a different model, not a proof. Deferred and not blocking Step 1: P6.0ac, P6.0ba, P6.0v4, P6.0v5; P6.0ae is settled within the Merks reproduction (Step 3). Order: P6.0g, then P6.0o (a large refactor; the earlier rows touch its files less once merged), then Step 1 onward. P6.0z runs after P6.0o and does not block the reproductions.

## D-135 P6.0g: kind classes (2026-10-04, P6.0g; coordinator, from the P6.0g test author; implements api-synthesis §2.2)

- **Gap.** `@kinds` takes only kind names (`name`, `name[frozen]`), and `cells`/`clusters`/`connectivity`/`Volume`/`Surface` take only integers, so a gate over several kinds is spelled `kind[x] == tip || kind[x] == stalk` at every site. Bauer 2009 (spec 05, friction 1) needs classes: the stroma is two collective cells (fluid, matrix), the medium owns no site, and every `old == 0` / `new != 0` gate is wrong there.
- **Rule.** `@kinds` accepts `name = (member, …)` lines (block or one-line form, anywhere among the kinds; they never shift kind numbers). Members are declared kinds or earlier classes, flattened in order. A class is usable wherever a kind list is: `cells(g)` (energy domain, `@divide`, `@components`, population folds), `clusters(g)`, `connectivity(g)`, `Volume`/`Surface(g; …)`, `Chemotaxis(…; kinds = g)`, mixed with kinds. `x ∈ g` / `x ∉ g` on a symbolic kind (`kind`, `kind′`, `kind[new]`, `kind[c]`, `kind[n]`) lowers at build to `(x == k₁) | … | (x == kₙ)` in member order (`!(…)` for `∉`): constant kind numbers, nothing allocated, so it runs on every backend, and a model with classes has the same generated code and fingerprint as the same model with explicit `||` chains. Declaring a class that no statement reads changes nothing. Classes are stored on the `PottsSystem` (not hashed; their effect is in the code) so `@extend` can bind them (`@extend endothelial = base = Base()`); an extension may restate a base class with the same members and add new ones; restating it with other members is an `ArgumentError` naming it. A class is not an index (`J[g, kind′]`, `γ[g]`: `ArgumentError` naming the class). `ArgumentError` at build: an empty class, a duplicate member (also after flattening), the medium as a member (write `kind[x] == medium || kind[x] ∈ g`), a member that is neither a kind nor an earlier class, a name clash (D-113 gains the category "kind class") or a reserved name. Operating points, layouts and `Wall` take kinds, not classes (a class there is an `ArgumentError` naming it). Future kind-list sites (`@transition`, `@create`, `no_extinction(kinds…)`) accept classes when they land. No DSL name or keyword is added: classes are declarations inside `@kinds`, and `∈`/`∉` are Base methods on a Potts-owned type (no piracy), so the DSL snapshot and the denylist are unchanged. `KindClass` is public, not exported (programmatic `PottsSystem(; kind_classes)`). Published fingerprints are unchanged. Coordinator: surface accepted as proposed (tuple syntax per api-synthesis §2.2, not the sketches' `[…]`/`@kind_classes`).
- **Frozen acceptance** `p6_0g_kind_classes.jl` (freeze 7ea25a46): a Bauer-style model (fluid and matrix as cell kinds, `ecm = (fluid, matrix)`, `endothelial = (tip, stalk)`, nested `mix = (ecm, tip)`) plus lifecycle, clusters and two `@extend` fixtures, each with the same generated code (Float64/Float32), fingerprint and trajectories (Sequential/Checkerboard, Float64/Float32) as its explicit twin; every gate site against a hand value or a plain-Julia oracle; ΔH self-check; negative controls (a class without stalk, misspellings, the medium, empty, duplicate and non-kind members, name clashes, class as a table index, class as an operating-point kind, conflicting `@extend`); P60gX and 7 published pins; Metal CPU = device (Float32). On 462b012a, 32 fail and 36 error of 92 (all on the gap); a prototype passes 336/336 (+1 Metal skip), and 340/340 with POTTS_GPU=metal.
- **Applied (coordinator, from the implementer and review).** A programmatic `PottsSystem(; kind_classes)` is validated at construction (kinds in `1:ncell`, no duplicate names or kinds, not empty, not a reserved or built-in name). `Chemotaxis(kinds = …)` takes a tuple mixing kinds and classes. `kind == g` and `kind != g` (either order) are `ArgumentError`s pointing to `∈`. Members are resolved when the macro expands, against this `@kinds`, earlier classes and names bound by an `@extend` written before `@kinds`. A restated base class must list the same members in the same order (the order is in the generated code). Layouts reject class names (Tiling, Scattered, Frame, InsertUntil `kind` and `into`, overlays, custom layers); an unknown non-class kind name is still accepted by `layout` (a model may be used only as a lattice) and rejected by `PottsProblem`. Classes are not hashed separately; their effect is in the generated code, so an unused class leaves the fingerprint unchanged and membership or member order changes it.
- **Review (P6.0g).** Two rounds (round 1: `kind == g` silently constant; members not checked at expansion, so a global integer could become a kind; layouts partly ignored class names).


## D-136 P6.0z scope: one frozen fingerprint suite (2026-10-04, maintainer; amends D-134)

- **Decision (maintainer).** Consolidate the fingerprint tests into one frozen suite, `lib/PottsModels/test/acceptance/fingerprint.jl`, as part of P6.0z. Move the fingerprint testsets out of p6_0p, p6_0aq, p6_0ar, p6_0as, p6_0at, p6_0ah, p6_0c2 (and the pin blocks in p6_0t, p6_0x, p6_0au, p6_0aw, p6_0av, p6_0u) into it, keeping every distinctness, checkpoint-refusal and cross-session check. Pin each published model's and fixture's fingerprint exactly once there; other frozen files drop their pin blocks. Re-freeze the touched files under this decision.
- **Applied (coordinator).** Also in scope: the pin blocks of p6_0ag, p6_0ax and p6_0g (merged or merging meanwhile), and any later frozen file that pins a fingerprint. "Pinned once" means one table of (system or fixture → value) in the suite; a file that needs a fixture's fingerprint for its own logic (e.g. "differs from the old pin", D-124) reads it from the suite's table or compares two builds, never a literal. Re-pins under future decisions then touch only the suite. The consolidation must change no fingerprint value: the suite's table equals the union of today's pins, and the run on the consolidating commit shows every moved check still fails on the commit before the fix it guards (spot-check one per decision via the decision's recorded base commit).

## D-137 P6.0o: `PottsSystem <: AbstractSystem`, its accessor contract and the property-read rule (2026-10-04, P6.0o; coordinator, from the MTK-native review; implements D-075 §0.1)

- **Gap.** Measured on 33f681df: `PottsSystem` is a plain struct. MTK's `equations`, `unknowns`, `observed`, `complete`, `getmetadata`, `setmetadata` and `toggle_namespacing` are MethodErrors on it, and `ModelingToolkitBase.parameters` silently returns an empty list. `sys.λ` is a FieldError. `compose(sys, [x])` falls into MTK's varargs `compose` and recurses without end. `ODEProblem`, `JumpProblem` and `extend(sys, ::System)` are MethodErrors. Aqua finds one ambiguity (`_pre`, src/vocabulary.jl). Potts reads PottsSystem fields by property 357 times in src/ and ext/. Six frozen files (p6_0av, merks_2006_defaults, p6_0al, p6_0e2, p6_0am, p6_0t) read them in test code.
- **Rule.**
  1. `PottsSystem <: ModelingToolkitBase.AbstractSystem`, with the `System` field names MTK's supported accessors read (`eqs`, `unknowns`, `ps`, `observed`, `name`, `systems`, `metadata`, `namespacing`, `complete`) beside the Potts-owned fields. The field named `observed` keeps the Potts `ObservedEq` vector (a frozen test reads `getfield(m, :observed)[i].var`); the `observed` accessor and MTK's `getvar` are overridden to give `name ~ expr` equations. An all-fields positional constructor takes `checks` (default true; `false` skips the construction checks). The keyword constructor keeps its names.
  2. Accessors, documented in the `PottsSystem` docstring: `equations` is the `@equations` as written plus each component's equations namespaced `comp₊x` (Hamiltonian terms, drives, updates, rules and observed are not equations). `unknowns` is the declared state variables of every scope plus component unknowns namespaced, never ownership, kinds or built-ins, each name once (also on `mtkcompile(sys).sys`). `parameters` is the declared parameters plus component parameters namespaced. `observed` is `name ~ expr` per `@observed`. `nameof` is the model name. `getmetadata`/`setmetadata`/`hasmetadata` are MTK typed metadata; they survive `complete`, `mtkcompile` and `extend` and never enter code or the fingerprint. `Potts.parameters` and `Potts.variables` still return the model's own declarations.
  3. `sys.x` is the namespaced symbolic as in MTK (`sys.dc.y` → `pr₊dc₊y`). A completed or non-namespacing system returns the declared symbol, which keys the operating point. An undeclared name is an `ArgumentError`.
  4. Potts owns `complete` (same code and fingerprint, idempotent), `extend(::PottsSystem, ::PottsSystem)` and `show`.
  5. `compose` with a PottsSystem on either side (D-039), `ODEProblem`/`JumpProblem` on a PottsSystem or `CompiledPottsSystem`, and `extend` between a PottsSystem and a `System` either way are `ArgumentError`s naming the operation and the Potts route (`@components`, `extend`, `PottsProblem`).
  6. **Strict property reads (coordinator choice, option B of the test author's report).** Every internal read uses `getfield` or an accessor. A property name that is not a declared symbol or component behaves as in MTK (an `ArgumentError`), so a missed internal read fails loudly. User-facing reads get a public (not exported) accessor where the manual needs one: `Potts.lattice(sys)` (manual models.md). The six frozen files, and later `p6_0g_kind_classes.jl` (frozen after them; one `sys.kinds` read, coordinator), are re-frozen under this decision, with property reads replaced by `getfield` or `Potts.parameters`/`Potts.variables` and nothing else. Rejected: option A (`getproperty` falls back to the Potts field) — it deviates from MTK and hides missed reads.
  7. Generated code (raw text) and fingerprints are unchanged.
  8. Latency: `benchmark/p6_0o_latency.jl` in paired mode against a 33f681df checkout decides acceptance — cold and warm construction, `mtkcompile`, `PottsProblem`, and time to first MCS, each within +5 %. The absolute D-047 figure is reported, not gated (maintainer, 2026-10-04). The warm-MCS gate is unchanged.
- **Frozen acceptance** `p6_0o_abstract_system.jl` (freeze 9093098e): subtype and fields, accessors, namespacing, complete/extend/show, clear errors, Aqua, a source scan, and 25 code and fingerprint pins (published models in Float64 and Float32, nine fixtures). On 33f681df 38 fail and 46 error of 193 (every target); a stub passes 261/261 with identical pins.
- **Baseline** (33f681df, load average 6.5–8.6, medians of 5 fresh processes): time to first MCS GG 9.88 s, Wortel 10.22, Merks 10.40, OpenVT 12.49, Akeeb 13.62, Akeeb Float32 (D-047) 14.69 s — under 2 % margin to 15 s, so a quiet-machine paired run decides.
- **Applied (implementer, coordinator-accepted).** The questions this decision left open, as resolved on feat/p6-0o:
  1. The mirror fields `eqs`, `unknowns`, `ps`, `systems` are derived by the constructor from `equations`, `variables`, `parameters`, `components` (one object for `eqs`/`equations` etc.); values passed to a constructor for them are ignored. Changed by review SF3: `@set sys.eqs`/`sys.unknowns`/`sys.ps = …` (`ConstructionBase.setproperties`) sets the Potts field they mirror; setting `systems`, or `observed` to MTK equations, is an `ArgumentError`.
  2. `systems` holds only the `@components` systems, under their component names; on `mtkcompile(sys).sys` the components are bound into variables, so it is empty there and `unknowns` lists nothing twice.
  3. `observed(sys)` is the `@observed` quantities only (not the component systems' own observed equations).
  4. `extend` merges metadata as MTK does (the newest value of a key wins, the extension's over the base's; MTK's mutable cache entry dropped) and resets `complete`/`namespacing` to their defaults.
  5. Changed by review SF1: a key namespaced by the model's own name (`sys.x` of an uncompleted `sys`, `pr₊x`, also `Symbol("pr₊x")`, inside expressions, and `sys.dc`/`sys.dc.y` of components) means the declared quantity at every key site (operating point, `remake` `p`/`u0`, `getu`/`setu`/`getp`, `observe`, `prob[…]`/`sol[…]`, `solvers`), through one helper (`_localize`); a key namespaced by another name is an `ArgumentError` naming `complete(sys).x`. `sys.<name>` of a kind, kind class, vector quantity, relation, relationship or field is an `ArgumentError` naming that category. Vector quantities are reached through their components (`sys.w_1`).
  6. Two-argument `show` prints `PottsSystem <name>`.
  7. `compose(mtk, [mtk2, potts])` (a mixed vector) still reaches MTK's generic `compose` (a `convert` MethodError); catching it would need MTK's internal `collect_scoped_vars!`.
  8. The keyword constructor takes no `checks`; the positional one does. `PottsSystem` keeps `Base.@kwdef` (an explicit 29-argument constructor made the first `PottsProblem` of a session about 60 % slower to infer).
  9. JumpProcesses (owner of `JumpProblem`) and ConstructionBase (owner of `setproperties`) are direct dependencies, both already loaded by ModelingToolkitBase. `complete` is exported (MTK's function); `independent_variables(sys)` is `[t]`.
- **Follow-ups (P6.0z, D-134).** `Potts.parameters` vs `ModelingToolkitBase.parameters` share a name and differ for component models; duplicate Float64 pins here are merged into the D-136 suite.
- **Review (P6.0o).** Three rounds (round 1: namespaced `sys.x` keys behaved differently per site and crashed on observed quantities; `complete` not exported; `@set` on a mirror field a silent no-op; `extend` kept a stale metadata value. Round 2: keys namespaced by another model leaked through `getp`, `prob.ps`, `solvers` and expressions). Approved in round 3. Follow-up to P6.0z: a component's algebraic observed (`dc₊z`) gets the "namespaced by another system" error; it should say the quantity is substituted and suggest `@observed`. `@mtkcompile s; s.λ` on a `CompiledPottsSystem` is a FieldError (pre-existing).

## D-138 P6.1a5: core `Voronoi` replaces `VoronoiBall`; shapes, `RandomPoints`, `Center()`; shape clipping; StableRNGs leaves PottsModels (2026-10-05, P6.1a5; coordinator, from the P6.1a5 test author; amends D-057, D-091; implements initial-state-review §2 S2 and Q1/Q3/Q5, D-093's `layer_rng`)

- **Shapes (Q1).** Potts imports from GeometryBasics, explicitly and only, `HyperSphere`, `Circle` (= `HyperSphere{2}`), `Sphere` (= `HyperSphere{3}`) and `Point`, and exports them (coordinator: exported, not public-only — every tutorial loads Makie, which re-exports the same bindings, so `using Potts, CairoMakie` stays unambiguous, D-056). Not imported or exported: `Rect`, `Vec`, `Cylinder` (index boxes stay tuples of unit ranges), and GeometryBasics' `volume`, `area`, `direction`, `origin`, `radius`, `widths`, `centered`. GeometryBasics (compat `0.5`) is a Potts dependency; CorePotts does not depend on it. Shapes are Cartesian: the lattice's `embed` of the index (identity on square, `(q + r/2, r√3/2)` on hex). Membership is closed, with a relative rounding tolerance (amended after the P6.1a5 review: GeometryBasics' own `in` drops boundary sites at exact lattice distances on hex, where `embed` carries √3/2 rounding): site x is in s iff `norm(center − embed(x)) ≤ r·(1 + 1e-12)` for x or one of its periodic images — shapes wrap through periodic edges and clip at closed edges and the domain. Known clash: DomainSets (loaded via ModelingToolkit) exports its own `Sphere` and `Point`; `using Potts, DomainSets` needs qualified names (outside D-056's list; documented in the layouts manual).
- **`Center()`** (exported): the Cartesian lattice centre `embed((size .+ 1) ./ 2)`, as a pattern or inside a vector of points. A shape's own centre stays an explicit `Point` (Q8).
- **`RandomPoints(n; region = whole lattice, seed)`** (exported; region a shape or a tuple of ranges): n distinct in-domain region sites drawn by VoronoiBall's rule (sites in column-major order s₁…sₘ, `rng = layer_rng(seed)`, `i = rand(rng, 1:m)` redrawn while taken), in draw order. `ArgumentError` for n < 0, n > m, or a seed outside `0:typemax(UInt64)`; `remake(p; seed)` works. `replace` stays P6.3c's. `Potts.points(pattern, x) -> Vector{Point{N,Float64}}` is public, not exported.
- **`Voronoi(points; region = whole lattice, lloyd = 0, kinds, splits = :warn)`** (exported): one cell per generator, ids in generator order, `kinds` cycled. Fills medium only — paints the region's in-domain sites still medium, never cuts an earlier layer (Morpheus InitVoronoi); no `into` until P6.3c. Nearest generator, Euclidean in the embedding, minimum image on periodic axes, ties to the lowest generator; `lloyd = k` centroid moves (minimum image), each followed by reassignment; then D-063's one-piece repair under the geometry's nearest steps, wrapping on periodic axes. Report row `type = :Voronoi`, `requested = painted =` generators, `dropped` = generators with no site, `misses = 0`, `counted = painted`, plus `clipped`. `ArgumentError` for `lloyd < 0`, empty `kinds`, no generators, a bad `splits`, or a dimension mismatch. The VoronoiBall pins require VoronoiBall's floating-point procedure (index coordinates, accumulation order, box scan).
- **`VoronoiBall` removed, no alias (Q3, D-028).** `Voronoi(RandomPoints(n; region = ball, seed); region = ball, lloyd = it, kinds)` with `ball = HyperSphere(Point(embed(center)), radius)` reproduces VoronoiBall's σ and kinds at 8eb9d210 on closed lattices and domains, and on periodic lattices where no periodic edge cuts the ball (VoronoiBall clipped where a shape now wraps). `graner_glazier_aggregate` is byte-identical and built on it.
- **`clipped` (Q5; amends D-057, D-091).** U = index points (periodic axes reduced to `1:n`) in the shape; a shape layer's `clipped` = |U| − in-domain lattice sites of U. Sites skipped because an earlier layer owns them are not clipped. Every report row gains `clipped`: 0 for `Tiling`, `Scattered`, `Frame`, `InsertUntil` (Tiling `:clip` boxes not counted in this item, deliberately unfrozen). `record!(op; …, clipped = 0)`. `Tiling` keeps D-057's throw.
- **`Potts.layer_rng(seed[, stream])`** (public, not exported): `StableRNG(UInt64(seed))` or `StableRNG(_substream_seed(seed, stream))`; out-of-range seed → `ArgumentError` (D-093's planned wrapper). `akeeb_state` draws its clocks from `Potts.layer_rng(seed, :clock)`, byte-identical. StableRNGs leaves PottsModels' `[deps]`/`[compat]` and stays a Potts dependency; no PottsModels source names `StableRNG`; the guardrail's `_substream_seed` exception is removed.
- **Re-freeze (D-060 style; API and names only).** `p6_0w_substream_seeds.jl`, `p6_1a6_layout_protocol.jl` and `p6_2a2_akeeb_inventory.jl` import `StableRNG` from StableRNGs in the PottsModels test env (which gains the dependency); p6_0w's akeeb_state check also accepts a two-argument `layer_rng`; p6_1a6's VoronoiBall check names `Voronoi`.
- **Load order (P6.1a5 review).** GeometryBasics' `OffsetInteger` `convert` methods invalidate the symbolic stack when loaded before it (`using Potts` 4.8 → 6.2 s); Potts imports GeometryBasics after its other dependencies (4.9 s). Later dependencies go above that import. Upstream (GeometryBasics ≤ 0.5.13) still has the methods.
- **Ties.** Generator ties are broken in floating point toward the lower generator; on hex, rounding can break exact geometric ties (VoronoiBall's procedure, kept for the pins).
- **Follow-up.** `Scattered` and `InsertUntil` keep a direct `StableRNG(l.seed)` because p6_0w's frozen non-vacuity check counts ≥ 5 raw constructor sites; its next re-freeze should count `layer_rng` calls too, after which they switch.
- **No DSL change** (layouts are problem data, D-057). Spec sketch 11 still names VoronoiBall; the coordinator updates it at merge.
- **Frozen acceptance** `p6_1a5_voronoi_shapes.jl` (freeze 4546c611): exports/bindings with a clash control; dependency moves and a source scan; `layer_rng` and Akeeb clock pins; closed-membership hand counts (square, 3D, hex, corner, periodic, domain); clip and wrap; `RandomPoints` against an independent StableRNG oracle; `Voronoi` = VoronoiBall σ and kinds for 11 cases × 4 seeds and `graner_glazier_aggregate` unchanged for 8; a brute-force nearest-generator oracle with minimum image (negative control without the wrap); one-piece repair actually exercised; Lloyd (centroid share > 0.99 vs ≈ 0.84 without, a non-wrapping Lloyd fails); medium-only fill; `clipped` hand values. On 8eb9d210: 27 pass (regression guards), 15 fail, 38 error of 80, all on the gap; a stub passes 611/611 and the three re-frozen files pass on it.
- **Applied (implementer, coordinator-accepted).** A single `Point` is accepted as a pattern; `Potts.points(vector, x)` returns the given Points unchanged and `Voronoi` converts them through the inverse embedding; `clipped` for a tuple-of-ranges region counts the box's out-of-domain sites (no region → 0); Lloyd on periodic axes uses each site's nearest image and wraps a moved generator into [½, n + ½); non-finite or negative shape parameters and non-finite generator coordinates or any of magnitude ≥ 1e15 are `ArgumentError`s; the first search radius is `2(m/n)^(1/N)` (exact for any radius).
- **Review (P6.1a5).** Two rounds (round 1: hex discs lopsided at exact lattice distances; `using Potts` +29 % from GeometryBasics' load-order invalidations, failing P6.0o's +5 % time-to-first-MCS bound; hex tie wording). After the fixes: `using Potts` ×1.04, time to first MCS ×1.013–1.034 against 8eb9d210. Known limit: the membership tolerance is relative to r, so on hex lattices of order 40 000² small discs far from the origin can lose boundary sites again (unrealistic sizes; fix by scaling with the centre's magnitude if ever needed).


## D-139 P6.1b: boundary lengths by kind pair and the annealed copy are public Potts functions (2026-10-04, P6.1b; coordinator, from the P6.1b test author; implements R16's first slice under D-051 item 6)

- **Why a library function.** R16's sorting analysis (spec 09 §9.0, PRE §II D1) needs the boundary length of a state split by kind pair, and the same measurement on a copy annealed at T = 0 with the run's own energies (PRE p. 2134). Neither depends on a model. Under D-051 item 6 analysis lives in the docs unless it has library merit; these two do: a generic annealer must override the copy temperature whatever the temperature expression is (`remake(p = [:T => 0])` works only for a bare parameter `T`), and the boundary split is the exact decomposition of the contact term of `total_energy`, reading the compiled kind names and the contact relation. Both go next to `total_energy` in Potts, public, not exported (coordinator, Q1). Neither names a model.
- **Rule.**
  1. `Potts.boundary_lengths(prob, u = prob.u0; relation = nothing) -> Dict{Tuple{Symbol,Symbol},<:Real}`. A bond is an unordered site pair {i, i+o}, o an offset of `relation` (a RelationSpec resolved on the problem's lattice; `nothing` = the problem's contact relation); the neighbour lies inside the lattice and its domain (periodic axes wrap; closed axes and the domain edge do not); the two owners differ. Each bond counts once, with the relation's weight. It is credited to the kinds of its owners (medium = the first `@kinds` name); keys `(a, b)` with `a` declared no later than `b`; every pair is a key, zeros included; `(medium, medium)` is 0; two cells of one kind count under `(k, k)`; kind classes are not keys. For a model whose only energy is `contacts => J[kind, kind′]`, Σ J·L == `total_energy`. Square, hex and 3D; host only.
  2. `Potts.anneal(prob, u = prob.u0; mcs, seed = 0, alg = SequentialCPM()) -> state`: a new state, `u` after `mcs` MCS of `prob`'s copy dynamics with copy temperature 0 for every proposal whatever the temperature expression; everything else is the run's own (parameters, lattice, relations, proposal, acceptance law with its T ≤ 0 tie convention, full ΔH including drives — coordinator, Q3). Only copy attempts run, preceded each MCS by the derived refreshes the energies read (integrals and population-fold energy snapshots, i.e. the at-init phase; amended after the P6.1b review): no other MCS phases, rules, updates, lifecycle, ODE or field steps; an energy reading a cell variable maintained by an update block sees it frozen at `u`'s value (it relaxes the displayed data only — coordinator, Q2; fixed by this entry, not by a test). `u` and `prob` unchanged; deterministic in (prob, u, mcs, seed, alg); `mcs = 0` returns an equal copy; `mcs < 0` is an `ArgumentError`. Statistical, not bitwise, agreement with 09's recipe.
  3. Docs: new manual page `docs/src/manual/analysis.md` (boundary lengths and fractions L/ΣL as in PRE; the annealed-copy protocol; the energy identity as a worked check), in `docs/make.jl` and the API page. Fits, graph analysis, T1 counts and MSD stay in docs Julia or `PottsModels.Analysis` (api-synthesis §2.14).
  4. **Not in this item (coordinator):** the frozen 09 tutorial (D-072) keeps its own `bond_counts`/`annealed` helpers. It is pre-registered and its FULL run (P6.1d) is in progress on the current code; switching it to these functions is a later change under its own DECISIONS entry, after P6.1d's verdict is recorded.
- **Frozen acceptance** `acceptance/p6_1b_boundary_anneal.jl` (freeze d54c2ab1): hand-counted fixtures (square, weighted, hex, 3D; periodic vs closed), the energy oracle with J = 10^{0,3,6,9,12} so Σ J·L spells each count, agreement with 09's `bond_counts` and (8 seeds, 5 SE) its annealed measurement, a hole fixture filled at T = 0 under Sequential, Checkerboard and a `3θ` temperature, negative controls. Current tree: 1 pass, 2 fail, 24 error (all `UndefVarError`/`ispublic`); stub: 77/77.
- **Applied (implementer, coordinator-accepted).** `anneal` replaces `prob.seed` with its own `seed` (copies addressed from MCS 0; replica and repeat kept); a model bias term drops out at T = 0; `boundary_lengths` returns `Int` for unweighted and `Float64` for weighted relations, and an asymmetric relation is an `ArgumentError`; `anneal` works on any `CorePotts.PottsProblem` and takes no `backend`; a failed copy dynamics (non-finite ΔH) is an error, not a partial state. The implementation swaps the temperature and phases on a remade problem; no CorePotts or kernel change.
- **Review (P6.1b).** Two rounds (round 1: frozen population-fold snapshots and integrals, so ΔH was not the run's own; a failed run returned silently; the docs overclaimed a lower energy). Notes: stored integrals in the returned state reflect σ before the final sweep (only updates, ODEs and lifecycle read them, none of which run); the annealed copy's clock runs 0…mcs, not `u`'s time.

## D-140 P6.3a: shell topology values on every geometry, the soft E₀ drive, the `Global()` placeholder, `track = (:ΔH,)` (2026-10-05, P6.3a; coordinator, from the P6.3a test author; implements R4's local half and D-075's `track`; amends D-016 as D-075 states)

- **Shell values.** `ring_arcs`, `ring_cells` and `ring_medium` are defined on every geometry and read the target's neighbour shell: the 8 Moore sites (square 2D), the 6 hex neighbours (hex), the 26 Moore sites (cubic 3D). `ring_arcs` counts the pieces of `old`'s shell sites under lattice face adjacency (the arcs on a 2D ring); it equals `local_components` on every geometry and is 0 for the medium. Out-of-domain sites are neither medium nor a cell (as in P6.0aa); periodic axes wrap. The shell is fixed whatever the `neighborhood` (as TST's 8-ring). `connectivity(k; rule = :arc_or_pair)` and `connectivity(k)` therefore work in 3D. No new DSL name; the values are leaf primitives inside the read-1 footprint, so the checkerboard stride is unchanged. (No tool defines a 3D ring rule — CC3D's Connectivity is 2D-only — so the 3D shell is this project's definition.)
- **Soft E₀ drive.** An expression, not a new name: `@drive copy => E₀ * ((kind[old] == k) & !((ring_arcs <= 1) | ((ring_cells == 2) & (ring_medium == 0))))`, exactly TST's threshold shift under Metropolis (model-spec 01 §7.3); the `connectivity` docstring gives this form. Merks 2006 adopts it in P6.3d (D-050 M3).
- **`Global(; window = nothing)`.** A reserved DSL name, placeholder until P6.9: `window` is `nothing` or a positive `Int` (else `ArgumentError`). `components(x; scope = Global())` is a DSL name too; using it raises an `ArgumentError` at build ("global connectivity (`Global()`) is not available yet (P6.9)") on every algorithm. P6.9 replaces the error with the exact sequential BFS and the device design of api-synthesis §8.1 Q6; `window` stays on `Global`/`components`, never on `connectivity`. DSL snapshot gains `:Global`, `:components`, keyword `:components => [:scope]`.
- **`track`.** A keyword of `PottsProblem(sys, op, tspan; track = ())` and `remake(prob; track)`, resolved in Potts (D-046). Only `:ΔH` for now; any other name or a duplicate is an `ArgumentError` (per-term names wait for R18). It compiles into a new last field of `CPMFunction`, `track::TK` (`nothing` off, a generated callable on); the CPMFunction keyword constructor gains `track = nothing`; `DeviceFunctions` carries it. The accumulated quantity is each committed copy's `delta_H` (energy plus every drive), excluding the `bias` term and the acceptance law's offset. This differs from TST's SumDH, which excludes `conn_diss`; irrelevant for 01 F9 / V-C11 (the 2008 set has `conn_diss = 0`); under R18 a per-term track can exclude the E₀ term.
  - Sequential: `sequential_mcs!` adds `dH` (before `_effective_dH`) into a local `Float64` on accept and returns it beside `accepted`; `step!` adds it to `stats.accepted_ΔH`; exact after every step.
  - Checkerboard: two cache buffers (`nothing` when off): a per-colour scratch `dH::Vector{T}` (`maxsites`) and a lattice-indexed accumulator `acc::Vector{T}` (N), T the model scalar (Float32 on Metal). `propose_body!` writes `dH[j]` for an accepted proposal; `commit_body!` adds `dH[j]` into `acc[t]` only when the copy commits; no sub-cycle is zeroed, no atomics (one target per site per colour).
  - Reduction only at read points (a save, `integ.u`/`current_state`, `checkpoint`, end of `solve!`; the D-089 pattern): one reduction of `acc` into the host `Float64`, then `acc` is zeroed. No per-MCS sync; on the checkerboard `integ.stats.accepted_ΔH` may lag between read points. Float32 per-site sums span one save interval. Relaxed order (D-029).
- **Stats.** `PottsStats.accepted_ΔH::Union{Nothing, Float64}`: `nothing` off, `0.0` at `init` on; `merge` adds (`nothing` if either side is); checkpoints carry it; `reinit!` resets it to 0.0. Other `PottsStats` names unchanged (D-031 F-13).
- **Fingerprint (D-075's D-016 amendment).** Off adds nothing (every existing fingerprint and pin unchanged); on hashes `"track=(:ΔH,)"`, so a checkpoint loads only into an equally tracked problem.
- **`count`** (`CheckerboardCPM(; count = true)`) stays in P6.7; it will reuse the same scratch, commit-add and read-point reduction.
- **Performance.** Off: gate unchanged (≤ 5 %), zero allocations; `track`, `dH`, `acc` are `nothing` and the branches are type-level. On: the implementer measures it on `merks_100`/GG by A/B (expected < 1 % Sequential; about 1–3 % Checkerboard on CPU and Metal). Metal quiet MCS: 0 syncs and 0 transfers on or off (pinned).
- **Frozen acceptance** `p6_3a_topology_track.jl` (freeze 61369813): shell values against an independent BFS oracle on square, hex, 3D (Periodic, Closed) plus 3D hand fixtures; both connectivity rules on hex and 3D; the soft E₀ drive against brute force plus E₀ × an independent break indicator; the 3D soft-connectivity sibling (0 vs 70 split snapshots at E₀ = 1e4 vs 0); `Global` placeholder and its error; `track` against the oracle Σ accepted ΔH = Φ(end) − Φ(start) on Sequential and Checkerboard (offset 3 not accumulated), no other effect, fingerprints, errors, checkpoint continuation, `reinit!`, `merge`; Metal Float32 within 0.5 and 0 syncs per quiet MCS. On 6abfd43c: 372 pass / 2 fail / 35 error (all on the gap); stub 650 pass.

## D-141 P6.3c: `Eden`, a host-routine `Splits`, `RandomPoints(replace = true)`, `shortfall` (2026-10-05, P6.3c; coordinator, from the P6.3c test author; amends D-138; implements initial-state-review §2 (§5.8a TST seeding) and §4)

- **`RandomPoints(n; region, replace = false, seed)`** (amends D-138). Under `replace = true`, point k is `s[rand(rng, 1:m)]` (`rng = Potts.layer_rng(seed)`, `s₁…sₘ` the region's in-domain sites in column-major order): one draw per point, no redraw, so duplicates and `n > m` are allowed; `n > 0` with `m = 0` is an `ArgumentError`. `replace = false` is unchanged (the two rules agree up to the first repeated draw). `remake(p; replace)` works.
- **`Eden(points; rounds, region = whole lattice, kinds, seed, neighborhood = nothing, shortfall = :error, splits = :warn)`** (exported): TST `GrowInCells` (ca.cpp:1071-1163).
  - Seeding: any point pattern (as `Voronoi`); each point maps to index coordinates rounded half up, `floor(x + 1/2)` (`Center()` on 200² is (101, 101), TST's `sizex/2`), wrapping on periodic axes. Points in order; a point becomes a one-site cell if its site is in the lattice, in region ∩ domain and still medium, else it is not placed; coinciding points merge (first wins). `kinds` cycled over created cells; ids in creation order.
  - Growth: `rounds` synchronous rounds. Offsets `CorePotts.relation(nbh, lattice).offsets`, `nbh` = `neighborhood` or the lattice's own (TST grows with 8 neighbours even on a 20-neighbour lattice, P6.3e). Each round visits region ∩ domain sites in column-major order; a site is eligible if, at the round's start, it is medium with at least one neighbour owned by a cell this layer created. Each eligible site draws `j = rand(rng, 1:K)` from `rng = Potts.layer_rng(seed, :eden)` (shared by the layer; the `:eden` stream decorrelates it from a `RandomPoints` with the same seed) and joins the cell at `shift(x, offs[j])` at the round's end if that cell is one of this layer's cells as of the round's start. This is TST's law (uniform over all neighbours, copied only from a growing cell); skipping draws at sites with no growing neighbour changes only the stream, not the law.
  - Medium only, no `into` (as `Voronoi`, D-138; TST grows into medium only).
  - Report row `:Eden`: `requested` = points, `painted` = cells created, `misses` = requested − painted, `counted` = painted, `clipped` per D-138.
  - `ArgumentError`s: `rounds < 0`, empty `kinds`, a bad seed, `shortfall` or `splits`, a `neighborhood` that is not a `RelationSpec`, an empty point list, a dimension mismatch (at layout). `remake` works.
- **`Splits(layer, k; shortfall = :error, splits = :warn)`** (exported): TST `DivideCells` (ca.cpp:901-1002) as a host routine, sharing only the split geometry with the lifecycle's `AlongMinorAxis` (no `CPMState`, no trackers). `0 ≤ k ≤ 30`. It paints `layer` into its own report row (a delegating layer, D-091), then makes k passes.
  - Pass j visits the row's cells in id order as they stand at the pass's start; each cell with ≥ 2 sites is cut and its daughter (same kind) allocated right after the cut. Earlier layers' cells are never touched.
  - The cut: Cartesian site coordinates (`embed`); on periodic axes each site uses the image nearest the cell's first column-major site (displacement in [−n/2, n/2), ties to the lower image). c the centroid, C = Σ(p − c)(p − c)ᵀ, v the unit eigenvector of C's largest eigenvalue by CorePotts' 2D `AlongMinorAxis` rule (`(λ − C₂₂, C₁₂)`; if `|C₁₂| ≤ eps·(|C₁₁| + |C₂₂|)`, e₁ when `C₁₁ ≥ C₂₂`, else e₂); for a repeated largest eigenvalue, the first standard axis with a nonzero projection on its eigenspace, projected onto it; sign fixed so the first component with |vᵢ| > 1e-9 is positive. The daughter takes sites with d = (p − c)·v > 1e-9 · max |d| over the cell; sites on the plane, up to that relative tolerance, stay with the mother (TST's `j > aa2 + bb2·i`; amended after the P6.3c review — an exact Float64 `> 0` sent on-plane sites to the daughter in about a quarter of affected cells). A cell spanning more than half a periodic axis can be cut into pieces (the nearest-image unwrap is relative to its first site); deterministic, and reported by the one-piece check.
  - One-piece check: every cell of this row not in one piece under the lattice neighbourhood is recorded and counted once in the row's `splits`; `layout` warns after renumbering, naming the cell's final id ("cell N (kind k) of a Splits layer is not one piece …"), unless `:allow`, a later layer dropped the cell, or the overlay check already named it (amended after the P6.3c review: the warning used paint-time ids). In nested Splits a cell is counted once and the outermost Splits' `splits` decides whether it warns. `:allow` silences the warning, not the count. The overlay's "cut by a later layer" check (D-057/D-091) is unchanged.
  - Report row `:Splits`: `requested` = m·2ᵏ (m = the inner layer's cells owning a site), `painted` = the row's cells owning a site, `misses` = requested − painted, `clipped` = the inner layer's. `ArgumentError` for k outside 0:30 or a bad `shortfall`/`splits`; `remake(s; k)` works.
- **`shortfall = :error | :warn | :allow`** on `Eden` and `Splits` only (other layers keep their throws). Checked when `painted < requested` at the end of the layer's own paint: `:error` throws an `ArgumentError` naming the layer type, "shortfall", both counts and the remedy `shortfall = :allow`; `:warn` logs the same text and paints; `:allow` is silent. The report row is the same in all modes. Never inferred from `replace`; cells dropped by later layers are `dropped`, not a shortfall.
- **First `:allow` consumer:** 01b de novo, `overlay(Frame(:border; width = 1), Eden(RandomPoints(360; region = (2:199, 2:199), replace = true, seed); rounds = 10, kinds = [:endothelial], seed, shortfall = :allow))`, exercised by the frozen test and by a sibling/docs example in this item (coordinator: a consumer in code here, so `:allow` is not unused); its library home (Merks2008 layouts) is P6.3d. **Sprout:** `overlay(Frame(:border; width = 1), Splits(Eden(Center(); rounds = 50, kinds = [:endothelial], seed), 7; splits = :allow))` — 0–5 of 128 pieces are disconnected under Moore(1), as in TST, so P6.3d passes `:allow`.
- **No DSL change** (D-057). `Eden` and `Splits` clash with nothing exported in the depot (D-056's list, incl. Makie, SciMLBase, MTK, Graphs, DomainSets).
- **Open (spec).** Whether 01a (2006) used Eden seeding is spec 01's A-15, still open; it does not affect this item.
- **Frozen acceptance** `p6_3c_eden_splits.jl` (freeze e7af6d2f): `RandomPoints(replace = true)` against an independent StableRNG oracle (square, 3D, domain, periodic, hex, a wrapping shape region), duplicates, the shared stream prefix, `remake`; Eden hand fixtures (seeding and rounding, merging, a hole, closed and periodic strips), medium-only fill, region, domain, `clipped`; an independent Eden oracle on square, VonNeumann, hex and 3D (closed, periodic, domain, after an earlier layer) with a deterministic-growth control; stream-prefix, reach and determinism invariants; spec 01 §7.6 bands for de novo (357–360 cells, ≈ 47.6 px) and sprout (1 816–2 439 px); Splits hand cuts (box, isotropic tie, on-plane row, diagonals, hex rhombus 3/3 vs index-space 2/4, 3D, periodic unwrap), ids, kinds, conservation, earlier layers untouched, the one-piece warning and count, shortfall and argument errors. On 21683819: 4 pass, 13 fail, 26 error of 43, all on the missing surface; a stub passes 611/611.
- **Applied (implementer, coordinator-accepted).** LinearAlgebra (stdlib, already loaded transitively; no load-time change) for the N-D eigenvector; ties within 1e-9·λmax, projection nonzero above 1e-6; a cell with no site strictly on the positive side is not cut; Eden draws from a sorted candidate frontier (stream identical to the full scan: 670/670 against an independent oracle); non-symmetric neighbourhoods use negated offsets for candidates and forward offsets for eligibility.
- **Review (P6.3c).** Two rounds (round 1: on-plane sites sent to the daughter in Float64; warnings with paint-time ids). Against the freeze stub (which had the same on-plane bug) sprout moved 0–2 sites on seeds 4–7; frozen bands unaffected. Follow-ups: the on-plane tolerance's margin shrinks ~1/L² (risk only for cells ~3×10⁴ long); a Splits cell repaired into one piece by a later layer still gets the "not one piece" warning — re-check against the final σ before warning (fold into P6.3d, the first Splits consumer).
