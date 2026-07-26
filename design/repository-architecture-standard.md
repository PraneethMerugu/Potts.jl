# Repository Architecture Standard

Status: Accepted engineering standard

## Purpose

This document defines the target repository, package, source, test, benchmark, documentation, and
reproducibility structure for the paper-release refactor and the concurrent incubation of
`ProcessBigraphs.jl`. Repository structure MUST reinforce the accepted scientific and API
boundaries rather than preserve the current layout.

The structural migration is a clean break. Historical package locations, the `Potts` umbrella
package, generated documentation, and duplicated development environments do not constrain the
target architecture.

## Package Family

The project remains a monorepo through the paper release. Its package family is:

- `PottsToolkit`: the primary user-facing package and conventional repository-root package
- `CorePotts`: the hardware-agnostic scientific execution engine
- `ProcessBigraphs`: an independent, domain-neutral multirate process-bigraph runtime incubated
  under `lib/`
- `MakiePotts`: an optional visualization satellite
- `NeuralPotts`: an experimental satellite

The repository MAY retain the broader `Potts.jl` project-family name, but the ordinary user entry
point is `using PottsToolkit`.

The existing `Potts` umbrella package MUST be removed. It MUST NOT be retained as a re-export layer,
because installing the primary interface must not pull visualization or experimental satellites
into the dependency graph.

The packages remain independently valid Julia packages with their own identity, project metadata,
compatibility bounds, and package-local tests. Repository co-location MUST NOT permit undeclared
cross-package dependencies.

`ProcessBigraphs` has an independent package UUID and internal package identity from its first
implementation slice. Internal alpha and beta labels are development gates, not public releases.
The package MUST remain unpublished until it has passed complete feature and observable-behavior
parity against the pinned Process-Bigraph 2.0 authority and a whole-cell-style composite acceptance
workload. A repository split MAY be considered only after that first complete-parity release; it is
not an incubation requirement.

During the Phase 13 freeze, only PottsToolkit and CorePotts are paper-core workspace packages.
MakiePotts source is intentionally outside that workspace until the Phase 14.4 migration. The
pre-freeze NeuralPotts implementation is absent; the experimental package identity may be restored
only by the Phase 14.4-or-later redesign required by the accepted scope map.

## Dependency Direction

The target dependency direction is:

```text
ProcessBigraphs
      ^
  CorePotts
      ^
 PottsToolkit
      ^
  MakiePotts

CorePotts <- NeuralPotts
```

More specifically:

- `ProcessBigraphs` MUST NOT depend on `CorePotts`, `PottsToolkit`, `MakiePotts`, or `NeuralPotts`.
- `CorePotts` depends on `ProcessBigraphs` after the corresponding strangler-migration slice and
  MUST NOT depend on `PottsToolkit`, `MakiePotts`, or `NeuralPotts`.
- `PottsToolkit` depends on `CorePotts` and MAY depend directly on `ProcessBigraphs` when its
  composition compiler uses runtime contracts. It MUST NOT depend on either satellite.
- `MakiePotts` MAY depend on `PottsToolkit` and `CorePotts`.
- `NeuralPotts` MUST depend on the smallest stable layer it requires.
- A satellite MUST NOT be required to load, test, document, or benchmark the primary interface.

The dependency arrow is introduced one accepted migration slice at a time. During parallel
incubation, G3-C and other Potts work MAY continue against the locked CorePotts ABI while
`ProcessBigraphs` develops in isolated paths. Temporary absence of the target dependency is allowed;
a reverse dependency, shared ownership of generic runtime contracts, or undeclared source inclusion
is not.

`ProcessBigraphs` owns generic paths, ports, state schemas, processes, steps, deltas, clocks,
composites, scheduling, reconciliation, and commits. CorePotts owns Potts laws, spatial storage,
workspaces, kernels, lifecycle operations, and algorithms. PottsToolkit owns biological authoring
façades and lowering. CorePotts is the flagship spatial-process adapter, not the semantic owner of
the general runtime.

KernelAbstractions, AcceleratedKernels, Atomix, KernelIntrinsics, Adapt, and physical device-storage
machinery belong primarily to `CorePotts`. `PottsToolkit` MAY depend directly on a low-level
performance library only when its own compilation responsibility genuinely requires that library.
It MUST NOT reach through `CorePotts` to manipulate engine storage or launch kernels.

StructArrays and StaticArrays MAY be used in either package when they serve that package's actual
responsibility. Their presence MUST NOT erase the boundary between modeling and execution.

## Target Top-Level Layout

The target repository shape is:

```text
Potts.jl/
  Project.toml
  src/
  ext/
  test/

  lib/
    ProcessBigraphs/
    CorePotts/
    MakiePotts/
    NeuralPotts/

  integration/
  benchmark/
  paper/
  docs/
  examples/
  spec/
  design/
  scripts/
  .github/
```

The root `Project.toml`, `src/`, `ext/`, and `test/` belong to `PottsToolkit`. Moving
`PottsToolkit` to the root MUST preserve its package UUID unless a separate release decision
explicitly changes package identity.

`spec/` owns observable scientific and API contracts. `design/` owns implementation and engineering
standards. These directories remain at the repository root because their authority spans the
package family.

`lib/ProcessBigraphs/` owns its package-local source, tests, internal documentation, and development
project. A package-local parity registry pins the normative Process-Bigraph 2.0 authority and binds
each claimed feature to executable evidence. Potts-specific models and adapters MUST NOT be used as
the runtime's only conformance evidence.

## CorePotts Source Organization

`CorePotts` uses scientific and execution responsibilities rather than vague directories such as
`Base` and `Tools`:

```text
lib/CorePotts/src/
  CorePotts.jl
  state/
  topology/
  components/
    energies/
    constraints/
    trackers/
    fields/
  proposals/
  algorithms/
  lifecycle/
  execution/
  kernels/
  sciml/
  initialization/
```

This is an organizational layout, not a requirement to create one Julia module per directory.
Source files SHOULD remain cohesive and moderately sized. The implementation MUST NOT introduce
deep namespace trees, one-type-per-file conventions, or abstract-type hierarchies merely to mirror
the filesystem.

Scientific components define meaning. Execution plans determine how that meaning runs. Kernels
implement bounded device operations. GPU-sensitive engine machinery has an explicit home:

```text
execution/
  plans.jl
  workspaces.jl
  launch.jl
  synchronization.jl
  transactions.jl
  randomness.jl

kernels/
  proposals.jl
  acceptance.jl
  state_updates.jl
  reductions.jl
  trackers.jl
  lifecycle.jl
```

The final file partition MAY differ when measured implementation needs justify it, but the
scientific/execution/kernel responsibilities MUST remain explicit.

## PottsToolkit Source Organization

The root package is organized around scientific modeling concepts and its compilation pipeline:

```text
src/
  PottsToolkit.jl
  models.jl
  domains.jl
  cells.jl
  media.jl
  properties.jl
  components.jl
  problems.jl
  rules/
    syntax.jl
    validation.jl
    representation.jl
    lowering.jl
  composition/
    fragments.jl
    overrides.jl
    provenance.jl
  reports/
```

The exact file partition MAY evolve with the implementation, but the Level 2 typed modeling API
MUST remain directly usable and MUST NOT be hidden inside DSL internals. The Level 1 DSL parses into
a typed representation, validates it, and lowers through the same modeling interfaces into stable
`CorePotts` protocols.

## Extensions and Backends

CUDA, AMDGPU, Metal, HDF5, Zarr, and other optional integrations use Julia package extensions and
weak dependencies. Backend-neutral source MUST NOT accumulate scattered package-name conditionals.

A substantial extension MAY use a loader and supporting directory:

```text
ext/
  CorePottsCUDAExt.jl
  CorePottsCUDAExt/
    adaptation.jl
    launch.jl
    diagnostics.jl
```

Loading an extension MUST NOT silently change accepted scientific semantics. Capability differences
and unsupported behavior follow the accepted backend capability and failure contracts.

## Environments and Julia Compatibility

Until compatibility CI is introduced at the final release-qualification stage, the refactor and
paper baseline target Julia 1.12.6 exclusively. Development, benchmarks, tests, and generated
manifests MUST use Julia 1.12.6 so compatibility work cannot constrain or confound the engine and
API redesign. Supporting older Julia versions is a later explicit release decision, validated by
dedicated CI lanes rather than assumed from package compatibility declarations.

Documentation, integration tests, benchmarks, and paper reproduction each have explicit Julia
projects. A small checked-in Julia setup script MAY develop the local packages into those
environments. The repository MAY adopt Pkg workspaces when their use materially simplifies
maintenance under the active Julia 1.12.6 development target.

Manifest policy is:

- Independently installable libraries, including `PottsToolkit` and `CorePotts`, MUST NOT commit a
  package-local manifest as their compatibility contract.
- Reproducible applications, especially `paper/`, SHOULD commit a complete manifest.
- `benchmark/` and `docs/` MAY commit manifests when exact environment reproduction is valuable.
- Every direct dependency of a released package MUST have an appropriate compatibility bound.

## Tests and Conformance

Tests are separated by responsibility:

```text
test/                         # PottsToolkit package tests
lib/ProcessBigraphs/test/     # ProcessBigraphs package and serial-oracle tests
lib/CorePotts/test/           # CorePotts package tests
lib/MakiePotts/test/          # MakiePotts package tests
lib/NeuralPotts/test/         # NeuralPotts package tests

integration/
  Project.toml
  runtests.jl
  reference/
  conformance/
  statistical/
  backends/
```

Package-local tests verify that package independently. `integration/` verifies cross-package
semantics, DSL-to-engine equivalence, SciML behavior, reference models, statistical correctness,
and backend conformance.

`ProcessBigraphs` CI owns its package-local unit, property, scheduler, persistence, and pinned-parity
conformance lanes. Cross-package CI owns CorePotts adapter equivalence, PottsToolkit lowering, and
whole-cell-style composite acceptance. A Potts CI lane MUST NOT be treated as evidence that the
domain-neutral runtime passes independently, and runtime CI MUST NOT silently alter the accepted
Phase 13 or Potts backend gates.

Backend launchers SHOULD use separate processes or CI jobs while invoking the same shared
conformance definitions. Scientific fixtures and canonical workload builders MUST NOT be copied
between backend-specific test files.

Specifications SHOULD link to their conformance tests. The repository SHOULD maintain an index
mapping each accepted specification to its implementing subsystem and validation evidence.

## Benchmarks

Performance measurement is a first-class project:

```text
benchmark/
  Project.toml
  performance_worker.jl
  workloads/
  micro/
  kernels/
  mcs/
  end_to_end/
  backends/
  external/
  reporting/
```

Canonical workload definitions SHOULD be reusable by correctness tests, benchmarks, and paper
experiments without duplicating model construction. Reuse MUST NOT couple performance timing to a
test harness or add assertions inside timed regions.

Benchmark results, profiler captures, device-code reports, and compiled reports are generated
outputs. They MUST NOT accumulate in ordinary package source. Release evidence is retained through
CI artifacts, Julia artifacts, or an archival release mechanism as defined by the benchmark and
paper-release standard.

## Paper Reproduction

The Potts.jl methods/performance paper reproduction is an application environment:

```text
paper/
  Project.toml
  Manifest.toml
  configurations/
  experiments/
  analysis/
  figures/
```

Experiment configurations, analysis programs, environment pins, checksums, and provenance belong
in the repository. Large raw results belong in content-addressed artifacts or archived releases.
Generated figures MAY be committed only when publication tooling requires them and their generating
program and provenance are also retained.

Published biological model reproductions are documentation products with reusable executable model
sources and independent evidence. They do not share an ambiguous `paper/` label with the
Potts.jl publication environment:

```text
docs/
  models/
    tutorials/
    examples/
    published/
      <model-id>/
        model.jl
        reproduction.toml
        validate.jl
  evidence/
    published/
      <model-id>/
        README.md
        Artifacts.toml
```

Paper-specific assembly, parameter tables, staged schedules, and analyses MAY live with a published
model. A reusable proposal, scientific component, state transition, field evolution law, lifecycle
operation, relationship update, or backend implementation MUST live in CorePotts or PottsToolkit
with package-owned tests.

Large source datasets, raw ensembles, animations, and evidence bundles use content-addressed
artifacts or archived releases. The checked-in evidence binding records immutable identities and
retrieval instructions; it is not a second generated-results tree.

## Documentation and Tutorials

Documentation contains source and its reproducible build environment:

```text
docs/
  Project.toml
  Manifest.toml
  make.jl
  src/
    learn/
    examples/
    published-models/
    concepts/
    api/
  models/
    tutorials/
    examples/
    published/
  evidence/
```

`docs/build/` is generated and MUST be ignored. Small intentional documentation assets MAY remain in
`docs/src/assets/`. Generated videos, Zarr stores, HDF5 stores, and other large tutorial products
belong in artifacts or release assets.

During incubation, `ProcessBigraphs` maintains package-local internal documentation for its public
contracts, parity decisions, executor semantics, and extension examples. The root documentation MAY
surface runtime-backed Potts workflows, but it MUST NOT imply a public runtime release or complete
parity before the release gates pass. Every runtime implementation phase updates its owned
documentation and CI evidence in the same phase.

The Documenter navigation is Learn, Examples, Published Models, Concepts and Guarantees, and API.
Learn progresses through Beginner, Model Builder, Research Workflows, and Advanced Extensions.

Each tutorial, example, and published model SHOULD have one canonical executable Julia source.
Pages explain and include those sources rather than becoming the only executable implementation.
Numerical assertions run in ordinary CI independently of expensive animation and publication
rendering. Published-model sources additionally provide the manifest, registered validation, and
evidence links required by the
[published-model reproduction contract](../spec/published-model-reproduction-semantics.md).

Tutorials are manually rebuilt after the Phase 13 API freeze. Missing scientific mechanisms exposed
by the selected published-model corpus follow the Phase 14.0 and 14.1 specification and conformance
gates before the corresponding documentation is presented as supported.

## Examples

Examples are focused user programs:

```text
examples/
  README.md
  basic/
  advanced/
  dashboards/
  notebooks/
```

Examples SHOULD share an environment where practical. A dashboard or notebook receives a separate
project only when it genuinely requires a distinct application stack. Scientific implementation
logic MUST live in the packages, not be stranded in an example.

`examples/` remains a convenient collection of focused standalone programs. Its supported programs
MUST also be linked from the Documenter Examples section so the public learning path remains inside
the documentation site. A literature-inspired simplification is labeled Inspired Example and is
not duplicated into Published Models.

## Scripts and Generated Files

`scripts/` contains thin repository operations such as environment setup, formatting, conformance
launch, benchmark launch, and artifact retrieval. Scripts call package functionality. Scientific
logic and canonical benchmark workloads MUST NOT accumulate in scripts.

Repository ignore rules MUST cover at least:

- `docs/build/`
- Benchmark results and compiled reports
- Profiler traces and device-code inspection output
- Coverage output
- Generated animations
- Generated Zarr and HDF5 stores
- Other temporary experiment products

Small permanent test fixtures MAY remain in the repository. Large fixtures and reference datasets
SHOULD use Julia's content-addressed artifact system.

## Structural Migration Gate

Repository restructuring precedes the main subsystem refactor. It MUST be performed as a controlled
structural phase that:

1. Establishes the final package locations and dependency direction.
2. Preserves package UUIDs and verifies independent package loading.
3. Establishes package-local tests plus the integration and benchmark projects.
4. Removes the `Potts` umbrella package and duplicated test ownership.
5. Removes tracked generated products and applies the accepted manifest policy.
6. Updates CI to address packages, conformance suites, and backends explicitly.
7. Verifies that CPU and at least one available GPU smoke workload still execute.

Moving files alone MUST NOT be mixed with broad scientific redesign. After the structural phase is
green, subsystem refactoring follows the phase order in the refactor and paper-release standard.
