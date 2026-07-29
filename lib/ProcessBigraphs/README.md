# ProcessBigraphs.jl

`ProcessBigraphs.jl` is an independent Julia implementation of a domain-neutral,
multirate process-bigraph runtime. It is incubating inside the Potts.jl
monorepo and is not yet a published package or a complete Process-Bigraph 2.0
implementation.

The package provides independently testable serial foundations:

- canonical typed hierarchical paths and deterministic encodings;
- structural leaf/branch schemas and logically immutable committed snapshots;
- typed ports, static wiring validation, and explicit residency preflight;
- normalized integer logical time;
- distinct temporal-process and zero-time-step declarations;
- a small typed update algebra with deterministic atomic reconciliation;
- a bounded imminent-event microfixture runner; and
- settled-boundary in-memory checkpoint/replay.

`ACSets.jl` 0.2.29, `Catlab.jl` 0.17.6, and `AlgebraicRewriting.jl` are direct dependencies.
One versioned `ProcessBigraphACSet` is the canonical structural authority. The ordinary Julia
`compose` builder produces an immutable `CompositeModel`, which lowers deterministically through
private implementation records to that canonical ACSet. Stable semantic identities, rather than
ACSet row numbers or declaration order, determine fingerprints and compiled provenance.

Validated authoring models compile into a frozen `StructuralEpoch` and an immutable indexed
`ExecutionPlan`. The serial runtime and checkpoint paths consume that plan and do not traverse the
ACSet or retain the authoring declaration or private `StaticComposite` IR as a second authority.
The frozen model, initial-state, final-state, and trace baselines remain exact.

Immutable open composition does not create a second runtime authority:

- selected typed stores become `import`, `export`, or `bidirectional` endpoints;
- reusable definitions mount under explicit namespace keys with distinct instance identities;
- exact-compatible endpoints join through named n-ary junctions;
- parent exports and initialization overrides are explicit;
- arbitrary finite static hierarchy is retained in the canonical ACSet and flattened into the
  existing execution plan;
- each open component exposes a real Catlab structured cospan; and
- a versioned annotated directed-wiring view round-trips losslessly, while generic Catlab diagrams
  remain inspection-only and fail closed if submitted for compilation.

Composition is pure and construction-order invariant. Types, shapes, units, ontology, update law,
persistence, residency, and endpoint transfer contracts must match exactly; no scientific
conversion is inferred. Runtime and checkpoint paths still consume only the frozen epoch and
indexed plan.

The immutable-topology serial runtime qualifies:

- exact fixed and adaptive scheduling with explicit exact/stop-prior horizons;
- changed-input reactive layers and named bounded or convergent iteration;
- four declared multirate interval-input policies;
- typed owner-bound process, step, and observer continuations;
- Philox4x32-10 semantic RNG with immutable lineage addresses and an isolated observer namespace;
- declarative typed observation at event, periodic, or explicit-time boundaries;
- deterministic fail-stop transactions covering all eight registered publication stages; and
- a canonical, integrity-checked v2 logical checkpoint envelope with exact compatible restart.

Current qualification covers the package suites, an independent stdlib-only 22-row specification
oracle, mutation targets, all registered failure stages, six authoring routes, restart cuts, and
frozen performance and allocation guardrails. Atomic structural transactions, solver-neutral
engine handoff, bounded Merks/CNV assemblies, and typed high-level authoring are included.

The authoring lifecycle is `CompositeModel` → `LoweredModel` → `ExecutionPlan` → mutable run
session. ProcessBigraphs owns when and why computation occurs; solver and CPM kernels retain
control of how their authorized heavy computation occurs.

ProcessBigraphs `0.6.0` is the Phase 17 candidate for the unpublished internal
beta. The retained source-addressed CPU, real Metal, and real ROCm claims
require exact-head requalification before this candidate is qualified.
`internal_beta = true`; `public_release = false` remains mandatory.

Ordinary models use a small Julia API rather than canonical IR:

```julia
model = compose(:CoupledModel; scale) do m
    field = store!(
        m, :field,
        LeafSchema(Float64; default=0.0, update_law=:add))
    solver = mount!(m, :solver, MySolver(config))
    schedule!(m, solver, Every(Duration(1, scale)))
    connect!(m, field, solver.field_in, solver.field_out)
    expose!(m, :field, field; role=:bidirectional)
end
```

Explicit names and typed handles determine semantic identity. `attach!` performs exact declared
bulk attachment only; it does not autowire approximately. `At` creates exact one-shot boundaries,
`On(store)` uses committed state publication, and `After` declares reactive stage order.
`SimulationProblem` binds initial state, typed parameter overrides, selected observables, exact
state interventions, time span, and master seed without changing the reusable model.

Direct `StaticComposite`, declaration, and port-binding construction is restricted to lowering,
canonical conformance, migration, and independent oracle code. Supported semantic archives require
explicit domain-owned component encoders and decoders; ProcessBigraphs does not serialize closures
or use a global runtime registry.

`AlgebraicDynamics.jl` is not currently a dependency or qualified extension. ProcessBigraphs
remains the sole authority for time, scheduling, logical state, reconciliation, commit, RNG,
observation, checkpoints, and replay.

Conformance uses a separate checked Julia specification oracle, source-located derivations, truth
tables, and property, metamorphic, invariance, failure, and restart tests. Production, oracle, and
comparison execute in separate Julia processes; the oracle process is restricted to stdlib roots.
Project tooling does not install or execute Vivarium, Process-Bigraph Python, or Bigraph-Schema
Python.

The current maturity, limitations, and exact parity pins are recorded in
[`parity-registry.toml`](parity-registry.toml). Internal contracts, ordinary open-composition
authoring, and the advanced AlgebraicJulia path are documented in
[`docs/src/architecture.md`](docs/src/architecture.md). Start with the
[internal-beta guide](docs/src/internal-beta.md), then use the
[adapter and solver guide](docs/src/adapters-and-solvers.md),
[failure and persistence guide](docs/src/failure-and-persistence.md), and generated
[capability matrix](docs/src/capabilities.md).

Historical qualification artifacts retain their original milestone-coded paths and identifiers.
They are indexed by the repository
[historical artifact index](../../design/evidence/consolidation-naming/historical-artifact-index-v1.toml);
primary documentation does not use those milestones as the current architecture.

Run the package suite with Julia 1.12.6:

```sh
julia --project=. -e 'using Pkg; Pkg.test()'
```

This package has no dependency on CorePotts or PottsToolkit. It is licensed
under the repository [MIT license](../../LICENSE).
