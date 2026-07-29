# Decision 0042: ProcessBigraphs Model and Documentation Productization

Status: Accepted architecture; specification in progress, implementation not authorized

Date: 2026-07-29

## Context

ProcessBigraphs 0.5.1 is a qualified unpublished internal beta. Phase 16 and the
semantic-preserving consolidation established a solver-neutral runtime, ordinary
Julia high-level authoring, dynamic structural transactions, exact logical
checkpoints, and bounded scientific assemblies. They did not turn the package
into a documented product.

The package-local documentation is five prose pages without an independent
Documenter environment, strict build, progressive learning path, API inventory,
visual portfolio, clean-install matrix, or rendered-site quality gate. The
qualified Merks implementation still lives in CorePotts and uses qualified
implementation details. Wortel remains a qualification harness rather than a
reusable reference model. Neither model is suitable as a public authoring example.

The project owner requires one autonomous phase that:

1. closes only the public and extension boundaries needed by the two models;
2. gives Wortel and Merks readable, explicit, supported Julia syntax;
3. migrates both models to downstream PottsToolkit ownership;
4. creates an independent ProcessBigraphs manual at least as strong as the
   existing Potts manual;
5. presents both complete model assemblies inline as qualified source-bounded
   case studies; and
6. ends with deterministic rendered-site checks and a terminal browser-agent
   quality gate.

Three researched owner-interview rounds resolve the product, API, compatibility,
documentation, browser, evidence, authority, and autonomous-stop decisions.

## Decision

### One bounded Phase 17

Create **Phase 17: ProcessBigraphs Model and Documentation Productization** with
ordered subgates:

- 17.A — contract freeze;
- 17.B — public boundary closure;
- 17.C — model migration;
- 17.D — independent manual;
- 17.E — scientific case studies; and
- 17.F — reconciliation and attestation.

The subgates are one product phase on one branch. Implementation begins only
after the owner accepts the complete specification packet and gives an explicit
send-off.

### Maturity and package ownership

ProcessBigraphs remains a qualified unpublished internal beta. Documentation
publication is not package release, parity, whole-cell qualification, or a 1.x
stability claim.

ProcessBigraphs owns domain-neutral orchestration, composition, publication,
failure, observation, replay, and extension contracts. CorePotts owns generic
CPM mechanisms and numerical adapters. PottsToolkit owns the canonical Wortel
and Merks scientific model families under `PottsToolkit.ReferenceModels`.

PottsToolkit directly and compat-boundedly depends on ProcessBigraphs.
ProcessBigraphs does not depend on either Potts package. Its docs environment may
depend on PottsToolkit for scientific case studies.

### Supported authoring boundary

Canonical documentation uses ordinary Julia:

```julia
model = compose(:ModelName) do system
    # explicit stores, mounts, attachments, connections, schedules,
    # observables, and parameters
end
```

Stores, mounts, attachments, connections, schedules, and observables remain
distinct and inspectable. Silent autowiring and an opaque all-in-one
mount/wire/schedule operation are forbidden in canonical tutorials.

Custom behavior is named, typed, versioned, and port-declared. Anonymous
closures cannot be semantic or checkpoint authority. Optional convenience
syntax must lower transparently and remain completely visible through
`describe`, `diagram`, and `explain`.

The complete engine extension protocol is qualified public API. Extension
methods should normally be `public` but unexported. User constructors remain
exported when unqualified use materially improves ordinary authoring.

### Narrow API additions

ProcessBigraphs adds exported:

- `managed_field_process(...)`; and
- the smallest schema, authoring, inspection, and problem operations required by
  the accepted tutorials.

CorePotts adds:

- exported `ActivityPottsProblem`;
- the ordinary SciML `init` and `step!` lifecycle for that problem; and
- supported logical-state, activity-value, observation, report, capture, and
  restore accessors.

`CoupledIntegrator`, `CoupledState`, `MCSPlan`, `init_coupled`, concrete
workspaces, and execution-plan representation fields remain internal.

Public topology construction accepts
`static_relation(role, topology; spacing, weights)`, and `Act` accepts a
supported topology or relation. Canonical model code does not extract private
offset tables.

### Model migration and compatibility

Split PottsToolkit reference models into model-family source files. Rebuild
Merks downstream through public ProcessBigraphs authoring, the supported managed
field constructor, public CorePotts stepping, and supported state/observation
accessors. The reduced documentation and canonical 500×500 profiles share one
model definition.

Create a reusable Wortel 2021 model family with model, problem,
ProcessBigraphs-composite, observation-plan, and profile constructors backed by
`Act` and `ActivityPottsProblem`.

Merks becomes semantic model version v2. Its Phase 16 v1 identity remains
historical evidence. Wortel starts at semantic model version v1 and does not
inherit the qualification-harness identity.

Preserve supported `ReferenceModels.merks2006_*` call shapes and CorePotts
forwarding shims through the next minor line. Retain v1 checkpoint readers.
Never silently restore v1 as v2. Document every fingerprint and persistence
migration.

Passing Phase 17 permits ProcessBigraphs 0.6.0, CorePotts 0.2.0, and
PottsToolkit 0.2.0 while ProcessBigraphs remains unpublished.

### Independent documentation product

Build a package-local strict Documenter site deployed from the monorepo with
`dirname = "ProcessBigraphs"` and a package-specific tag prefix. It has six
top-level sections:

- Home;
- Learn;
- Examples;
- Scientific Case Studies;
- Concepts and Guarantees; and
- API.

The curated inventory contains at least 35 pages. Required tutorials and case
studies show and execute complete source. Reader-facing `include(...)`, hidden
scientific setup, and prebuilt reference-model substitutions are forbidden.

Wortel and Merks are labeled **Qualified Source-Bounded Case Study**. The pages
state their source trace, configuration, admitted result, and nonclaims.
Neither page claims quantitative publication reproduction.

The ProcessBigraphs documentation quality score must be at least 92/100 with no
category below 8/10. Root Potts documentation must not regress.

### Rendered-site and accessibility quality

Strict Documenter, page/API/media registries, program visibility, behavioral
tests, platform smokes, and link checks are necessary but insufficient.

The documentation also receives:

- pinned Playwright Chromium, Firefox, and WebKit journeys;
- accessibility-tree assertions;
- axe WCAG 2.2 A/AA checks without disabled rules or broad exclusions;
- Lighthouse thresholds;
- pinned Linux/Chromium visual regression;
- desktop, tablet, and mobile responsive checks;
- light and dark theme checks; and
- a terminal task-based browser-agent review.

Automated accessibility results are not represented as a complete human WCAG
audit. Browser-agent task reviews are auditor led, not external user studies.

### Exact-content browser closure

The browser-agent review is the final functional gate. It runs only after all
deterministic package, documentation, platform, accessibility, performance, and
visual checks pass.

Any browser finding reopens implementation. The complete browser-agent gate
reruns after repair. Waivers are forbidden.

Evidence binds to a declared qualifying content-tree digest. Runtime, model,
test, documentation, browser-test, dependency, or configuration changes
invalidate it. Evidence-only attestation metadata is outside the qualifying
path set, preventing a self-referential evidence-commit loop.

### Autonomous authority and stop conditions

After explicit send-off, the agent may normally merge `origin/main` into the
existing `codex/ProcessBigraphs-Docs` branch, commit intentionally, push only
that branch, open or update one draft pull request, and drive required workflows
to green.

The agent may not merge to `main`, publish a registry release, weaken branch
protection, or broaden scientific claims.

The autonomous run stops only for missing authority or credentials, sustained
external-service failure, newly required unavailable hardware, destructive
ambiguity involving user work, or a specification contradiction requiring a
scope or scientific-claim decision. Test failures, documentation defects,
budget misses, and browser findings are work to repair.

## Consequences

- Scientific models become first-class downstream products rather than
  privileged qualification harnesses.
- Required authoring and adapter hooks become tested internal-beta interfaces
  with explicit migration treatment.
- The large Phase 16 internal surface is classified instead of accidentally
  documented as supported.
- Complete case-study programs provide a strong independent check that supported
  downstream authoring is sufficient.
- Documentation quality becomes observable in the rendered product, not inferred
  only from source structure.
- Hosted cross-platform and browser evidence is required before the branch can
  be called complete.
- Public release, full paper reproduction, and whole-cell acceptance remain
  separate future decisions.

## Rejected alternatives

- Leave the models in CorePotts or benchmark harnesses.
- Promote the registry-v1 coupled runtime as public API.
- Let tutorials import prebuilt models.
- Replace explicit wiring and scheduling with silent autowiring.
- Use anonymous closures as reconstructable model identity.
- Treat the five internal-beta prose pages as sufficient documentation.
- Embed ProcessBigraphs pages into the Potts manual as a duplicate manual.
- Treat axe or Lighthouse scores as complete accessibility evidence.
- Run only scripted browser tests without a final task-based agent review.
- Permit browser findings through waivers.
- Publish or merge automatically merely because Phase 17 passes.

## Required conformance evidence

Closure requires every row in
`spec/process-bigraph-phase17-qualification-v1.toml` to be qualified, including:

- accepted interview and specification consistency;
- complete API inventory and docstrings;
- zero-internal canonical model and documentation scans;
- public-boundary lifecycle and compatibility tests;
- Merks and Wortel source, differential, oracle, and persistence evidence;
- visible tutorial/package equivalence;
- strict independent and root documentation builds;
- page, media, runtime, asset, and claim-boundary checks;
- macOS, Linux, and Windows clean smokes;
- Playwright cross-browser, accessibility, Lighthouse, and visual evidence;
- three persona task reviews;
- terminal browser-agent evidence; and
- exact qualifying-content-tree attestation.

## Authority

- [Round 1 interview](../../design/audits/process-bigraph-phase17-owner-interview-round-1.md)
- [Round 2 interview](../../design/audits/process-bigraph-phase17-owner-interview-round-2.md)
- [Round 3 interview](../../design/audits/process-bigraph-phase17-owner-interview-round-3.md)
- [Normative Phase 17 specification](../phase-17-process-bigraph-model-and-documentation-productization.md)
