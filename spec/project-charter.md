# Project Charter

Status: Accepted

## Mission

This repository develops two coordinated scientific products:

1. Potts.jl, a scientific simulation ecosystem for Cellular Potts Models
2. `ProcessBigraphs.jl`, an independently identified, Julia-native multirate process-bigraph
   runtime incubated under `lib/`

Potts.jl is intended to combine three equal identities:

1. A scientifically trustworthy modeling library
2. A world-leading high-performance simulation engine
3. An approachable biological modeling environment

`ProcessBigraphs.jl` is intended to reproduce the features and observable behavior of a pinned
Process-Bigraph 2.0 authority through idiomatic Julia contracts. Its long-term purpose is to support
whole-cell and multiscale model development, not merely to provide schema interchange with another
runtime. Vivarium 1.x compatibility is outside this parity goal unless a later accepted decision
adds a specific capability on its own merits.

The Potts ecosystem MUST remain architecturally hardware agnostic. Until superseded by an accepted
semantic decision, its first-class release contract is CPU, Apple Metal, and AMD ROCm. NVIDIA CUDA
remains a deferred integration: its code MAY remain available for development, but it MUST NOT be
included in Potts support, correctness, performance, or release claims. Stable Potts scientific
features MUST support both two- and three-dimensional models unless explicitly documented
otherwise.

## Primary User Experience

PottsToolkit is the primary public modeling interface. It SHOULD allow computational biologists,
statistical physicists, HPC researchers, and Julia developers to express models without depending
on CorePotts internals.

PottsToolkit acts as a high-level declarative language and model compiler for CorePotts. It MUST
provide an ergonomic path for ordinary users without preventing advanced users from extending or
using CorePotts directly.

## Core Engine

CorePotts defines the scientific execution contracts, fundamental state model, reference engine,
optimized engines, and extension interfaces. It MUST remain usable independently of visualization
and experimental neural-model packages.

Optimized execution MUST be judged against explicit scientific contracts. Performance improvements
MUST NOT silently redefine model behavior.

## Process-Bigraph Runtime

`ProcessBigraphs.jl` owns domain-neutral paths, ports, state schemas, process and step protocols,
typed deltas, logical clocks, composites, scheduling, reconciliation, and commit semantics. It MUST
NOT depend on CorePotts, PottsToolkit, or another Potts-specific package.

CorePotts is the flagship spatial-process adapter for the runtime. PottsToolkit retains its
biological authoring façades and MAY lower generic composition into `ProcessBigraphs.jl`. Generic
runtime semantics MUST NOT be duplicated or defined in parallel by the Potts packages after the
corresponding migration slice is accepted.

The deterministic serial executor is the executable semantic authority. Dagger and other parallel
executors MAY determine physical placement and concurrent execution of already selected work, but
MUST NOT define scientific ordering, logical time, visibility, reconciliation, or commit behavior.

The runtime is GPU-native at its execution boundaries, while each process family declares and
qualifies its own backend capabilities. Whole-cell composites MAY contain explicit CPU-only
processes. Cross-residency movement MUST be declared, bounded, measured, and visible during
preflight; hidden movement is a contract violation. These runtime rules do not weaken the Potts
CPU, Metal, and ROCm release contract.

Runtime development proceeds independently, including independent research and resolution of
upstream ambiguities. Behavioral parity MUST be established against an explicitly pinned
Process-Bigraph 2.0 revision through a versioned parity registry and executable conformance
evidence. Interchange formats and Python bridges MAY be added, but they are not the product center
or a substitute for feature and behavioral parity.

## SciML Integration

Potts.jl targets genuine SciML semantic integration rather than a merely SciML-shaped API. The
eventual stable interface is expected to support the applicable `solve`, `init`, `step!`, callback,
ensemble, saving, remake, termination, return-code, and solution conventions.

The exact supported SciML contract remains under investigation and MUST be established using the
current SciMLBase interfaces.

## Algorithms and Scientific Guarantees

Potts.jl MAY provide both reference and approximate algorithms. They MUST be separately identified
and MUST report their equilibrium, kinetic, attempt-normalization, reproducibility, topology, and
backend guarantees.

The unqualified word "exact" MUST NOT be used as a technical guarantee. Documentation MUST instead
state whether an algorithm provides reference CPM kinetics, a proven invariant equilibrium
distribution, a reference-equivalent implementation, a statistically calibrated approximation, or
experimental behavior.

All user-visible algorithms MUST use comparable normalized Monte Carlo step units.

## Performance and Hardware Portability

The project aims to be the fastest Cellular Potts implementation while remaining scientifically
auditable and approachable. Performance claims MUST be supported by reproducible benchmarks.

Hardware portability means more than successful compilation. Each supported backend MUST be covered
by a capability policy, conformance tests, numerical expectations, and performance measurements.

Backend-specific code MAY optimize a shared semantic operation. Backend-specific behavior MUST NOT
become the implicit definition of that operation.

## Package Stability

The package boundaries are open to revision. PottsToolkit is the stable public destination;
CorePotts is the stable engine and extension destination. MakiePotts should consume stable
observation interfaces. NeuralPotts is an experimental satellite until the classical simulation
foundation and differentiation contracts mature.

`ProcessBigraphs.jl` begins as an independent internal package under `lib/`, with its own UUID,
project metadata, source, tests, documentation, and compatibility declarations. Internal alpha and
beta milestones MAY be used for planning, but the package MUST NOT be publicly released before it
passes complete parity against the pinned Process-Bigraph 2.0 authority and a whole-cell-style
composite acceptance workload. Repository co-location MUST NOT weaken its domain-neutral dependency
boundary.

Auxiliary constraint and fluctuating mechanical-state components are a defining project capability.
They MUST participate through the same extensible component, algorithm-capability, backend,
randomness, checkpoint, and lifecycle interfaces as other scientific families. Historical
`HST...Penalty` names and detailed-balance claims are not normative: the Hubbard-Stratonovich name
MUST be used only when a valid transformation has been derived. Equilibrium auxiliary constraints
and nonequilibrium fluctuating-pressure or fluctuating-tension mechanics MUST be separately named.

## Compatibility and Release Goal

The immediate Potts target is a paper-quality research release. There are no external API
compatibility requirements for the current Potts redesign. Breaking changes are permitted when they
materially improve scientific correctness, API coherence, GPU execution, extensibility, or
maintainability.

The runtime has a separate compatibility obligation: feature and observable behavioral parity with
its pinned Process-Bigraph 2.0 authority. Julia API spelling and implementation structure need not
copy upstream, but deliberate semantic differences MUST be versioned, justified, and covered by
conformance evidence. The runtime and Potts workstreams MAY advance concurrently; neither workstream
may silently relax the other's accepted gates.

Metaprogramming is an implementation tool, not a goal. It MUST be evaluated by generated-code
quality, compilation latency, clarity, extensibility, and GPU suitability.

## Quality Principles

- Scientific semantics precede optimization.
- The sequential reference engine is the executable scientific baseline.
- Public APIs require documentation, validation, and extension examples.
- Every runtime phase owns its package documentation, conformance evidence, and CI coverage rather
  than deferring them to a final cleanup phase.
- State mutations require explicit ownership and invariants.
- Semantic duplication is eliminated.
- Intentional hardware specialization is documented rather than hidden behind unsuitable
  abstractions.
- Tests validate laws and observable behavior rather than incidental struct layouts.
- Current behavior, intended behavior, and compatibility behavior are documented separately.
