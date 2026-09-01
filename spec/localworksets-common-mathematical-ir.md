# LocalWorksets Common Mathematical IR Research

Date: 2026-08-16

Status: authoritative for the common-IR decision and its 2026-08-16
implementation record. Its authoring-language design is superseded by
[Typed LocalWork and CorePotts Adoption](localworksets-typed-language-and-core-adoption.md),
whose package identity, authoring surface, and future work order are in turn
superseded by the committee-accepted
[LocalMath Direct Cutover](../design/evidence/localmath/localmath-direct-cutover.md). The one-common-IR and
one-execution-architecture decision survives.

Implementation status: Phases 1--6 completed by direct edit and the final
four-perspective review accepted on 2026-08-16

## Direct implementation record

The approved hybrid was implemented without a second mathematical execution
path:

- Phase 1 replaced stringly conjunctive-family admission with one
  package-owned descriptor, consolidated the ordinary/buffered/keyed result
  validators behind one declaration-derived result contract, and centralized
  generic binding authority.
- Phase 2 added closed host-only `SourceOrigin`. Planning and kernels retain
  only the bare concrete callable.
- Phase 3 added the original closed scalar-authoring grammar. It was
  subsequently replaced directly by the typed `@localwork` language specified
  in [Typed LocalWork and CorePotts Adoption](localworksets-typed-language-and-core-adoption.md).
- Phase 4 replaced the former witness-only operation types for D2Q9,
  lattice-spring, matrix-free FEM, particle/contact, and fragment rendering.
  The explicit numerical oracles remain independent.
- Phase 5 added one typed CorePotts checkerboard-proposal emitter that derives
  the scalar schedule from the compiler-owned descriptor plan and combines it
  with Core-owned checkerboard capacity/epoch facts to construct the complete
  `LocalWork` and topology declaration. No Potts author writes a LocalWorksets
  declaration.
- Phase 6 freezes only the waist, callable protocol, authoring grammar,
  existing conflict declarations/sequence, and provenance described below.

The Phase 5 audit corrected one premise in the proposed work: after Gates
0--5A there were no surviving Core-side LocalWorksets schema/route validators
or adapter hierarchy to delete. The checks that remain validate canonical
checkerboard identity, descriptor source layout, before/device adaptation,
and topology epoch. Those are Core scientific/compiler preservation laws and
must not be moved into LocalWorksets. The emitter removes declaration
construction from preparation while preserving those checks.

The proposal schedule is deliberately value-specialized into
`_FusedCheckerboardProposalOperation{schedule}` during one-time host
preparation. Schedule length and entries arise from runtime compiler-owned
descriptor vectors, so the emitter itself is a staging/function-barrier
boundary rather than an inference promise. The resulting `PreparedWork`,
operation type, callback return, execution workspace, and repeated `run!` path
are concrete; tests assert those facts. No schedule dispatch occurs inside a
submitted kernel.

Evidence recorded for this implementation:

- explicit and mathematical authoring have equal lowering identity, phase
  types, launch count, workspace schema, binding requirements, capability,
  and determinism evidence;
- the functional LocalWorksets evidence through direct, buffered, resolved,
  seeded, runtime-keyed, heterogeneous named-port, runtime, and adversarial
  admission paths passes after the validator consolidation;
- all five converted cross-domain models execute against their independent CPU
  oracles;
- all five converted models device-compile and match those oracles on actual
  Metal with scalar fallback disabled; and
- the edit adds zero `_central_admission`, preparation, `_execute_phase!`,
  `@kernel`, vendor-backend, or old/new execution-selector families.

The initial physical-line census was 11,580 lines under
`lib/LocalWorksets/src`; the final source is 11,849 lines. The net 269-line
increase includes the 99-line syntax translator, concrete provenance,
stage-aware planning/preparation/settlement diagnostics, and inspection. It is
not a raw LoC reduction. The implementation nevertheless deletes semantic
duplication: three result-contract implementations became one, arbitrary
named-family admission disappeared, and five unrelated models reuse the same
front end without a new planner or kernel. The simplification claim is about
authorities and paths, not fewer physical lines.

Final implementation census:

| Measure | Gates 0--5A baseline | Final | Change |
|---|---:|---:|---:|
| physical / nonblank / code-like LocalWorksets source lines | 11,580 / 10,948 / 10,850 | 11,849 / 11,196 / 11,098 | +269 / +248 / +248 |
| general common semantic IRs | 1 (`LocalWork`) | 1 (`LocalWork`) | 0 |
| persistent mathematical-expression IRs | 0 | 0 | 0 |
| result-contract authorities | 3 | 1 | -2 |
| distinct `_validate*` names | 47 | 46 | -1 |
| semantic leaf mechanisms / optimized strategies / composers | 4 / 6 / 1 | 4 / 6 / 1 | 0 / 0 / 0 |
| LocalWork lowering stages | 3 | 3 | 0 |
| central admission / public preparation / execution-dispatch families | 1 / 1 / 1 | 1 / 1 / 1 | 0 / 0 / 0 |
| prepared phase executor methods | 14 | 14 | 0 |
| textual kernels | 14 | 14 | 0 |
| CPU-versus-non-CPU / vendor-specific execution branches | 10 / 0 | 10 / 0 | 0 / 0 |
| old/new execution selectors | 0 | 0 | 0 |

This table is a historical census of the earlier implementation, not the
current authoring API. Its temporary scalar-authoring wrapper was deleted;
current typed authoring constructs `LocalWork` directly. `SourceOrigin` is
stored on `LocalWork` as host evidence and does not enter `_LoweredWork`, a
prepared callback, or a kernel argument.

## Decision under review

The candidate decision is a deliberately narrow hybrid:

```text
domain notation and domain semantic IRs
                  |
        scalar Julia/Symbolics compilation
                  v
      LocalWork spatial/publication IR
                  v
          _LoweredWork / WorkPlan
                  v
          KernelAbstractions phases
                  v
       CPU / GPU / future partition owner
```

`LocalWork` is the only common semantic waist. It owns bounded item and
emission domains, named read bindings, selection, local-calculation invocation,
routing, assignment, folding, resolution, named multi-port publication, and
finite ordered composition. The access relation inside an arbitrary callable
is `opaque` until a compiler-derived or mechanically enforced read declaration
proves it. `_LoweredWork` is the one private execution-planning representation.
A domain compiler may keep a richer scientific IR above this waist, and may
compile scalar algebra into an ordinary concrete Julia callable before
constructing `LocalWork`.

The candidate rejects a second general `LocalLaw` hierarchy. The missing facts
identified by the research -- provenance, bounded gather/footprint facts, and
some richer folds -- are dimensions of `LocalWork`, its reads, or its outputs.
Duplicating items, reads, outputs, active selection, gate, and operation in a
new value would add a lowering pass and another semantic authority while
deleting nothing.

This is not a claim that `LocalWork` is the scientific IR for Potts, LBM, LSM,
or FEM. It is the common mechanical local-law IR below those scientific IRs.

## Falsification conditions

Reject or revise this candidate if implementation demonstrates any of the
following:

1. A required scientific fact must be interpreted by LocalWorksets rather than
   merely preserved as opaque provenance.
2. Mathematical syntax requires a runtime expression tree on a GPU path.
3. Explicit and mathematical authoring lower into different planning or kernel
   families.
4. A new representation duplicates `LocalWork` fields and survives after
   lowering.
5. A feature adds validators, adapters, or backend branches without deleting or
   reusing an existing path.
6. Deterministic order, tie breaking, empty behavior, publication gating, or
   proposal RNG order becomes implicit.
7. A domain name appears in LocalWorksets admission or execution.

## Round 1 -- internal architecture and deletion analysis

### Existing representations and their authority

`LocalWork{I,R,O,A,G,F}` is already the semantic declaration. It contains one
bounded item domain, named logical reads, named output laws, active selection,
a scalar execution gate, and the local calculation. The three general output
families already distinguish:

- unique or explicitly partial assignment;
- deterministic canonical-order or explicitly relaxed folding; and
- rank/payload resolution with a declared tie law and empty behavior.

Routes may be fixed, identity, or bounded runtime keys. One calculation may
publish multiple named ports. `sequence` is finite ordered composition without
a scheduler.

`_LoweredWork{M,B,W,P}` is not a rival semantic IR. It is the single private
planning result: qualified mechanism, binding authority, workspace authority,
and phase tuple. `WorkPlan` combines the declaration, topology, backend,
lowering, and evidence. `_PreparedPipeline` replaces plan-time phase tags with
prepared phase values and backend topology/status. These values correspond to
different lifecycle stages and should not be collapsed merely to reduce the
type count.

CorePotts' `AnalyzedTermIR`, `ProposalDescriptor`, `StaticEvaluator`, affected
anchor plans, stage descriptors, and proposal contexts retain information that
must not enter LocalWorksets: Hamiltonian categories, before/after proposal
meaning, resource and affected-region proofs, canonical Hamiltonian source
order, semantic RNG, acceptance, lifecycle, and checkpoint meaning.

### Duplication and consolidation map

The strongest present duplication is not between `LocalWork` and
`_LoweredWork`; it is between declarations and ad-hoc mechanism recognition.
In particular, `localwork` currently admits a named tuple carrying a `family`
symbol, planning recognizes `:resolved_conjunctive_selection`, and the
conjunctive implementation revalidates the tuple shape and family. Replace
that stringly external declaration with one package-owned concrete mechanism
descriptor and dispatch. Delete the generic named-family exception.

A larger and more important duplication exists in result validation.
`_validate_independent_result_type`, `_validate_emission_result_type`, and
`_validate_keyed_result_type` each reconstruct the operation's named-port,
lane, key, rank, payload, conditionality, and arity contract. Phase 1 derives
one typed result schema from `work.outputs` and uses it for ordinary, buffered,
and keyed validation. The same schema is the sole target for explicit callables
and mathematical authoring. Central port-plan accessors likewise derive
ordinary/keyed binding authority rather than preserving parallel meanings.

The proposed scalar-law authoring envelope must not become a second operation
authority or survive inside `LocalWork.operation`. `localwork` immediately
normalizes it to the bare concrete callable and stores its origin in a separate
host-only provenance field. Planning and kernels therefore see exactly the
same operation as explicit authoring. Mathematical syntax produces only this
immediately erased input; it creates no AST, device wrapper, or executor.

The following representations are retained:

- `LocalWork`: semantic waist;
- `_LoweredWork`: private plan/schedule result;
- `WorkPlan`: reusable validated plan and evidence;
- `_PreparedPipeline`: prepared backend values;
- domain descriptor IRs: domain meaning above the waist.

The internal baseline measured after Gates 0--5A is:

| Measure | Count |
|---|---:|
| LocalWorksets physical / nonblank / code-like lines | 11,580 / 10,948 / 10,850 |
| relevant CorePotts / Potts compiler / witness physical lines | 24,225 / 10,380 / 1,487 |
| LocalWork semantic node types | 22 |
| mechanism/lowered representation types | 7 |
| plan phase tags / prepared phase types | 14 / 14 |
| concrete semantic/lowering/phase types | 57 |
| principal lifecycle envelopes | 5 |
| semantic leaf mechanisms / optimized strategies / composers | 4 / 6 / 1 |
| LocalWork lowering stages | 3 |
| distinct `_validate*` names | 47 |
| CPU-versus-non-CPU / vendor-specific execution branches | 10 / 0 |
| textual kernels / instantiated kernel source variants | 14 / 20 |
| concrete Core adapter/projection types / prepared operations | 6 / 2 |

The semantic leaf mechanisms are direct independent, buffered
combined/resolved, runtime-keyed grouped, and conjunctive resolved. Singleton
resolved is a private optimized strategy, not a new semantic family. The
former fixed-count seeded specialization is retired in favor of the general
canonical combined law. Phase tags and prepared phases remain unless a change proves equal
inference and generated device code.

The following authority is removed or forbidden:

- arbitrary named-tuple `family` operation declarations;
- a parallel public `LocalLaw` object graph;
- a Symbolics expression stored in a `LocalWork` device operation;
- per-domain LocalWorksets adapters or domain-name admission branches; and
- explicit-versus-mathematical execution selectors.

### Missing common-waist facts

The five-model pass identified real gaps, but not grounds for a duplicate IR:

1. **Origin/provenance.** A typed, opaque source reference must join
   `inspect(LocalWork)` to its domain compiler or source equation without
   putting a domain object on the device.
2. **Bounded gather/footprint.** Reads currently identify bindings and topology
   routes, but arbitrary callable indexing is opaque. A future read declaration
   must be able to describe a fixed-offset stencil or bounded indirect
   incidence relation. Until accesses are compiler-derived or mechanically
   enforced, inspection must say `opaque`, not trust an external trait.
3. **Product folds.** Exposing the inside of CorePotts proposal evaluation would
   require one canonically ordered fold over heterogeneous numeric and Boolean
   fields. This is not needed for the current coarse proposal `LocalWork` and
   must be added only with a non-Potts witness and a concrete deletion target.
4. **Fusion legality.** General fusion requires snapshot, dependency,
   visibility, effect, and RNG-order facts. `sequence` provides ordered
   visibility, not a public promise of kernel fusion.
5. **Partition facts.** Halo analysis needs global/local ownership, read
   footprints, boundary rules, and cross-partition conflict settlement.
   LocalWorksets may report requirements; a grid/domain layer must own
   communication and decomposition.
6. **AD.** Scalar AD belongs to a domain/scalar compiler. LocalWorksets may later
   expose mechanical transpose rules for gathers and folds, but selections and
   nondifferentiable laws require explicit domain policy.

`SourceOrigin` is a closed, monomorphic package-owned host record with only a
source string, integer line, and optional symbol label. It is a concrete field
of `LocalWork`, not a type parameter. It accepts no domain object, AST, module,
callable, or mutable graph. Origin never affects admission, lowering,
fingerprints, cache identity, workspace, adaptation, callbacks, or kernel
specialization and is available only to inspection and diagnostics. Structural
evidence must prove that no apply-kernel argument contains it.

### Deletion criterion

The first implementation must remove the named-family declaration path,
centralize the three result-schema validators, and centralize ordinary/keyed
port binding authority while adding no execution family. The expected result
schema deletion is 100--160 production lines and the port-authority deletion is
20--40 lines. Later footprint or product-fold work is admitted only when it
consolidates validators/planners or replaces a real downstream kernel. Line
count is recorded at every gate, but semantic-authority and execution-family
counts are the primary metrics.

## Round 2 -- external architecture research

Only mechanisms solving demonstrated LocalWorksets problems are adopted.

| System | Relevant mechanism | LocalWorksets conclusion |
|---|---|---|
| [ModelingToolkit](https://docs.sciml.ai/ModelingToolkit/dev/internals/systems/) and [Symbolics](https://docs.sciml.ai/Symbolics/stable/manual/functions/) | Rich symbolic systems transform and compile to numerical functions | Use as an optional scalar authoring/compiler layer; do not use it for topology, conflicts, publication, or GPU execution. |
| [Catalyst](https://docs.sciml.ai/Catalyst/stable/api/core_api/) | One scientific reaction model lowers to several numerical problem forms | Preserve domain meaning above a reusable lower waist. |
| [UFL](https://docs.fenicsproject.org/ufl/main/manual/form_language.html) and [Firedrake](https://arxiv.org/abs/1501.01809) | Mathematical forms remain distinct from mesh/access/execution descriptions | Keep weak forms and basis meaning in FEM; make access and contribution laws explicit below them. |
| [Devito](https://www.devitoproject.org/) | Symbolic equations lower through dependency and stencil analysis before backend code | Add inspectable footprints before attempting halo or fusion inference. |
| [ParallelStencil / ImplicitGlobalGrid](https://arxiv.org/abs/2211.15716) | One stencil source targets xPUs; a separate layer owns distributed halo exchange | Keep communication outside LocalWorksets and report the required regions. |
| [Tullio](https://github.com/mcabbott/Tullio.jl) | A macro translates concise index notation and reductions to Julia/KernelAbstractions | Borrow syntax translation and diagnostics, not an implicit conflict law. |
| [Finch](https://finch-tensor.org/Finch.jl/stable/docs/language/calling_finch/) | Typed loop/control-flow IR and inspectable generated code | Keep inspection, but do not import a sparse compiler hierarchy. |
| [Taichi](https://yuanming.taichi.graphics/publication/2019-taichi/taichi-lang.pdf) | Separates computation from sparse data structure/layout | Keep topology/layout distinct from scalar laws; avoid a new runtime. |
| [Simit](https://people.csail.mit.edu/jrk/simit.pdf) | Local graph laws contribute through explicit assembly reducers | Closest precedent for `items x routing x contribution law`; domain global solvers remain above. |
| [Halide](https://halide-lang.org/) | Algorithm and schedule are separate | `_LoweredWork` is the private schedule boundary; do not expose a schedule language. |
| [GraphIt](https://arxiv.org/abs/1805.00923) | Algorithm and performance schedule are separate | Backend planning may choose strategies, but domain authors should not select execution families. |
| [MLIR](https://mlir.llvm.org/docs/Rationale/Rationale/) | Progressive lowering retains only facts needed at each level | Retain explicit legality and provenance; do not build dialect/pass infrastructure. |

The external evidence consistently rejects Symbolics as the whole waist. Scalar
expression trees do not contain routing, conflict, topology, publication,
workspace, event, or deterministic numerical-order meaning. It also rejects a
public schedule/task graph. Simit, UFL/Firedrake, Devito, and
ParallelStencil/ImplicitGlobalGrid support a narrow local law below domain
meaning and above execution, with topology and communication assigned to the
proper layer.

## Round 3 -- complete scientific feasibility

### CorePotts Hamiltonian/proposal

```text
scientific notation
  Delta H_s(p) = sum_a [H_s(a, after(p)) - H_s(a, before(p))]
  log alpha = -(Delta H + drive_energy)/T + drive_log_bias + kinetic_modifier
      |
domain semantic IR
  QualifiedStatement -> AnalyzedTermIR -> ProposalDescriptor{StaticEvaluator}
  + affected-anchor plan + canonical descriptor schedule
      |
LocalWork
  checkerboard proposal items
  immutable science snapshot + active prefix
  one concrete ProposalOperation{Schedule}
  independent disposition and proposal-record ports
      |
plan
  one direct apply/publish phase on the selected backend
```

LocalWorksets must not interpret Hamiltonian categories, affected anchors,
before/after views, descriptor source order, RNG, Metropolis acceptance, MCS
scheduling, or transactions. The existing coarse lowering is valid and GPU
compatible. A future heterogeneous product fold could expose more internal
calculation only if it preserves exact source order and deletes Core machinery.

### D2Q9 collide/stream

```text
f_i* = f_i - omega (f_i - f_i_eq)
f_i(x + c_i, t + 1) = f_i*(x),  rho = sum_i f_i*
      |
LBM collision/boundary semantic IR
      |
LocalWork over cells
  logical gather: nine populations
  current proof: opaque callable indexing
  future proof: fixed-offset stencil read
  assign nine fixed-routed streamed populations
  assign one identity-routed moment record
      |
one direct planned phase
```

LBM retains velocity-set, equilibrium, boundary, conservation, and timestep
meaning. LocalWork retains only the named-read, bounded-emission,
invocation/routing/publication law. A mechanically proved stencil footprint is
needed before deriving 3D halos.

### Lattice spring force, damage, and fracture

```text
epsilon_e = length_e - rest_e
F_a += k epsilon_e; F_b += -k epsilon_e
d_e' = d_e + |epsilon_e|  (representative irreversible witness law)
winner_z = argmax(extension, tie = canonical edge id)
      |
LSM constitutive/damage/fracture IR
      |
LocalWork over edges
  independent edge state
  deterministic or explicitly relaxed two-endpoint force fold
  conditional resolved fracture candidate
  ordered pointwise damage stage before fracture evaluation
      |
generic combined/resolved plan + sequence
```

LSM retains constitutive, orientation, units, irreversibility, fracture, and
topology-mutation meaning. The domain IR must state whether fracture observes
old or newly updated damage. An ordered LocalWork sequence makes the selected
visibility mechanical; topology mutation becomes visible only after the
domain-owned fracture/commit boundary.

### Matrix-free FEM element application

```text
r_e = K_e x_e;  r_a = sum_(e,l: connectivity(e,l)=a) r_e,l
      |
FEM weak form, basis, quadrature, geometry, material, and BC IR
      |
LocalWork over elements
  logical gather: element DOFs
  current proof: opaque callable indexing
  future proof: validated finite-incidence read
  deterministic or relaxed fixed-incidence residual fold
      |
generic combined plan
```

FEM retains weak-form and solver meaning. A bounded incidence read is needed
for honest halo/transpose inspection, but not for current single-device
execution.

### Runtime-keyed deposition/rendering

```text
q_j = sum_(p,l:key(p,l)=j) w_(p,l) q_p
front_j = argmin(depth, tie = canonical materialized record identity)
      |
deposition/visibility semantic IR
      |
LocalWork over particles or fragments
  runtime-keyed deterministic fold
  runtime-keyed resolved payload
  one evaluator and several named ports
      |
initialize -> evaluate -> validate -> ordered named-port publication
```

The domain retains interpolation, geometry, visibility, and key-generation
meaning. LocalWorksets retains bounded keys, no-write-before-validation,
conflict laws, and publication order. A domain may call this a canonical
fragment-ID tie only after proving that its fragment ordering is identical to
the materialized record order. An independently emitted runtime semantic tie
identity is deferred and not claimed by the current waist.

### Coverage of required mechanical laws

| Requirement | Existing common-waist representation |
|---|---|
| unique assignment | `independent`, full or partial coverage |
| deterministic fold | `combined(... deterministic(...))` with canonical item/lane order |
| explicitly relaxed fold | `combined(... fast(...))` after backend/type qualification |
| argmin/argmax + payload + tie | fixed routes accept explicit semantic identities; runtime routes currently tie by canonical materialized record order |
| conditional participation | conditional `emit` / `candidate`, active selection, work gate |
| fixed routing | named topology routes and identity routes |
| runtime routing | bounded `runtime_route` with prepublication validation |
| multiple ports | named output tuple from one operation invocation |
| ordered stages | `sequence` with provider-order visibility |
| pointwise update | qualified `pointwise_read` and identity-routed publication |
| record values | concrete isbits values and qualified StructArray storage |
| provenance | missing; add typed opaque origin metadata |

## Alternatives

### A. LocalWork as the common IR -- selected

Enhance `LocalWork` and its read/output vocabulary only where demonstrated.
Mathematical syntax and domain compilers construct the same value. This has one
semantic waist, one planner, and one executor.

### B. Small LocalLaw above LocalWork -- rejected for now

A second object is justified only if it carries required transformable meaning
that cannot be represented as a `LocalWork` field or declaration. The proposed
items/reads/gathers/evaluator/ports/active/gate/access/origin shape duplicates
`LocalWork`. A one-to-one erasing pass has no optimization or deletion payoff.
Reconsider only after a real transformation requires a persistent equation DAG
that cannot compile directly to a callable plus `LocalWork` declarations.

### C. Symbolics as the entire IR -- rejected

Symbolics is suitable for scalar algebra, substitution, differentiation, and
code generation. It is not the authority for bounded emission, routing,
coverage, deterministic numerical order, rank/payload coherence, topology,
workspace, publication, or event semantics.

### D. Hybrid -- selected interpretation

The selected hybrid is not B plus C. It is:

- domain or Symbolics values for scientific/scalar meaning on the host;
- a concrete isbits Julia callable for device scalar calculation;
- `LocalWork` for spatial and publication meaning; and
- `_LoweredWork` for execution strategy.

Ordinary concrete callables remain first-class. No package is required to use
Symbolics.

## Candidate direct-edit implementation

### Phase 1 -- establish the common waist

1. Replace arbitrary named-tuple mechanism-family admission with a
   package-owned concrete conjunctive-selection descriptor and dispatch.
2. Derive one typed expected result schema from output declarations and replace
   the ordinary independent, buffered emission, and runtime-keyed result
   validators with it. Exact callable applicability and inferred return type
   remain prepare-time proofs because storage and submission types become
   concrete there; no `Any`-typed speculative planning is introduced.
3. Centralize port-plan accessors and ordinary/keyed binding authority.
4. Centralize operation normalization, origin inspection, and operation-kind
   accessors.
5. Keep `LocalWork`, `_LoweredWork`, `WorkPlan`, and `_PreparedPipeline` as the
   only semantic/planning/prepared lifecycle values.
6. Record semantic-authority, lowering-pass, execution-family, validator,
   backend-branch, and production-line counts before and after.

No compatibility constructor or old/new selector survives.

### Phase 2 -- separate scalar expressions from spatial laws

Store host source-origin metadata directly on `LocalWork` beside a concrete
isbits callable. Provenance never reaches preparation callbacks or a kernel
argument. `inspect` reports the normalized operation representation and
provenance. No authoring envelope contains items, reads, outputs, routes,
schedules, AST nodes, or Symbolics values.

The executable scalar protocol already exists:
`f(item::Int32, reads, values) -> NamedTuple`. A programmatic compiler passes
that callable and `origin=SourceOrigin(...)` directly to `localwork`. A
Symbolics or MTK adapter must compile completely to `f` before calling it. The
typed macro constructs origin beside the callable, never inside its closure.
Unsupported or non-isbits captures reject during construction. Exact callable
applicability and result inference are qualified during preparation;
selected-device legality is finally proved by device compilation.

### Phase 3 -- mathematical front end

Add one syntax-only macro:

```julia
work = @localwork item in items begin
    @read x
    @port residual::Float32 = combined(...)
    local_value = x[item]
    residual ← emit(local_value)
    residual ← emit(-local_value)
end
```

Ordinary `=` creates scalar intermediates. Exact-typed `:=` equations define
bounded immutable local tensors. Top-level `←` statements supply publication
contributions using the existing `emit` and `candidate` vocabulary, so
conditions, runtime keys, multiple lanes, and payloads do not acquire duplicate
semantic authority. The macro returns an ordinary `LocalWork` whose concrete
callable produces the canonical named tuple expected by `localwork`.

Assignment, fold, and resolution remain authoritative in the explicit output
declarations:

```julia
outputs = (
    state = independent(...),
    residual = combined(...; combine = deterministic(+, 0f0)),
    winner = resolved(...),
)
```

Neither `:=` nor `←` infers a conflict law. `sequence` remains the one
finite-composition construct. The macro does no planning, execution, runtime
evaluation, or code generation by string.

The accepted grammar is closed:

- the header is exactly `item in items`;
- declaration markers form a preamble and declare reads, submission values,
  static axes, selection, gate, and exact-typed ports;
- tensor equations are exact-typed, immutable, and statically bounded;
- port brackets identify authoritative contiguous local emission lanes, never
  runtime destinations;
- runtime keys remain explicit arguments to `emit` or `candidate`;
- nested assignment, explicit `return`, dynamic control flow, and unreviewed
  nested macros reject at macro expansion;
- ordinary statements and right-hand sides execute once in source order;
- a port equation does not introduce a subsequently readable local binding;
- after evaluation the macro constructs a lexicographically canonical
  `NamedTuple`, matching `localwork` output canonicalization; and
- the result is checked by the same declaration-derived typed result schema as
  an explicit callable.

`:=` means a typed local tensor equation and `←` means a publication
contribution. Neither means mutation, infers a fold, selects an execution
strategy, or creates a second execution order.

The macro guarantees syntax translation, a concrete callable candidate, one
execution path, and no runtime AST. It does not make arbitrary Julia code
device-legal. Allocation, dynamic dispatch, recursion, exceptions, or host-only
APIs reject during selected-device qualification with the captured origin in
the diagnostic.

### Phase 4 -- cross-domain validation

Rewrite D2Q9, lattice-spring, matrix-free FEM, and fixed-route z-buffer work
with the typed language. Keep their independent numerical oracles. The two
runtime-keyed named-port witnesses deliberately remain explicit zero-field
isbits callables until stable grouping and shared no-write publication are
requalified; they move to typed syntax only in the later language-completion
phase. This is an authoring boundary, not a parallel execution path.

At least one paired explicit-versus-typed witness must have equal
lowering identity, phase-type tuple, launch count, workspace schema, binding
authority, capability evidence, and determinism evidence. The resulting
execution must add zero `_central_admission`, preparation, `_execute_phase!`,
or `@kernel` families. Callable specializations are not execution paths.

### Phase 5 -- CorePotts compiler adoption

The coarse fused checkerboard proposal family already uses the common
`LocalWork` execution waist. Do not perform a ceremonial authoring-wrapper
edit. Instead, move construction of its items, read roles, two port laws,
active selection, identity routes, destination counts, and compiler origin into
one typed compiler emitter derived from the compiler-owned descriptor/stage IR.
The post-Gates-0--5A audit found no surviving Core-side LocalWorksets adapter
hierarchy or duplicate schema/route validator to delete; do not recreate one.
The emitter derives checkerboard mechanics from Core-owned engine/stage IR; it
does not make descriptor scientific IR the owner of checkerboard topology.
LocalWorksets remains the central validator of the emitted `LocalWork` schema
and routes. Core retains canonical-plan, descriptor-layout, adaptation, and
topology-epoch preservation checks because those are scientific/compiler
facts, not LocalWorksets validation. The existing concrete scheduled operation
remains the scalar calculation emitted into the resulting `LocalWork`.

Ordinary Potts authors see no LocalWorksets syntax. Hamiltonian evaluation,
source order, proposal views, RNG, acceptance, and MCS/lifecycle meaning remain
Core-owned. The phase is complete only if the emitter centralizes declaration
construction, introduces no adapter or validator family, and ordinary Potts
authors remain unaware of LocalWorksets; wrapping the current callable does
not count as adoption.

Expansion inside proposal evaluation is deferred until bounded gathers and
product folds have unrelated witnesses and delete more code than they add.

### Phase 6 -- syntax and extension freeze

Freeze only:

- `LocalWork` as the common spatial/publication waist;
- the existing concrete callable protocol and direct `SourceOrigin` input;
- typed `@localwork` local tensor equations and publication contributions;
- existing output/conflict declarations and `sequence`; and
- inspectable origin and calculation representation.

Do not freeze a general expression-node API, pass manager, scheduler, halo
runtime, AD system, Symbolics dependency, or a claim of halo completeness.

## Phase evidence gates

At every phase boundary record:

- exact scientific/oracle parity;
- type inference of the local calculation and planned/prepared values;
- CPU and actual GPU launch/device-compilation legality with no fallback or
  runtime AST;
- deterministic order, fixed-route semantic identities, runtime canonical
  record ties, empty behavior, and invalid-input no-write law;
- inspection completeness and provenance;
- semantic-authority and execution-family count;
- added/deleted production lines and removed branches; and
- readability of the five complete model chains.

Any phase that adds an abstraction without either deleting an authority/path or
being reused by at least two unrelated domains is removed before the next
phase.

## Deferred work, with admission requirements

### Bounded gathers and halo facts -- admitted narrow extension

`bounded_read(binding, route; maximum=K)` is the one admitted spatial-read
declaration. It lowers directly into `LocalWork`; no LocalLaw or scheduler IR
was introduced. A user assertion attached to an arbitrary callable is not a
proof. The executable route is either an immutable `fixed_offset_route` with
`D=1:4`, `K=1:32`, exact `Int32` geometry and strict-in-bounds semantics, or a
host `Matrix{Int32}` with shape `K × item_count` and a positive-prefix,
zero-suffix incidence law. Planning validates route structure. Preparation
validates the exact fixed source shape or every positive incidence endpoint
against the exact source binding length before topology transfer, workspace
allocation, provider construction, or execution.

The sole generated item-read boundary materializes `GatheredValues{K,T}` after
active selection. The operation never sees the source array or indices.
Concrete Julia callables remain first-class and no runtime symbolic tree is
required. The same materializer is used by direct, buffered, keyed, and
singleton-resolved execution.

`active_indices(route; prefix=nothing)` selects an immutable topology-owned
`Vector{Int32}`. Planning proves strict increase and item-domain bounds; the
vector is fingerprinted and copied once. The optional existing `Int32`
submission prefix selects its first entries. Slot-to-item mapping is central,
so sparse evaluation preserves logical item identity and canonical publication
order without a dense membership workspace or a second executor.

Inspection derives exact lower and upper halo depths from fixed offsets. A
partition owner must intersect finite-incidence endpoints with its ownership
map, so incidence reports `owner_intersection_required`; ordinary callable
indexing remains opaque. Cross-partition publication additionally requires
owner selection and distributed conflict settlement, and ordered-stage
footprints cannot be blindly unioned across visibility boundaries. These
remain outside LocalWorksets. This feature does not claim distributed
readiness, own partitions, schedule exchange, or infer geometry from IDs.

### Heterogeneous product folds

Require at least one non-Potts witness, per-field identities/operations,
canonical product order, record-layout qualification, and deletion of an
existing specialized fold. Do not create a Potts-shaped `ProposalEvaluation`
mechanism.

### Fusion

Keep fusion private. Admit a fusion only from explicit snapshot, dependency,
visibility, effect, and RNG-order facts and only when it preserves the same
semantic `LocalWork` sequence. Never expose a public schedule.

### AD

Scalar expression compilers may differentiate the concrete calculation.
Mechanical gather/fold transpose laws can be added later. Resolved selection,
nondifferentiability, and scientific parameter meaning remain explicit domain
policy.

## Committee questions

The independent committee must reject this candidate unless it can answer yes
to all of the following:

1. Is another general IR unnecessary today?
2. Does Phase 1 remove a real semantic authority rather than rename it?
3. Do scalar mathematics, spatial effects, and execution strategy remain
   separate?
4. Can all domains use the same `LocalWork` and planning path?
5. Is every device-reachable value concrete and isbits, with no runtime AST?
6. Are deterministic folds, ties, empties, gates, and publication still exact?
7. Is the footprint/halo path honest about what is proved versus opaque?
8. Are CorePotts, LBM, LSM, and FEM meanings retained by their domains?
9. Are the five models clearer without hiding conflict semantics?
10. Is this smaller than a separate LocalLaw or Symbolics-wide design?
