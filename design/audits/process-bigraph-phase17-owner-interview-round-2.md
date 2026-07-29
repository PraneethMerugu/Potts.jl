# ProcessBigraphs Phase 17 Owner Interview — Round 2

Date: 2026-07-29

Participants: project owner, Codex architecture and documentation auditor

Research baseline: qualified Phase 16 and semantic-preserving consolidation at
`origin/main` commit `04f39dc05f847b7dd84f24f12cce24d1ed0229a6`

Status: accepted, including the post-interview tutorial-transparency amendment

## Scope of this round

Round 2 fixes package and source ownership, the public-versus-extension API
boundary, the smallest supported CorePotts execution façade needed by the
Wortel model, the Merks and Wortel migration shape, semantic-version and
checkpoint treatment, internal-API enforcement, and one-branch baseline
preparation.

It does not authorize implementation. Exact qualification commands, CI jobs,
documentation budgets, visual acceptance, browser-driven review, commit
topology, autonomous stop conditions, and final evidence schema belong to
Round 3.

## Repository research basis

### Current package boundary

Decision 0034 makes ProcessBigraphs the independent domain-neutral runtime,
CorePotts its flagship high-performance spatial adapter, and PottsToolkit the
biological CPM authoring environment. ProcessBigraphs owns orchestration and
publication; CorePotts and injected engines own numerical work. PottsToolkit
may depend on both packages, while ProcessBigraphs cannot depend on either
domain package.

Decision 0040 makes the immutable high-level `CompositeModel` and ordinary
Julia builder the normal scientific authoring route. Raw canonical IR is
forbidden in migrated scientific models, ordinary behavioral tests, examples,
and documentation.

### Merks boundary violations

The qualified Phase 16 Merks assembly in
`lib/CorePotts/src/coupled/merks2006.jl` is high-level at the composition layer
but still depends on qualified implementation details:

- `ProcessBigraphs.ManagedFieldAdvanceProcess`;
- the concrete `BranchSchema.children` field;
- `ScientificPottsIntegrator.mcs`; and
- `ScientificPottsIntegrator.algorithm`.

The public CorePotts `PottsProblem`, SciML `init`, SciML `step!`,
`logical_state`, and checkpoint interfaces already provide the correct
supported execution direction. The model should use those interfaces rather
than promoting integrator representation fields.

### Wortel boundary gap

The current Wortel implementation is a qualification harness rather than a
reusable reference-model product. It directly uses `CorePotts.offsets`,
`CorePotts.init_coupled`, coupled runtime fields, workspace fields, observation
storage, execution-plan metrics, and checkpoint internals.

The existing Level 1 `Act` declaration lowers to the qualified
`ActivityProgram`, but there is no supported public problem/integrator façade
for executing that program. Exporting the whole registry-v1 coupled executor
would freeze an intentionally internal migration structure. A narrow
activity-specific problem façade is the smallest coherent public boundary.

### ProcessBigraphs extension gap

ProcessBigraphs exports the main engine protocol types and transaction methods,
but several methods that adapter packages must extend remain qualified-only.
The managed field process is also a qualified concrete type, despite being
needed by the sibling CorePotts scientific models.

The appropriate Julia boundary is:

- a small exported user API;
- qualified documented `public` extension hooks;
- explicitly experimental/internal-beta bindings; and
- true implementation details.

### External primary-source research

Julia defines public API in terms of exported or `public` bindings and the
documented behavior attached to them. Documented behavior of a private binding
is not public API, while undocumented behavior of a public binding is not a
supported contract. Julia package extensions load when declared trigger
packages are present and extend functions owned by the parent package.

SciML defines `init(problem, ...)`, `step!(integrator)`, and
`solve!(integrator)` as the ordinary problem/integrator pattern. The
Process-Bigraph solver-wrapping tutorial similarly recommends a stable Process
interface, explicit ports, deterministic state mapping, and solver-specific
configuration behind the adapter.

Primary references:

- <https://docs.julialang.org/en/v1/manual/faq/#Public-API>
- <https://docs.julialang.org/en/v1/manual/modules/>
- <https://docs.julialang.org/en/v1/manual/code-loading/#Package-Extensions>
- <https://docs.sciml.ai/SciMLBase/stable/interfaces/Init_Solve/>
- <https://docs.sciml.ai/DiffEqDocs/stable/basics/integrator/>
- <https://vivarium-collective.github.io/process-bigraph/notebooks/tutorial_1.html>
- <https://vivarium-collective.github.io/process-bigraph/notebooks/tutorial_2.html>
- <https://pypi.org/project/process-bigraph/>
- <https://arxiv.org/abs/2512.23754>

## Accepted decisions

| ID | Decision | Rationale | Revisit trigger |
|:--|:--|:--|:--|
| P17-R2-01 | Canonical Wortel and Merks implementations live under `PottsToolkit.ReferenceModels`, separated into model-family source files. CorePotts retains generic mechanisms and adapters; ProcessBigraphs retains no biological model code. | Scientific-paper assemblies belong to the biological façade, not the domain-neutral runtime or numerical kernel package. | A separately versioned scientific-model package is approved. |
| P17-R2-02 | PottsToolkit gains a direct compat-bounded ProcessBigraphs dependency. ProcessBigraphs remains independent of both Potts packages. Only the ProcessBigraphs docs/example environment depends on PottsToolkit. | Julia packages must declare direct dependencies, and Decision 0034 explicitly permits PottsToolkit to depend on both packages. | Repository or package separation changes. |
| P17-R2-03 | Split the monolithic `reference_models.jl` into model-family files while preserving public access through `PottsToolkit.ReferenceModels`. | Source organization becomes maintainable without making file layout part of the user contract. | A dedicated reference-model package supersedes the module. |
| P17-R2-04 | Classify every ProcessBigraphs binding as exported user API, qualified public extension API, experimental/internal-beta API, or implementation detail in a machine-readable registry. | API coverage and compatibility cannot be inferred safely from export statements or docstrings alone. | Julia or repository policy adopts a stronger authoritative mechanism. |
| P17-R2-05 | The complete engine-extension protocol becomes qualified documented public API. Most extension hooks use Julia `public` rather than broad exports. | Adapter authors need supported dispatch points without namespace pollution or exposure of unrelated runtime representation. | A replacement adapter protocol is accepted before implementation freeze. |
| P17-R2-06 | Add exported `managed_field_process(declaration; resource_authorization, subcycles_per_mcs=1)`. Keep the concrete managed field process type internal. | Authors need a stable construction behavior, not a promise about concrete representation. | The concrete type itself becomes necessary for supported dispatch. |
| P17-R2-07 | Scientific models use `schema_at`, `schema_leaves`, typed authoring handles, or explicit stores. Direct access to `BranchSchema.children` is forbidden outside ProcessBigraphs internals. | Schema representation is not the scientific authoring contract. | A future public collection interface supersedes these accessors. |
| P17-R2-08 | Introduce a narrow supported `ActivityPottsProblem` with the ordinary `init`/`step!` lifecycle and public logical-state, activity-value, observation, report, capture, and restore accessors. | Wortel requires a supported execution boundary, while a generic public coupled-registry API would freeze substantially more machinery than the model needs. | A separately researched generic coupled-problem API is accepted. |
| P17-R2-09 | `CoupledIntegrator`, `CoupledState`, `MCSPlan`, `init_coupled`, coupled workspaces, and registry-v1 process records remain implementation details. | They are migration-era execution structures, not the intended biological or runtime authoring surface. | A later API promotion gives each type an explicit compatibility and documentation contract. |
| P17-R2-10 | Extend public relation construction so `static_relation(role, topology; spacing, weights)` is supported. `Act` accepts a supported topology or relation; model code no longer calls `CorePotts.offsets`. | The topology is meaningful author input, while raw topology-offset extraction is a numerical representation detail. | A stronger declarative neighborhood API supersedes this overload. |
| P17-R2-11 | Rebuild Merks in `PottsToolkit.ReferenceModels` using only public ProcessBigraphs authoring, `managed_field_process`, public CorePotts problem/stepping methods, and public state/observation accessors. The reduced documentation and full 500×500 profiles share one model definition. | One canonical model must serve both bounded documentation and full qualification without privileged access. | Source tracing requires a materially distinct declared model. |
| P17-R2-12 | Create a reusable Wortel 2021 family with model, problem, ProcessBigraph composite, and observation-plan constructors backed by `Act` and `ActivityPottsProblem`. | The existing benchmark proves a mechanism and backend slice but is not an ordinary reusable scientific model. | A different source-bounded Wortel scope is accepted. |
| P17-R2-13 | Canonical models, public tests, examples, and documentation must contain zero internal API references. Narrowly allowlisted benchmark-only kernel probes may retain white-box access solely to preserve frozen evidence. | Scientific authoring must prove the supported boundary; low-level qualification may still need isolated implementation probes. | A public diagnostic API eliminates a remaining benchmark exception. |
| P17-R2-14 | The migrated Merks assembly receives semantic version v2. Existing Phase 16 v1 fingerprints remain historical evidence. The new reusable Wortel case starts at semantic version v1 and does not inherit the benchmark harness identity. | Ownership and execution-path changes must not be hidden behind unchanged semantic identities. | A proof demonstrates byte-for-byte semantic identity without compatibility deception. |
| P17-R2-15 | Preserve public `ReferenceModels.merks2006_*` call shapes, retain qualified CorePotts forwarding shims through the next minor line, retain v1 checkpoint readers, prohibit silent v1-as-v2 restoration, and document fingerprint migration. Passing Phase 17 permits ProcessBigraphs 0.6.0, CorePotts 0.2.0, and PottsToolkit 0.2.0 while ProcessBigraphs remains unpublished. | This protects supported callers and historical evidence while applying honest pre-1.0 versioning to meaningful API changes. | Final API inventory proves a narrower non-breaking version action is sufficient and the owner explicitly approves it. |
| P17-R2-16 | Require clean downstream environments, model-source internal-API scanning, public registry/docs agreement, Merks v1-to-v2 differential fixtures, Wortel façade-to-frozen-oracle fixtures, and build/run/observe/checkpoint/restart tests for both models. Device requalification is conditional on changing kernel semantics or device ABI. | Boundary correctness must be executable; unchanged qualified kernels do not require ceremonial hardware reruns. | Kernel semantics, device ABI, or qualified backend claims change. |
| P17-R2-17 | After all interviews and explicit implementation send-off, normally merge `origin/main` into `codex/ProcessBigraphs-Docs`. Preserve the branch's existing CI-trimming commit, the owner's `paper.pdf` deletion, and all interview artifacts. Do not reset, destructively check out, rebase, or create a second implementation branch. | The current branch is one unique commit ahead and 43 commits behind the qualified baseline. A normal merge preserves both histories and user work. | The owner explicitly authorizes a different history operation. |
| P17-R2-18 | Both scientific tutorials display and execute the complete model assembly inline. They may import packages, but may not import a prebuilt model, use a visible or hidden `include` as a substitute, or conceal scientific setup. Reusable packaged implementations remain, and semantic-fingerprint plus bounded-behavior tests prove equivalence between packaged and independently authored tutorial models. | Full visible authoring is both the requested learning experience and an independent proof that downstream users can build the models without privileged access. | The owner explicitly relaxes tutorial transparency. |

## API-shape consequences

Round 3 specifications must preserve these properties even if exact spelling is
refined:

- biology is declared separately from ProcessBigraph orchestration;
- stores, component ports, connections, and schedules remain explicit and
  inspectable;
- mounting, wiring, and scheduling may have transparent convenience sugar but
  cannot become silent autowiring;
- any inline functional step has a stable name, semantic version, declared
  inputs, declared outputs, and canonical identity;
- displayed tutorial code is the code executed by documentation CI;
- complete diagrams and inspection reports lower from the same visible model;
  and
- no tutorial relies on `ReferenceModels.merks2006_*` or
  `ReferenceModels.wortel2021_*` to hide the assembly it is teaching.

## External-design alignment

The accepted direction aligns with the published Process-Bigraph principles:
explicit interfaces, typed hierarchical shared state, independent processes,
visible orchestration, and composable solver adapters. No claim is made that
Eran Agmon or another upstream contributor has reviewed or endorsed the Julia
syntax. External presentation remains governed by Decision 0034 and cannot
create design or release authority.

## Explicit non-decisions

Round 2 does not decide:

- exact inline-step spelling;
- whether transparent `mount!` convenience keywords are admitted;
- exact docs/example file layout;
- documentation runtime and output-size budgets;
- visual baselines and responsive breakpoints;
- accessibility, keyboard, link, search, and browser matrices;
- browser-agent task scripts and evidence capture;
- exact CI workflow/job names;
- performance regression thresholds;
- local versus hosted preview mechanics;
- autonomous failure-repair loops and terminal stop rules;
- commit boundaries, final attestation schema, or pull-request disposition.

These questions remain open for researched Round 3.

## Owner disposition

The project owner accepted P17-R2-01 through P17-R2-17 without amendment on
2026-07-29. The owner then required full visible inline model syntax in both
tutorials; P17-R2-18 records that binding amendment.
