# ProcessBigraphs Phase 17 Autonomous Implementation Plan

Date: 2026-07-29

Status: active; explicit owner send-off received

Authority:

- Decision 0042;
- the Phase 17 normative specification;
- the three accepted Phase 17 owner interviews; and
- the machine-readable entry, API, documentation, browser, and qualification
  contracts.

## 1. Objective

Complete one autonomous Phase 17 on `codex/ProcessBigraphs-Docs` that:

1. closes the smallest supported user and adapter boundaries required by Wortel,
   Merks, and the independent manual;
2. migrates both scientific model families to PottsToolkit without internal API
   access;
3. creates a strict, versioned, high-quality ProcessBigraphs documentation site;
4. displays and executes both complete model assemblies inline;
5. qualifies rendered behavior, accessibility, performance, and visuals; and
6. ends with an exact-content terminal browser-agent pass.

The owner authorized autonomous Phase 17 implementation with the persistent goal
“finish phase 17.”

## 2. Invariants

Every implementation chunk MUST preserve:

- one production authority for each semantic concept;
- ProcessBigraphs ownership of when and why computation occurs;
- engine and CorePotts ownership of authorized heavy numerical work;
- canonical ACSet and compiled-plan authority;
- exact transactional publication and failure atomicity;
- deterministic semantic identity and RNG;
- qualified checkpoint readers;
- source-bounded rather than reproduction model claims;
- no ProcessBigraphs dependency on a Potts package;
- no internal API in canonical models or required documentation;
- no hidden scientific setup in required pages;
- no automatic main merge or package release; and
- all unrelated user work.

## 3. Baseline integration after send-off

### 3.1 Read-only preflight

Record:

```text
git status --short
git branch --show-current
git rev-parse HEAD
git rev-parse origin/main
git log --left-right --cherry-pick --oneline HEAD...origin/main
```

Confirm:

- branch is `codex/ProcessBigraphs-Docs`;
- the existing branch-only CI-trimming commit is present;
- the three interview files and specification packet are present;
- `paper.pdf` remains deleted as owner work; and
- no unexpected user mutation overlaps Phase 17 targets.

### 3.2 Merge

Fetch normally, then merge `origin/main` with an ordinary merge commit. Do not
reset, rebase, destructively check out, or create another implementation branch.

Resolve conflicts by retaining:

- the qualified `origin/main` production and evidence baseline;
- the branch's intentional CI-trimming change;
- the owner interview and specification packet;
- the owner’s `paper.pdf` deletion; and
- any unrelated user changes.

Run the specification checker immediately after resolution. Commit the resolved
contract freeze before runtime implementation.

## 4. Subgate 17.A — Contract freeze

### 4.1 Reconcile paths and versions

Update only specification metadata made stale by the baseline merge:

- exact baseline commit and tree;
- current package versions;
- consolidated file paths;
- workflow names; and
- dependency manifests.

Do not change an accepted decision to match convenient implementation.

### 4.2 Create entry tooling

Implement:

- `scripts/check_process_bigraph_phase17_spec.jl`;
- `scripts/check_process_bigraph_phase17_api.jl`;
- `scripts/check_process_bigraph_phase17_docs.jl`;
- `scripts/check_process_bigraph_phase17_browser_contract.jl`;
- `scripts/check_process_bigraph_phase17_internal_use.jl`; and
- `scripts/check_process_bigraph_phase17_closure.jl`.

The first checker exists in the pre-send-off packet. The remaining checkers are
17.A implementation deliverables.

### 4.3 Freeze inventories

Generate a complete binding inventory from the merged source. Reconcile every
binding against `process-bigraph-phase17-api-v1.toml`.

Freeze:

- admitted binding name;
- module;
- class;
- export/public status;
- owner page;
- docstring requirement;
- compatibility action;
- tests; and
- required tutorial use.

No runtime source change begins until every binding is classified and the API
checker fails closed on an unclassified fixture.

### 4.4 Exit

17.A exits only when P17-A01–P17-A05 are qualified and all machine contracts
agree on subgates, row count, pages, budgets, API additions, exclusions,
autonomy, and closure rules.

## 5. Subgate 17.B — Public boundary closure

Implement in dependency order.

### 5.1 ProcessBigraphs schema and extension surface

1. Verify `schema_at` and `schema_leaves` cover all downstream needs.
2. Add missing behavior without exposing concrete branch storage.
3. Mark the qualified engine extension protocol with Julia `public`.
4. Remove broad exports only where the v0.6 migration registry explicitly
   permits it.
5. Keep concrete sessions, candidates, handles, caches, buffers, tasks, and
   solver objects internal.
6. Add docstrings and conformance tests before downstream migration.

### 5.2 Managed field constructor

Add exported:

```julia
managed_field_process(
    declaration;
    resource_authorization,
    subcycles_per_mcs = 1,
)
```

Test:

- valid construction;
- stable semantic parameters;
- invalid subcycle rejection;
- absent and incompatible authorization rejection;
- opaque concrete return type;
- Merks-required behavior; and
- compatibility with existing qualified managed-field execution.

### 5.3 CorePotts activity façade

Add exported `ActivityPottsProblem`.

Implement:

- `SciMLBase.init`;
- `SciMLBase.step!`;
- `logical_state`;
- `site_property_value`;
- `current_mcs_report`;
- `ProcessBigraphs.observation_records`;
- `capture_checkpoint`; and
- `restore_checkpoint`.

Use existing generic names and semantics. Do not add redundant
`activity_*` aliases.

Test:

- construction and validation;
- deterministic initialization;
- one-step and bounded-step execution;
- activity lookup;
- observation retention;
- report access;
- checkpoint exact restart;
- incompatible restore rejection;
- algorithm and model mismatch rejection;
- no direct coupled runtime fields in public tests; and
- Aqua/API inventory agreement.

### 5.4 Topology admission

Implement:

```julia
static_relation(role, topology; spacing, weights)
```

Extend `Act` to accept a supported topology or relation. Test equivalence to the
qualified relation under the accepted Wortel fixture, plus invalid role,
dimension, spacing, and weight failures.

### 5.5 Internal boundary negative tests

Prove the required source contains none of:

- `ManagedFieldAdvanceProcess`;
- `.children` on `BranchSchema`;
- `init_coupled`;
- `CoupledIntegrator`;
- `CoupledState`;
- `MCSPlan`;
- direct `.mcs` or `.algorithm` integrator access;
- private coupled workspaces;
- private observation storage;
- private execution-plan metrics; or
- private topology offset extraction.

### 5.6 Exit

17.B exits only when P17-B01–P17-B09 are qualified in clean independent package
environments and the API inventory/docstring checker is 100%.

## 6. Subgate 17.C — Model migration

### 6.1 Source organization

Replace the monolithic reference-model include structure with:

```text
src/reference_models/
  ReferenceModels.jl
  wortel_2021.jl
  merks_2006.jl
  compatibility.jl
```

Public access remains through `PottsToolkit.ReferenceModels`. File names and
include order are internal.

### 6.2 Wortel family

Implement named constructors for:

- semantic model v1;
- declared profile;
- `ActivityPottsProblem`;
- ProcessBigraph composite;
- observation plan; and
- reduced documentation run.

Transcribe only the source-bounded accepted mechanism. Record all fixed and
ambiguous choices. Build an independent façade-to-harness fixture with:

- equal topology semantics;
- equal Act parameters;
- equal initial logical state;
- equal seeded accepted-copy/activity behavior for the bounded slice;
- equal relevant observations; and
- explicit differences caused by the reusable façade.

The benchmark qualification harness remains independent. Do not share decisive
oracle logic.

### 6.3 Merks family

Move scientific assembly ownership downstream without moving generic numerical
mechanisms.

Implement one model definition parameterized by named profiles:

- canonical `500x500`;
- reduced docs CPU.

Use public ProcessBigraphs and CorePotts only. Create a v1-to-v2 differential
registry covering:

- ownership/module path;
- managed field constructor;
- schema access;
- integrator access;
- fingerprint;
- checkpoint version;
- preserved scientific parameters;
- preserved source/ambiguity trace; and
- accepted bounded outputs.

Keep v1 readers and shims. Reject silent v1-as-v2 restore.

### 6.4 Model lifecycle matrix

For each profile required by the contract, test:

1. construct;
2. validate;
3. lower/compile;
4. initialize;
5. step/run;
6. observe;
7. report;
8. checkpoint;
9. restore;
10. exact bounded continuation; and
11. semantic manifest.

### 6.5 Exit

17.C exits only when P17-C01–P17-C08 are qualified and the internal-use scanner
reports zero canonical-model violations.

## 7. Subgate 17.D — Independent manual

### 7.1 Documentation environment

Create:

```text
lib/ProcessBigraphs/docs/
  Project.toml
  Manifest.toml
  make.jl
  README.md
  src/
  models/
  browser/
```

Pin Documenter and all rendering/browser dependencies. The docs environment may
develop local packages but must not modify their production dependency graph.

### 7.2 Information architecture

Implement every registered page from
`process-bigraph-phase17-documentation-quality-v1.toml`. `make.jl` navigation
and the registry must match exactly.

Use a persistent internal-beta banner, direct repository-install instructions,
support labels, source/edit links, and version/migration navigation.

### 7.3 Canonical visible programs

Each required executable page has one standalone `.jl` source and byte-normalized
visible containment in evaluated Documenter blocks. The quality checker rejects:

- reader `include`;
- aliasing `include`;
- hidden scientific setup;
- missing imports;
- prebuilt reference models;
- incomplete execution;
- drift from canonical source; and
- unevaluated claimed results.

### 7.4 Concepts and API

Write concepts from accepted semantics, not implementation representation.

API pages are curated by task. An autogenerated index MAY supplement but MUST
NOT replace:

- user authoring;
- semantic values/schemas/schedules/effects;
- process/step/observer/runtime/checkpoint;
- composition/structure; and
- extension/experimental/compatibility.

### 7.5 Visual portfolio

Derive diagrams from canonical models. Generate example and case-study media
from displayed sources in the pinned environment. Record media provenance and
budgets.

Animations are short inspection loops with poster/static fallback, reduced-motion
treatment, alt text, and textual quantitative summaries.

### 7.6 Deployment

Use:

- `dirname = "ProcessBigraphs"`;
- package tag prefix;
- `devbranch = "main"`;
- no PR production deployment; and
- serialized gh-pages writes with root docs.

### 7.7 Exit

17.D exits only when P17-D01–P17-D09 are qualified, the warm runtime and asset
budgets pass, and both strict docs sites build without warnings.

## 8. Subgate 17.E — Scientific case studies

### 8.1 Required page structure

Each case study includes:

- content-class banner;
- source citation and trace;
- explicit accepted profile;
- complete inline assembly;
- diagram;
- execution;
- typed observation;
- state figure;
- quantitative trace;
- short animation;
- packaged/displayed equivalence;
- full qualification command;
- admitted conclusion; and
- explicit nonclaims.

### 8.2 Wortel

State clearly:

- reduced bounded configuration;
- Act mechanism and topology;
- source-trace choices;
- backend used by docs;
- separate existing CPU/Metal/ROCm mechanism evidence; and
- excluded 51-parameter/30-seed Figure 2 study.

### 8.3 Merks

State clearly:

- reduced docs profile;
- canonical 500×500 profile;
- exact shared model definition;
- source and ambiguity trace;
- full qualification command; and
- excluded Figure 5 morphometry/ensemble analysis.

### 8.4 Exit

17.E exits only when P17-E01–P17-E04 are qualified and a scanner proves neither
page imports a prebuilt model or hides scientific setup.

## 9. Subgate 17.F — Reconciliation and attestation

### 9.1 Deterministic gate order

Run:

1. specification and project integrity;
2. independent package tests;
3. cross-package integration;
4. independent specification oracles;
5. model differential/oracle/lifecycle suites;
6. compatibility and persistence;
7. internal-use scanner;
8. root documentation quality and strict build;
9. ProcessBigraphs documentation quality and strict build;
10. runtime and asset budgets;
11. cross-platform clean smokes;
12. Playwright Chromium/Firefox/WebKit;
13. axe WCAG route scans;
14. Lighthouse;
15. pinned visual regression;
16. three persona task-review records; and
17. qualifying content digest.

GPU qualification runs only if the checked impact map requires it.

### 9.2 Hosted workflows

Push only the Phase 17 branch and open or update one draft PR. Required hosted
jobs include:

- Linux package/integration/docs/browser;
- macOS package/integration/docs smoke;
- Windows package/docs smoke;
- independent oracle and performance;
- exact-content digest; and
- Required aggregate.

Workflow failures are repaired on the same branch. Do not bypass, mark neutral,
or reduce the required matrix.

### 9.3 Terminal browser-agent gate

After every deterministic gate is green:

1. rebuild the exact ProcessBigraphs site;
2. serve it locally;
3. run every registered journey;
4. inspect required routes at desktop, tablet, and mobile;
5. inspect terminal routes in light and dark;
6. record DOM/accessibility, screenshots, console, network, findings, and result;
7. repair every finding and restart affected deterministic gates; and
8. repeat until the complete browser gate passes.

### 9.4 Evidence-only closure

Commit the browser and closure evidence only under declared evidence-only paths.
Recompute the qualifying content digest. It must match the browser-qualified
digest.

Perform the terminal exact-content browser check on the final branch state
without further qualifying-path changes.

### 9.5 Exit

17.F exits only when P17-F01–P17-F09 and all 44 ledger rows are qualified.
ProcessBigraphs remains unpublished. The draft PR is ready for owner review but
is not merged.

## 10. Failure repair policy

No in-scope failure receives a waiver.

For each failure:

1. preserve the failing artifact;
2. identify the earliest violated contract;
3. implement the smallest semantic fix;
4. add a regression test;
5. rerun the affected gate and all downstream gates;
6. update evidence without rewriting history; and
7. keep scientific nonclaims unchanged.

## 11. Autonomous stop policy

Stop only for:

- missing credentials or authority;
- sustained external-service failure after safe retries;
- newly required hardware unavailable to the project;
- destructive ambiguity involving user work; or
- a contradiction that requires changing scope or a scientific claim.

Before stopping, exhaust read-only diagnosis, documented retries, safe local
alternatives, and unaffected work. The blocker report names exact rows and the
smallest decision required.

Do not stop merely because work is large, tests fail, builds are slow, a browser
finds defects, or the token/context window compacts.

## 12. Handoff

The completed handoff includes:

- exact branch and commit;
- draft PR URL;
- package versions;
- qualifying content digest;
- 44-row qualification ledger;
- documentation rubric;
- browser evidence;
- cross-platform workflow run IDs;
- conditional GPU impact disposition;
- migration guide;
- remaining nonclaims; and
- confirmation that no merge or release occurred.
