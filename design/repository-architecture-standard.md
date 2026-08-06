# Repository architecture standard

Status: current

Date: 2026-08-05

## Goal

Repository structure must keep symbolic authoring, numerical execution, and visualization separate
without making normal Potts use depend on an orchestration framework. The governing retirement and
boundary decisions are [Decision 0043](../spec/decisions/0043-retire-processbigraphs.md) and
[Decision 0044](../spec/decisions/0044-pre-g6-cohesion-and-mtk-hardening.md); the current phase
boundary is the [G5H Hardening Contract](../spec/symbolic-potts-v1-hardening.md).

## Package graph

```text
ModelingToolkit ──optional extension──> PottsToolkit ──> CorePotts
Unitful ──────────optional extension──>      │
MakiePotts (user-selected visualization) ────┘

Accelerator packages ──optional extensions/protocols──> CorePotts and MakiePotts
```

Equivalently, the package dependency direction is
`MakiePotts -> PottsToolkit -> CorePotts`; MakiePotts never bypasses PottsToolkit to depend on
CorePotts directly.

The arrows denote allowed dependency or extension directions, not ownership of scientific
semantics.

## Responsibilities

### PottsToolkit

PottsToolkit owns:

- symbolic Potts statements and systems;
- biological authoring and composition;
- completion, validation, diagnostics, and semantic fingerprints;
- structural MTK compilation and native-component coupling schedules;
- problem construction, late private lowering, public inspection, and the public SciML problem,
  integrator, solution, saving, checkpoint-envelope, SII, and ensemble lifecycle; and
- optional ModelingToolkit and units integration.

PottsToolkit may depend on CorePotts. It must not reach into private CorePotts storage or dispatch on
private backend types.

### CorePotts

CorePotts owns:

- runtime state and storage;
- transition algorithms and backend-independent execution semantics;
- CPU and accelerator kernel protocols;
- settled runtime snapshots and statistics, logical checkpoint payloads, and restore mechanics;
- deterministic random streams and replica/repeat identity primitives; and
- runtime capability and compatibility reporting.

CorePotts must remain independently loadable. It must not depend on PottsToolkit,
ModelingToolkitBase, ModelingToolkit, Symbolics, Unitful, Makie, or an orchestration framework.

### MakiePotts

MakiePotts consumes public state, snapshot, solution, and metadata interfaces. It owns rendering,
plots, legends, interactive controls, and export. It must not define solver behavior or mutate
private runtime state.

## Integration boundaries

Optional ecosystems integrate through Julia package extensions. The parent package owns a small,
documented generic hook only when that hook expresses a stable Potts concept. An extension must not
introduce a second model authority, lifecycle engine, scheduler, checkpoint format, or parameter
store.

An external ModelingToolkit system remains a native component island through structural
compilation. An extension may define its explicit scope, IO map, cadence, time map, solver policy,
and capability checks, but must not copy the system's equations and metadata into a parallel Potts
representation.

A new adapter proposal must specify:

- which package owns the hook;
- the exact public input and output types;
- time, state, error, cancellation, and ownership semantics;
- optional-dependency and load-order behavior;
- checkpoint and provenance implications; and
- focused tests proving the base packages work without the dependency.

## Compiler and runtime flow

```text
authoring statements
        │
        v
completed Potts system
        │ structural mtkcompile + native component scheduling
        v
scheduled Potts system + symbolic schemas
        │ PottsProblem + init/solve specialization
        │
        v
private executable lowering + selected algorithm/backend
        │
        v
integrator / solution / observations / checkpoints
```

Only the completed and structurally scheduled system is symbolic authority. Lowered executables
are private caches; they may store normalized data but must retain fingerprints and provenance
sufficient to detect mismatched systems, parameters, and checkpoints.

## Repository layout

```text
src/                         PottsToolkit source
ext/                         optional PottsToolkit integrations
test/                        PottsToolkit unit and compiler tests
lib/CorePotts/               independent numerical package
lib/MakiePotts/              independent visualization package
integration/                 cross-package and optional-extension tests
docs/                        public documentation
spec/                        normative semantics and decisions
design/audits/               historical research and review evidence
benchmark/                   reproducible performance environments
examples/                    executable user workflows
```

Code shared between packages must live in the lowest package that genuinely owns its semantics.
Copying an abstraction into multiple packages is not an integration mechanism.

## Dependency rules

- Every direct import must be declared in the importing package's `Project.toml`.
- Local path dependencies in committed manifests must point to a current package and describe its
  current direct dependencies.
- Optional packages belong in weak dependencies and extensions, not unconditional imports.
- Test-only packages belong in test projects or extras.
- No package may discover a sibling by walking the filesystem at runtime.
- Examples, documentation, benchmarks, and integration tests must have their own resolvable
  environments.

## Test ownership

- PottsToolkit tests authoring, completion, validation, compilation, problem construction, and
  inspection.
- CorePotts tests numerical semantics, runtime protocols, backends, reproducibility, logical
  checkpoints, and replica/repeat primitives independently.
- PottsToolkit tests the public SciML solution, SII, remake, saving, checkpoint-envelope, and
  ensemble lifecycle.
- MakiePotts tests public-data adaptation and rendering independently.
- `integration/` tests only genuine cross-package or optional-extension behavior.
- Documentation tests stable user workflows; it must not substitute for package tests.

Hardware-specific tests must report the exact backend and whether they ran, were unsupported, or
were skipped for a documented reason.

## Change control

Changes that move ownership across packages, add a required dependency, expose a new generic hook,
or introduce a second representation of model/runtime state require a decision record before
implementation. Ordinary internal refactors do not, provided public semantics and package
boundaries remain unchanged.

Historical audits are evidence, not current authority. When they conflict with this standard or an
accepted decision, the current standard and decision win.
