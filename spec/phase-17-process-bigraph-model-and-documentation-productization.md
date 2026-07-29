# Phase 17 ProcessBigraph Model and Documentation Productization

Status: Normative specification; implementation not authorized

Version: 1.0.0

Date: 2026-07-29

## 1. Normative language and authority

The key words **MUST**, **MUST NOT**, **REQUIRED**, **SHOULD**, **SHOULD NOT**,
and **MAY** are normative.

This specification is governed by Decision 0042 and the three accepted Phase 17
owner interviews. If prose, TOML contracts, implementation, tests, generated
documentation, or evidence disagree, the stricter accepted requirement applies
until the contradiction is resolved through an owner-approved specification
change.

This document does not authorize implementation.

## 2. Phase boundary

Phase 17 MUST be implemented as one ordered phase:

1. **17.A Contract freeze**
2. **17.B Public boundary closure**
3. **17.C Model migration**
4. **17.D Independent manual**
5. **17.E Scientific case studies**
6. **17.F Reconciliation and attestation**

A later subgate MUST NOT compensate for an unqualified earlier subgate.

ProcessBigraphs MUST remain a qualified unpublished internal beta throughout the
phase. Phase 17 MUST NOT claim:

- registry publication;
- stable 1.x compatibility;
- complete Process-Bigraph parity;
- Dagger, distributed, or alternate-executor qualification;
- broad FBA, SBML, biochemical, or whole-cell integration;
- CNV case-study polish;
- Wortel Figure 2 reproduction;
- Merks Figure 5 morphometry or ensemble reproduction;
- source-author endorsement;
- external usability research; or
- human WCAG conformance certification.

## 3. Dependency and ownership rules

The following dependency direction is REQUIRED:

```text
ProcessBigraphs
      ↑
  CorePotts
      ↑
PottsToolkit
```

PottsToolkit MUST directly declare compat-bounded dependencies on CorePotts and
ProcessBigraphs. ProcessBigraphs MUST NOT depend on CorePotts or PottsToolkit.
The ProcessBigraphs documentation environment MAY depend on PottsToolkit,
CorePotts, MakiePotts, CairoMakie, Documenter, and browser tooling without
changing the production dependency graph.

Canonical scientific model ownership is:

- `PottsToolkit.ReferenceModels.Wortel2021`;
- `PottsToolkit.ReferenceModels.Merks2006`.

CorePotts MUST own only generic CPM mechanisms, execution façades, and adapters.
ProcessBigraphs MUST contain no Wortel- or Merks-specific biology.

File layout below `PottsToolkit.ReferenceModels` MAY change without compatibility
effect, but the public module paths and accepted call shapes MUST remain
supported according to the migration registry.

## 4. Canonical authoring form

The ordinary authoring entry MUST remain:

```julia
model = compose(:ModelName) do system
    # declarations
end
```

The complete programmatic surface MUST be sufficient without a macro. Canonical
tutorials MUST use typed handles and MUST show separate operations for:

- `store!`;
- `mount!`;
- `attach!`;
- `connect!`;
- `schedule!`;
- `observable!`;
- `parameter!` when parameters are taught; and
- `compile` or problem construction.

`expose!`, `iteration!`, and structural template operations MUST be shown when
their semantics are part of the page.

Silent name-based autowiring is forbidden. An operation that mounts a component
MUST NOT silently connect, schedule, or expose it. Optional convenience syntax
MAY group explicitly supplied declarations, but:

1. every connection and schedule remains an argument visible at the call site;
2. lowering is identical to the explicit operations;
3. `describe`, `diagram`, and `explain` expose the expanded form; and
4. canonical tutorials retain the explicit form.

## 5. Named behavior and identity

A custom process, step, or observer admitted in a required tutorial MUST have:

- a stable semantic name;
- an explicit semantic version;
- typed declared ports;
- typed semantic parameters;
- an explicit schedule or activation rule;
- a reconstructable Julia type or other qualified reconstructable descriptor;
- deterministic canonical identity; and
- documented failure and continuation behavior.

Anonymous closures MUST NOT enter semantic fingerprints, canonical model
serialization, checkpoints, or restoration authority. A closure MAY be used
inside nonsemantic analysis or rendering code if it is not required to
reconstruct execution.

The following identities MUST remain distinct:

- scientific model family and semantic version;
- ProcessBigraph semantic fingerprint;
- canonical IR fingerprint;
- execution-plan fingerprint;
- problem fingerprint;
- run identity;
- checkpoint identity; and
- documentation profile identity.

## 6. ProcessBigraphs API boundary

Every module binding MUST appear exactly once in the Phase 17 API inventory with
one class:

- `exported_user`;
- `public_extension`;
- `experimental_beta`;
- `deprecated_compat`;
- `internal`.

An exported or Julia-`public` binding is unsupported unless its inventory row
states otherwise. Conversely, an admitted user or extension binding MUST be
exported or declared `public` as specified by its row.

### 6.1 User authoring

The existing ordinary authoring, inspection, identity, problem, and structural
effect surface MUST remain admitted when used by required pages.

`managed_field_process(declaration; resource_authorization,
subcycles_per_mcs=1)` MUST be exported. Its returned concrete type MUST remain
internal. Validation MUST reject invalid subcycle counts and incompatible or
missing resource authorization before execution.

`schema_at` and `schema_leaves` MUST be the supported schema-inspection route.
Downstream scientific code MUST NOT access `BranchSchema.children` or another
concrete schema field.

### 6.2 Extension protocol

The complete engine adapter protocol required to implement the independent
custom-adapter example MUST be qualified public extension API. Extension
functions SHOULD be Julia-`public` and unexported. Concrete sessions, candidates,
completion handles, caches, workspaces, solver integrators, buffers, streams,
tasks, and device allocations MUST remain internal unless an inventory row
explicitly proves a public need.

The extension reference MUST define:

- implementor-owned types;
- required dispatch points;
- call ordering;
- publication ownership;
- failure atomicity;
- resource authorization;
- continuation/reconstruction behavior;
- conformance fixtures; and
- forbidden access.

### 6.3 Stability and docstrings

Every `exported_user` and `public_extension` binding MUST have:

- a docstring;
- an owning API page;
- a support-level label;
- at least one positive test;
- a misuse or failure test when invalid input is meaningful; and
- compatibility disposition.

Coverage MUST be 100%. No binding may remain unclassified.

## 7. CorePotts public boundary

CorePotts MUST provide an exported `ActivityPottsProblem` that represents the
supported execution of an `ActivityProgram` without exposing registry-v1
coupled runtime structures.

The façade MUST support the ordinary SciML lifecycle:

- `SciMLBase.init(problem, algorithm; kwargs...)`;
- `SciMLBase.step!(integrator)` and explicit bounded stepping as applicable; and
- existing supported solve behavior where semantically valid.

The façade MUST expose supported operations for:

- logical state;
- activity value lookup;
- typed observations;
- execution report;
- checkpoint capture; and
- compatible restore.

The exact binding spellings MUST be frozen in the Phase 17 API inventory before
17.B implementation. They MUST reuse existing generic CorePotts operations where
semantics match instead of adding activity-specific synonyms.

The following MUST remain internal:

- `CoupledIntegrator`;
- `CoupledState`;
- `MCSPlan`;
- `init_coupled`;
- coupled process records;
- registry-v1 workspaces;
- concrete observation storage;
- execution-plan metric fields; and
- direct integrator representation fields such as `mcs` and `algorithm`.

`static_relation(role, topology; spacing, weights)` MUST be supported.
`Act` MUST accept a supported topology or relation. Scientific model code MUST
NOT call a private offsets extractor.

## 8. Model product requirements

### 8.1 Shared requirements

Each model family MUST provide supported constructors for:

- semantic model;
- execution problem;
- ProcessBigraph composite;
- observation plan; and
- named execution profiles.

Every profile MUST record:

- source model version;
- source trace;
- profile identity;
- declared deviations or ambiguity choices;
- domain and runtime bounds;
- seed policy;
- backend claim;
- expected observations; and
- scientific nonclaims.

Required model, public test, example, and documentation source MUST contain zero
internal API references. A scanner MUST inspect qualified source, lowered code
references where practical, and explicit forbidden-name inventories.

### 8.2 Merks 2006

The canonical source-bounded Merks definition MUST retain the qualified 500×500
profile and Phase 16 source trace. Documentation MUST run a named reduced CPU
profile from the same model definition.

Merks semantic model v2 MUST:

- use only supported ProcessBigraphs authoring and schema access;
- construct fields through `managed_field_process`;
- use public CorePotts problem, stepping, state, observation, report, checkpoint,
  and restore operations;
- preserve supported `ReferenceModels.merks2006_*` call shapes;
- provide a differential record against v1 for every intentional change; and
- never present the reduced profile as the source configuration.

Phase 16 v1 fingerprints and evidence remain historical. A v1 checkpoint reader
MUST remain. Restoration MUST reject interpreting a v1 checkpoint as v2 without
an explicit migration operation.

### 8.3 Wortel 2021

Wortel semantic model v1 MUST be a new reusable family rather than a renamed
benchmark harness.

It MUST use:

- `Act`;
- supported topology or relation construction;
- `ActivityPottsProblem`;
- the public SciML lifecycle;
- supported logical state, activity, observation, report, checkpoint, and restore
  operations; and
- a versioned source-trace and bounded declared profile.

The existing qualification harness remains an independent oracle and low-level
backend evidence source. The reusable façade MUST match its accepted mechanism
outputs under the frozen comparison fixture. Full Figure 2 parameter/seed study
and reproduction claims remain excluded.

## 9. Tutorial transparency and equivalence

Every required tutorial, example, and case-study program MUST appear in an
evaluated reader-facing Documenter block.

The page MUST NOT use:

- reader-facing `include(...)`;
- `Base.include` through an alias;
- a generated hidden setup containing scientific assembly;
- `ReferenceModels.merks2006_*` or `ReferenceModels.wortel2021_*` as the model
  being taught;
- an imported prebuilt problem or composite; or
- unevaluated code as the only presentation of a claimed workflow.

Setup blocks MAY contain non-scientific rendering configuration or shared
documentation infrastructure, but MUST NOT contain model declarations,
scientific parameters, stores, components, wiring, schedules, observations, or
execution.

Each case-study test MUST independently construct:

1. the packaged model; and
2. the exact displayed model.

It MUST compare semantic fingerprints, declared profile metadata, relevant
lowered structure, and bounded observations.

## 10. Documentation architecture

The site MUST contain the page inventory accepted in Round 3:

- one Home;
- 10 Learn pages;
- Examples index plus six complete programs;
- Scientific Case Studies index plus Wortel and Merks;
- nine Concepts and Guarantees pages; and
- five API pages.

The machine-readable documentation contract owns exact IDs, paths, audiences,
support levels, canonical source, runtime class, visuals, and required tasks.

Every tutorial, example, and case study MUST state:

1. outcome;
2. prerequisites;
3. admitted APIs and support levels;
4. complete executed source;
5. material defaults and scientific choices;
6. expected result;
7. what the result establishes;
8. what it does not establish;
9. backend, runtime profile, and seed;
10. reproduction command; and
11. next step.

Home and every page MUST visibly identify the unpublished internal-beta status.

## 11. Visual and media requirements

Required visuals are:

- generated home visual;
- architecture/ownership diagram;
- scheduling/publication timeline;
- transaction/failure diagram;
- at least one result visual for every complete example;
- Wortel reduced-profile state figure, quantitative trace, and animation; and
- Merks reduced-profile state figure, quantitative trace, and animation.

Composition diagrams MUST derive from the same canonical model. Case-study
figures and traces MUST derive from the exact displayed program. Parallel
hand-authored scientific illustrations MUST NOT substitute for executable
output.

Every meaningful image MUST have descriptive alt text and a textual result
summary. Decorative images MUST have empty alt text and explicit presentation
semantics. Animations MUST:

- not autoplay with sound;
- have a static fallback;
- respect reduced-motion presentation;
- not be the sole evidence of an outcome; and
- remain within the media budget.

Media provenance MUST record source content digest, environment, command,
profile, seed, output hash, dimensions, frames, duration, encoding, and license
or original-work status.

## 12. Runtime and asset budgets

Budgets are measured after dependency instantiation and package compilation
unless a record explicitly states a cold-install measurement.

Required warm maxima:

- first tutorial: 10 seconds;
- each ordinary example: 15 seconds;
- Wortel reduced case study: 30 seconds;
- Merks reduced case study: 60 seconds;
- all required executable documentation programs: 240 seconds;
- strict ProcessBigraphs docs build: 480 seconds.

Hosted documentation job timeout MUST be 30 minutes.

Media maxima:

- each video: 3 MiB;
- all newly generated ProcessBigraphs site media: 15 MiB;
- each ordinary raster image: 512 KiB unless an explicit evidence-backed waiver
  is accepted before implementation; and
- SVG MUST be preferred for diagrams and plots where semantically adequate.

A budget miss MUST be fixed by implementation, profile design, rendering, or
asset optimization. The model's meaning or required documentation outcome MUST
NOT be silently weakened.

## 13. Documentation build and deployment

`lib/ProcessBigraphs/docs` MUST contain a pinned `Project.toml`, manifest,
`make.jl`, source registry, browser environment, and maintenance README.

`makedocs` MUST use:

- `doctest = true`;
- `warnonly = false`;
- strict cross-reference checking;
- a curated pages list;
- versioned HTML;
- the ProcessBigraphs repository source mapping; and
- an internal-beta banner on every page.

Deployment MUST use a unique monorepo `dirname = "ProcessBigraphs"` and package
tag prefix. Pull requests MUST build without production publication. Root and
ProcessBigraphs documentation deployment MUST be serialized or otherwise
protected from `gh-pages` write races.

The root Potts manual MUST link to the ProcessBigraphs manual and the two
scientific case studies without duplicating their complete runtime manual.

## 14. Automated rendered-site quality

### 14.1 Playwright

A lockfile-pinned browser environment MUST run Chromium, Firefox, and WebKit.
Required checks include:

- every curated route returns the expected document;
- navigation, next/previous links, search, and deep links work;
- the internal-beta banner is visible;
- complete canonical source is present and copyable;
- code blocks scroll without page-level overflow;
- meaningful media loads and has accessible alternatives;
- headings and landmarks form an intelligible accessibility tree;
- required controls have accessible names;
- no unexpected console error or warning occurs;
- no failed same-origin request occurs; and
- light and dark themes remain usable.

### 14.2 Accessibility

Every curated route MUST have zero axe violations for WCAG 2.0, 2.1, and 2.2 A
and AA tags supported by the pinned axe version. Disabling rules, excluding broad
containers, or snapshotting an accepted violation list is forbidden.

The terminal browser agent MUST additionally assess:

- keyboard reachability and order;
- no keyboard trap;
- visible focus;
- focus not obscured;
- bypass blocks;
- page titles;
- heading and label clarity;
- link purpose;
- target usability;
- reflow and text spacing;
- non-text alternatives;
- contrast not completely determined by automation;
- reduced motion; and
- search/modal dismissal.

The evidence MUST state that this is auditor-led browser assessment, not a human
accessibility conformance audit.

### 14.3 Lighthouse

Home, first tutorial, Wortel, Merks, and extension API MUST achieve:

- Accessibility 100;
- Best Practices 100;
- SEO at least 95;
- mobile Performance at least 90; and
- CLS at most 0.1.

Lighthouse MUST run from a local production-style static server with pinned
configuration. At least three runs per route MUST be recorded; the median is
the score authority and no individual run may fall more than five points below
the applicable threshold.

### 14.4 Visual regression

Golden screenshots MUST be generated and compared only in the pinned
Linux/Chromium environment with animations disabled, fonts loaded, deterministic
media state, and fixed viewports.

A golden update MUST include:

- changed route and viewport;
- actual, expected, and diff artifacts;
- reason for the change;
- qualifying content digest; and
- browser-agent disposition.

The test MUST use a small explicit diff tolerance. It MUST NOT use a threshold
large enough to hide missing content, overflow, contrast failure, or structural
layout change.

## 15. Terminal browser-agent quality gate

The browser-agent gate MUST run after every deterministic qualification gate is
green.

Required viewports:

- 1440×900;
- 1024×768;
- 390×844.

Home, first tutorial, Wortel, Merks, and API MUST be inspected in light and dark
themes. The agent MUST complete all accepted Round 3 journeys.

The agent MUST use the rendered DOM, accessibility tree, real interactions,
console/network state, and screenshots. Static source inspection alone is not
admissible.

Each journey record MUST include:

- persona;
- starting route;
- task statement;
- actions;
- success criteria;
- observed result;
- viewport and theme;
- screenshot or DOM evidence;
- console/network disposition;
- finding IDs; and
- pass/fail.

Any failure MUST reopen implementation. After repair, affected deterministic
gates and the complete terminal browser gate MUST rerun. No waiver is allowed.

## 16. Qualifying content digest

The Phase 17 entry contract MUST enumerate qualifying path prefixes and
evidence-only exclusions.

The digest MUST cover at least:

- production source and package metadata;
- extension source;
- model source;
- tests and fixtures;
- integration source;
- benchmark oracles used by Phase 17;
- root and ProcessBigraphs documentation source;
- visible canonical programs;
- generated committed media;
- documentation and browser dependency manifests;
- browser, accessibility, Lighthouse, and visual-test configuration;
- quality scripts;
- workflows; and
- Phase 17 normative contracts.

Evidence manifests, screenshots, logs, and closure audits MAY be excluded only
when they cannot influence the built product or test behavior.

After evidence metadata is committed, a checker MUST recompute the qualifying
content digest and prove equality with the browser-qualified digest.

## 17. Cross-platform and compatibility qualification

Clean environments MUST validate installation, loading, the public smoke, and
the strict ProcessBigraphs documentation build on:

- Linux x86_64;
- macOS aarch64; and
- Windows x86_64.

Required Julia version is 1.12.6 unless the project baseline changes before
send-off and the specification packet is deliberately reconciled.

Phase 17 MUST retain applicable package, integration, independent-oracle,
performance, persistence, documentation, and exact-identity evidence.

Real Metal or ROCm requalification is REQUIRED only when a checked impact map
finds a change to:

- device kernel source;
- device-visible data layout;
- device ABI;
- backend dispatch;
- transfer/residency semantics; or
- a qualified device claim.

## 18. Evidence and completion

The qualification ledger MUST contain no `qualified` row without:

- command or task identity;
- exact content digest;
- environment;
- result;
- evidence path or hosted artifact;
- assertion or route count where applicable; and
- limitation statement.

Phase 17 is complete only when every required row is `qualified`, the
documentation rubric is at least 92/100 with no category below 8/10, and the
final qualifying content digest matches the terminal browser evidence.

Completion MUST NOT imply merge, publication, release, reproduction, parity, or
whole-cell qualification.

## 19. Autonomous execution boundary

After explicit send-off, the agent MAY:

- merge `origin/main` normally into the existing branch;
- resolve in-scope conflicts without discarding either history;
- edit all in-scope repository paths;
- commit intentionally;
- push only the Phase 17 branch;
- open or update one draft pull request;
- rerun hosted workflows; and
- repair every in-scope qualification failure.

The agent MUST preserve unrelated user work and the owner's `paper.pdf`
deletion. It MUST NOT reset, rebase, destructively check out, create a second
implementation branch, merge to `main`, publish a package release, or weaken a
gate.

The run stops only for the accepted Round 3 stop conditions. A stop report MUST
name the exact blocker, exhausted safe alternatives, affected rows, and the
smallest owner decision or external change required.
