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
authority. The ordinary `StaticComposite` API is an ergonomic façade that lowers to the same
canonical model as direct ACSet authoring. Stable semantic identities, rather than ACSet row
numbers or declaration order, determine fingerprints and compiled provenance.

Validated authoring models compile into a frozen `StructuralEpoch` and an immutable indexed
`ExecutionPlan`. The serial runtime and checkpoint paths consume that plan and do not traverse the
ACSet or retain the `StaticComposite` declaration as a second authority. The Phase 14.PB0 model,
initial-state, final-state, and trace baselines remain exact.

Phase 15.A is not the complete Phase 15 internal alpha. Structured-cospan composition, derived
wiring diagrams, nested open composites, the independent Julia specification oracle, semantic RNG,
and the broader multirate/failure fixture matrix remain open Phase 15 work.

Phase 16 will add `AlgebraicRewriting.jl` for ProcessBigraphs-owned atomic structural transactions.
Phase 17 will add an `AlgebraicDynamics.jl` weak-dependency extension for suitable scientific
authoring. ProcessBigraphs remains the sole authority for time, scheduling, numerical state,
reconciliation, commit, RNG, observation, checkpoints, and replay.

Conformance will use a separate checked Julia specification oracle, source-located derivations,
truth tables, and property, metamorphic, invariance, failure, and restart tests. Project tooling
will not install or execute Vivarium, Process-Bigraph Python, or Bigraph-Schema Python; claims will
be source-audited feature and semantic parity rather than live upstream-runtime equivalence.

The current maturity, limitations, and exact parity pins are recorded in
[`parity-registry.toml`](parity-registry.toml). Internal contracts and an
executable example are in [`docs/src/internal.md`](docs/src/internal.md). The bounded closure is
recorded by the repository
[Phase 15.A audit](../../design/audits/process-bigraph-phase15a-canonical-structure-audit.md) and
[evidence record](../../design/evidence/process-bigraph-phase15a-evidence-v1.toml).

Run the package suite with Julia 1.12.6:

```sh
julia --project=. -e 'using Pkg; Pkg.test()'
```

This package has no dependency on CorePotts or PottsToolkit. It is licensed
under the repository [MIT license](../../LICENSE).
