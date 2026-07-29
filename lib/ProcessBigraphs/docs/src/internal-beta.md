# Internal-beta guide

Status: unpublished internal-beta consolidation candidate; package version `0.5.1`

The metadata-only attestation admits the previously qualified exact-head implementation without
changing runtime or scientific-model behavior.

## What this beta is

ProcessBigraphs 0.5 is a qualified, unpublished internal beta for composing dynamic scientific processes around
optimized domain engines. ProcessBigraphs owns logical time, invocation reason, visibility,
identity, reconciliation, validation, publication, failure, checkpoint, and replay. A selected
solver or CPM kernel owns timesteps, sweeps, device kernels, arrays, caches, workspaces, streams,
and other heavy-computation details inside an authorized invocation.

The ordinary authoring path is:

```text
compose do-block
    → immutable CompositeModel
    → deterministic LoweredModel plus author-origin map
    → immutable ExecutionPlan
    → mutable run session with private engine instances
```

Authors use typed handles and ordinary Julia calls. A macro is not required, and scientific models
do not construct `StaticComposite`, `ProcessDeclaration`, `StepDeclaration`, or `PortBinding`
directly.

## Qualified scope

- Solver-neutral interval, boundary-solve, discrete-batch, and typed-extension operations.
- Exact field scheduling and named splitting controlled by ProcessBigraphs.
- Cartesian 2D/3D native fields on CPU, real Metal, and real ROCm hardware.
- CPU SciML integration with an explicitly injected real algorithm.
- An independent CPU custom adapter proving the protocol is not SciML-specific.
- Atomic add, remove, divide, move, and rewire structural transactions.
- A CorePotts adapter and canonical coupled logical checkpoints.
- Source-bounded runnable Merks 2006 and CNV scenario-38/simulation-902 assemblies.
- Immutable semantic authoring, deterministic lowering, complete author-origin maps, typed
  problems and interventions, semantic archives with caller-owned codecs, and layered identity.

The generated [capability matrix](capabilities.md) is derived from the normative
registries and is checked for drift in CI.

## How to author and run

Create a reusable semantic model with `compose`, declare stores with `store!`, mount component laws
with `mount!`, connect explicit endpoints with `connect!` or exact-name `attach!`, and declare
orchestration with `schedule!`. Use `Every`, `At`, `On(store)`, and `After` to say when and why an
invocation occurs. These declarations do not prescribe numerical substeps.

Bind run-specific initial state, parameters, observables, interventions, time span, and seed in a
`SimulationProblem`. `compile(problem)` validates and freezes the selected run. Use `describe`,
`diagram`, `explain`, and the layered fingerprint functions before execution when inspecting
provenance.

## Stability promise

Semantic identity, exact scheduling, publication, checkpoint, and evidence contracts are stable
for the internal beta. Constructor spelling remains pre-1.0 and may improve. Concrete engine
instances, completion handles, candidates, integrators, caches, and raw rewrite rules are not
public API.

## Important limits

This is not a public release or complete Process-Bigraph parity. It does not qualify Dagger,
distributed or multi-GPU execution, CUDA, universal third-party-solver GPU support, implicit
co-simulation, FEM, AMR, moving meshes, arbitrary mid-event restart, graphical authoring,
arbitrary closure serialization, AlgebraicDynamics, broad biochemical/FBA/SBML adapters, or a
whole-cell composite. The Merks and CNV deliverables are bounded runnable implementations, not
their complete publication analyses or ensembles.

See the [adapter and solver guide](adapters-and-solvers.md) and
[failure and persistence guide](failure-and-persistence.md) before adding a new engine.
