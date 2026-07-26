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

The accepted Phase 15 architecture, not yet implemented, adopts `ACSets.jl` and `Catlab.jl`
directly. One custom ProcessBigraph ACSet will become the canonical structure, structured cospans
will define open composition, and directed wiring diagrams will be derived views. Typed Julia and
AlgebraicJulia authoring will lower to the same canonical fingerprint. Structure will compile into
immutable indexed runtime tables so ordinary numerical hot paths do not traverse the ACSet.

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
executable example are in [`docs/src/internal.md`](docs/src/internal.md).

Run the package suite with Julia 1.12.6:

```sh
julia --project=. -e 'using Pkg; Pkg.test()'
```

This package has no dependency on CorePotts or PottsToolkit. It is licensed
under the repository [MIT license](../../LICENSE).
