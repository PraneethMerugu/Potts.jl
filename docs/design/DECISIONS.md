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
