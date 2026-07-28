# ProcessBigraphs.jl

`ProcessBigraphs.jl` is an independent Julia implementation of a domain-neutral,
multirate process-bigraph runtime. It is incubating inside the Potts.jl
monorepo and is not yet a published package or a complete Process-Bigraph 2.0
implementation.

Phase 14.PB0 provides independently testable serial foundations:

- canonical typed hierarchical paths and deterministic encodings;
- structural leaf/branch schemas and logically immutable committed snapshots;
- typed ports, static wiring validation, and explicit residency preflight;
- normalized integer logical time;
- distinct temporal-process and zero-time-step declarations;
- a small typed update algebra with deterministic atomic reconciliation;
- a bounded imminent-event microfixture runner; and
- settled-boundary in-memory checkpoint/replay.

Phase 15.A implements the first bounded AlgebraicJulia slice. `ACSets.jl` 0.2.29 and `Catlab.jl`
0.17.6 are direct dependencies, and one versioned `ProcessBigraphACSet` is the canonical structural
authority. The ordinary Julia `compose` builder produces an immutable `CompositeModel`, which
lowers deterministically through private implementation records to the canonical ACSet. Stable
semantic identities, rather than ACSet row
numbers or declaration order, determine fingerprints and compiled provenance.

Validated authoring models compile into a frozen `StructuralEpoch` and an immutable indexed
`ExecutionPlan`. The serial runtime and checkpoint paths consume that plan and do not traverse the
ACSet or retain the authoring declaration or private `StaticComposite` IR as a second authority.
The Phase 14.PB0 model,
initial-state, final-state, and trace baselines remain exact.

Phase 15.B adds immutable open composition without creating a second runtime authority:

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

Phase 15.C now qualifies the complete immutable-topology serial internal alpha frozen by Decision
0038 and the completed 64-choice owner interview:

- exact fixed and adaptive scheduling with explicit exact/stop-prior horizons;
- changed-input reactive layers and named bounded or convergent iteration;
- four declared multirate interval-input policies;
- typed owner-bound process, step, and observer continuations;
- Philox4x32-10 semantic RNG with immutable lineage addresses and an isolated observer namespace;
- declarative typed observation at event, periodic, or explicit-time boundaries;
- deterministic fail-stop transactions covering all eight registered publication stages; and
- a canonical, integrity-checked v2 logical checkpoint envelope with exact compatible restart.

Qualification passes 440 Phase 15.C assertions, 309 retained historical assertions,
nine Aqua checks, an independent stdlib-only 22-row specification oracle, five mutation targets,
eight failure stages, six authoring routes, eight fixtures, and 33 restart cuts. This implementation
record also includes four checked hot-path/performance guardrails, including bounded allocation and
event-throughput measurements without a fastest-runtime claim. Implementation PR #24 passed
Required CI and its squash-merge tree exactly matches the qualified tree. The metadata-only
closure attestation promotes package version `0.4.0` with `internal_alpha = true`;
`public_release = false` remains in force.

Phase 16 adds `AlgebraicRewriting.jl` for ProcessBigraphs-owned atomic structural transactions,
solver-neutral engine handoff, bounded Merks/CNV assemblies, and a typed high-level authoring
layer. The authoring lifecycle is `CompositeModel` → `LoweredModel` → `ExecutionPlan` → mutable
run session. ProcessBigraphs owns when and why computation occurs; solver and CPM kernels retain
control of how their authorized heavy computation occurs.

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

Phase 17 will add an `AlgebraicDynamics.jl` weak-dependency extension for suitable scientific
authoring. ProcessBigraphs remains the sole authority for time, scheduling, numerical state,
reconciliation, commit, RNG, observation, checkpoints, and replay.

Conformance uses a separate checked Julia specification oracle, source-located derivations, truth
tables, and property, metamorphic, invariance, failure, and restart tests. Production, oracle, and
comparison execute in separate Julia processes; the oracle process is restricted to stdlib roots.
Project tooling does not install or execute Vivarium, Process-Bigraph Python, or Bigraph-Schema
Python.

The current maturity, limitations, and exact parity pins are recorded in
[`parity-registry.toml`](parity-registry.toml). Internal contracts, ordinary open-composition
authoring, and the advanced AlgebraicJulia path are documented in
[`docs/src/internal.md`](docs/src/internal.md). The bounded Phase 15.B closure is recorded by the
repository [audit](../../design/audits/process-bigraph-phase15b-open-composition-audit.md) and
[evidence record](../../design/evidence/process-bigraph-phase15b-evidence-v1.toml). The Phase 15.C
scope and qualified internal-alpha state are checked from the
[entry contract](../../spec/process-bigraph-phase15c-entry-v1.toml) and
[qualification ledger](../../spec/process-bigraph-phase15c-qualification-v1.toml), with closure
provenance in the [evidence manifest](../../design/evidence/process-bigraph-phase15c-evidence-v1.toml).

Run the package suite with Julia 1.12.6:

```sh
julia --project=. -e 'using Pkg; Pkg.test()'
```

This package has no dependency on CorePotts or PottsToolkit. It is licensed
under the repository [MIT license](../../LICENSE).
