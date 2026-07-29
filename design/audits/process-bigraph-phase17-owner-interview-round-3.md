# ProcessBigraphs Phase 17 Owner Interview — Round 3

Date: 2026-07-29

Participants: project owner, Codex architecture and documentation auditor

Research baseline: qualified Phase 16 and semantic-preserving consolidation at
`origin/main` commit `04f39dc05f847b7dd84f24f12cce24d1ed0229a6`

Status: accepted in full

## Scope of this round

Round 3 closes the remaining Phase 17 decisions: exact autonomous phase ordering,
canonical authoring style, complete documentation inventory, runtime and media
budgets, API and model qualification, rendered-site automation, accessibility and
performance thresholds, the terminal browser-agent quality gate, exact-tree
invalidation, branch and hosted-CI authority, autonomous stop conditions, and the
completion definition.

This interview does not authorize implementation. After acceptance, the next
deliverable is the complete Phase 17 specification packet. Runtime, model,
documentation, workflow, branch-integration, push, and pull-request work still
wait for the project owner's explicit implementation send-off.

## Repository research basis

### Existing documentation quality authority

The qualified Potts documentation establishes the local quality floor:

- 42 curated pages;
- 14 progressive Learn pages and 10 canonical gallery examples;
- reader-visible programs executed by Documenter;
- strict `doctest = true`, `warnonly = false` builds;
- complete stable public-name classification and docstring evidence;
- macOS, Linux, and Windows clean-install smokes;
- generated figures and bounded animations with source provenance;
- external-link checking; and
- auditor-led beginner, model-builder, and extension-author task reviews.

The visible-workflow audit records the critical correction that canonical source
existence is not equivalent to teaching it. Required programs must appear in
evaluated reader-facing blocks; `include(...)` and reference-model shortcuts
cannot hide the workflow.

ProcessBigraphs 0.5.1 currently has five package-local prose pages and no
independent `Project.toml`, `make.jl`, strict Documenter build, page registry,
API documentation inventory, visual portfolio, platform smoke, or rendered-site
quality gate.

### Browser calibration

The current published Potts development manual was inspected in the Codex
in-app browser at desktop and 390-pixel mobile widths. The inspection confirmed:

- outcome-first navigation and readable progressive structure;
- working documentation search;
- visible and copyable evaluated code;
- responsive page layout without page-level horizontal overflow;
- intentionally scrollable code blocks;
- loaded generated media;
- clean browser console output on the inspected journeys; and
- successful navigation from the landing page to a deep tutorial route.

The browser also identified a rendered tutorial image without an accessible
name. Whether such an element is meaningful or decorative cannot be established
from Markdown inventory alone. Phase 17 therefore treats rendered DOM,
accessibility tree, interaction, viewport, and screenshot inspection as
independent evidence rather than an optional duplicate of static checks.

### Exact-head and closure precedent

Phase 16 and semantic-preserving consolidation use content-addressed candidate
trees, exact CI artifacts, machine-readable ledgers, explicit zero-functional-
delta metadata boundaries, and exact-head rechecks. Phase 17 retains this
discipline while defining a qualifying content-tree path set so that adding
evidence-only attestation metadata does not recursively invalidate the
scientific, runtime, documentation, or browser-tested content.

### External primary-source research

The external basis is limited to primary or official documentation:

- Julia public API and package-extension rules:
  <https://docs.julialang.org/en/v1/manual/faq/#Public-API>,
  <https://docs.julialang.org/en/v1/manual/modules/>, and
  <https://docs.julialang.org/en/v1/manual/code-loading/#Package-Extensions>;
- SciML problem/integrator lifecycle:
  <https://docs.sciml.ai/SciMLBase/stable/interfaces/Init_Solve/> and
  <https://docs.sciml.ai/DiffEqDocs/stable/basics/integrator/>;
- Documenter strict builds, versioning, and monorepo `dirname` deployment:
  <https://documenter.juliadocs.org/stable/> and
  <https://documenter.juliadocs.org/stable/man/hosting/>;
- WCAG 2.2 and W3C evaluation limits:
  <https://www.w3.org/TR/WCAG22/>,
  <https://www.w3.org/WAI/standards-guidelines/wcag/new-in-22/>, and
  <https://www.w3.org/WAI/test-evaluate/tools/selecting/>;
- Playwright accessibility, accessibility-tree snapshots, and visual testing:
  <https://playwright.dev/docs/next/accessibility-testing>,
  <https://playwright.dev/docs/aria-snapshots>, and
  <https://playwright.dev/docs/test-snapshots>;
- Lighthouse:
  <https://developer.chrome.com/docs/lighthouse/overview> and
  <https://developer.chrome.com/docs/lighthouse/accessibility/scoring/>; and
- Core Web Vitals thresholds:
  <https://web.dev/articles/defining-core-web-vitals-thresholds>.

W3C and Playwright both state that automated tools cannot determine complete
accessibility. Phase 17 therefore combines automated WCAG checks with task-based
browser-agent assessment. Playwright also warns that screenshot output varies by
browser, platform, fonts, and hardware, so visual baselines are qualified only
inside one pinned Linux/Chromium environment.

## Accepted decisions

### Phase execution and canonical syntax

| ID | Decision | Rationale | Revisit trigger |
|:--|:--|:--|:--|
| P17-R3-01 | Phase 17 remains one ordered phase with subgates 17.A–17.F. Red tests, browser failures, performance misses, and documentation defects are implementation work rather than stop conditions. | The phase is intended to complete autonomously without fragmenting product ownership or requiring owner supervision for ordinary engineering decisions. | A required dependency materially broadens the accepted scientific or product scope. |
| P17-R3-02 | After this interview, produce the complete decision, normative specifications, entry registry, API registry, documentation contract, qualification ledger, browser-QA protocol, and implementation plan before implementation. Implementation still waits for explicit owner send-off. | The owner requires rock-solid specifications and interviews before autonomous execution. | The owner explicitly changes the send-off protocol. |
| P17-R3-03 | Canonical tutorials use `compose(:Name) do model` with typed handles and visibly distinct `store!`, `mount!`, `attach!`, `connect!`, `schedule!`, `observable!`, and `compile` operations. Canonical teaching material does not use opaque autowiring or an all-in-one mount/wire/schedule call. | Separate orchestration operations remain readable, inspectable, and faithful to explicit process-bigraph composition. | Rendered task evidence proves a different spelling is both clearer and equally explicit before API freeze. |
| P17-R3-04 | Custom processes and steps are ordinary named Julia types with explicit ports, parameters, semantic versions, and schedules. Anonymous closures cannot be semantic or persistence authority. Convenience syntax is admissible only when `describe`, `diagram`, and `explain` expose its complete lowering. | Stable names and versions preserve identity, restart, provenance, and understandable extension boundaries without sacrificing readable Julia. | A qualified reconstructable behavior representation supersedes named Julia types. |
| P17-R3-05 | Wortel and Merks pages display and execute their complete model assembly. They may import packages and supported components, but may not use `include`, hidden setup files, or `ReferenceModels.*` constructors as substitutes for the model being taught. Packaged and tutorial assemblies must have equal semantic fingerprints and accepted bounded outputs. | Full visible syntax is a learning requirement and an independent proof that downstream users can construct the models using supported APIs. | The owner explicitly relaxes the Round 2 tutorial-transparency amendment. |

### Documentation product

| ID | Decision | Rationale | Revisit trigger |
|:--|:--|:--|:--|
| P17-R3-06 | Build an independent versioned ProcessBigraphs site from its package-local Documenter environment. Deploy it from the monorepo with `dirname = "ProcessBigraphs"` and a package-specific tag prefix, producing the development route `/Potts.jl/ProcessBigraphs/dev/`. Show a persistent qualified-unpublished-internal-beta banner. | Documenter officially supports unique monorepo `dirname` deployment, preserving package identity without a second repository or deployment authority. | Repository or hosting topology changes. |
| P17-R3-07 | Require at least 35 curated pages: one Home; 10 Learn; an Examples index plus six complete programs; a Scientific Case Studies index plus Wortel and Merks; nine Concepts and Guarantees pages; and five API pages. Pages may be added, but required outcomes cannot be collapsed away merely to meet a smaller count. | ProcessBigraphs is narrower than the full Potts product but still needs a complete composer, adapter, reproducibility, contributor, and scientific-case-study journey. | Task evidence proves a smaller structure preserves every required outcome with better navigation. |
| P17-R3-08 | The Learn sequence covers installation/status; mental model; first multirate composite; stores, ports, and updates; composition and diagrams; scheduling and publication; writing processes, steps, and observers; adapters and solvers; dynamic structure; and checkpoint, failure, and replay. | This order teaches the runtime's distinguishing semantics progressively before advanced extension and structural behavior. | A prerequisite audit demonstrates a safer sequence without removing outcomes. |
| P17-R3-09 | The six complete example programs are pulse/decay, reusable nested composites, n-way junctions, a SciML field adapter, an independent custom engine adapter, and structural division with failure/recovery. | Together they cover ordinary authoring, open composition, fan-in, ecosystem integration, extension conformance, dynamic structure, and atomic recovery without broadening into deferred scientific ecosystems. | A required capability cannot be taught in this set or an example proves redundant in task review. |
| P17-R3-10 | Every tutorial, example, and case study states prerequisites, support level, complete executed source, expected result, scientific meaning, nonclaims, seed/runtime/backend, reproduction command, and next step. | A page is not complete merely because its code runs; readers must understand its authority and bounded claim. | A stronger machine-enforced page contract supersedes these fields. |
| P17-R3-11 | Require a generated home visual, architecture diagram, scheduling/publication timeline, transaction diagram, one result visual for every example, and for each case study a deterministic reduced-profile state figure, quantitative trace, and short bounded animation with a static fallback and textual summary. Meaningful images require alt text; decorative images must be explicitly hidden. Media commands, source identity, and hashes are recorded. | This matches the existing visual documentation quality while keeping temporal media accessible, bounded, and reproducible. | A medium cannot be generated reproducibly within the accepted budgets. |
| P17-R3-12 | Warm execution budgets are: first tutorial at most 10 seconds, each ordinary example at most 15 seconds, Wortel at most 30 seconds, and Merks at most 60 seconds. Complete warm example execution is capped at four minutes, the strict docs build at eight minutes, and a hosted documentation job at 30 minutes. Each video is capped at 3 MB and total new generated site media at 15 MB. | Explicit budgets keep the independent manual usable in pull requests while retaining meaningful model behavior. | Measured qualified evidence proves a threshold is unachievable without weakening a required teaching or scientific outcome; any amendment requires owner approval. |

### API and model qualification

| ID | Decision | Rationale | Revisit trigger |
|:--|:--|:--|:--|
| P17-R3-13 | Register every ProcessBigraphs binding as exported user API, qualified public extension API, experimental/internal-beta API, or implementation detail. Admitted user and extension APIs require 100% docstrings and owning reference pages. | The package currently exposes a broad surface; complete intentional classification prevents accidental promises and missing adapter contracts. | Julia or repository policy adopts a stronger authoritative inventory mechanism. |
| P17-R3-14 | Canonical models, tutorials, examples, public tests, and documentation must contain zero internal API references. Benchmark-only white-box probes require an exact machine-readable allowlist. | Scientific authoring and teaching must prove the supported boundary; isolated low-level qualification may retain explicitly governed inspection. | Public diagnostic APIs eliminate every benchmark exception. |
| P17-R3-15 | Merks semantic v2 passes v1 differential fixtures within the accepted semantic-change envelope. Wortel semantic v1 passes against the frozen mechanism oracle. Both pass build, run, observe, checkpoint, restore, and tutorial/package equivalence tests. | Migration must preserve admitted behavior honestly while distinguishing changed semantic identities. | A new source or qualification authority changes the accepted oracle. |
| P17-R3-16 | Preserve the Round 2 forwarding shims, call shapes, checkpoint readers, explicit fingerprint migration, and prohibition on silent v1-as-v2 restoration. Device qualification reruns only if kernel semantics or device ABI changes. | This protects supported callers and frozen evidence without ceremonial hardware work for documentation-only or façade-only changes. | The qualified diff changes a device kernel, device ABI, or backend claim. |

### Automated rendered-site QA

| ID | Decision | Rationale | Revisit trigger |
|:--|:--|:--|:--|
| P17-R3-17 | Add a pinned package-local Playwright environment with Chromium, Firefox, and WebKit tests for navigation, search, deep links, code visibility and copying, responsive overflow, media loading, status banners, console errors, and accessibility-tree structure. | Static Markdown and Documenter checks cannot prove interactive rendered behavior or cross-browser layout. | A qualified replacement provides at least the same browser and evidence coverage. |
| P17-R3-18 | Target WCAG 2.2 Level AA on every curated route. Automated scans permit no disabled axe rules or broad exclusions and must report zero WCAG A/AA violations. The browser agent separately assesses keyboard order, visible and unobscured focus, bypass navigation, motion, headings, accessible names, and textual alternatives. | Automated tools catch common failures but official guidance says they cannot establish complete accessibility. | A later WCAG revision or accepted accessibility contract supersedes 2.2 AA. |
| P17-R3-19 | On Home, the first tutorial, Wortel, Merks, and the extension API, require Lighthouse Accessibility 100, Best Practices 100, SEO at least 95, mobile Performance at least 90, and CLS at most 0.1. Run screenshot regression in one pinned Linux/Chromium environment. Baseline updates require a recorded browser-agent visual disposition. | Lab scores and stable visual baselines catch regressions that content tests miss, while a fixed renderer controls documented screenshot variability. | Qualified evidence demonstrates a Documenter-owned limitation that cannot be corrected locally without materially forking the theme; any exception requires owner approval. |

### Terminal browser-agent gate

| ID | Decision | Rationale | Revisit trigger |
|:--|:--|:--|:--|
| P17-R3-20 | Run the browser-agent gate only after package, integration, documentation, accessibility, Lighthouse, visual-regression, and cross-platform gates pass. It is the final functional gate. | Human-like task assessment should evaluate a technically qualified candidate, not substitute for deterministic checks. | None within Phase 17. |
| P17-R3-21 | Inspect 1440×900 desktop, 1024×768 tablet, and 390×844 mobile. Inspect Home, the first tutorial, Wortel, Merks, and API in both light and dark themes. | These viewports cover the desktop documentation layout, intermediate collapse, and narrow mobile reading experience; theme coverage catches contrast and media errors. | A supported theme or responsive breakpoint changes. |
| P17-R3-22 | The browser agent must: discover, copy, and execute the first multirate model; build and inspect a nested composite without hidden setup; locate extension hooks and follow the minimal adapter path; capture and exactly restart a simulation; run both reduced case studies; correctly identify what each proves and does not prove; and locate migration, capability, and beta-status information through navigation and search. | These journeys directly exercise the three priority review personas and the principal scientific-claim boundary. | Audience priority or accepted task outcomes change. |
| P17-R3-23 | Any browser finding reopens implementation. After repair, rerun all affected deterministic checks and then the complete browser-agent gate. Browser waivers are prohibited. | A terminal gate is meaningful only if failures cause repair and full re-evaluation. | The owner explicitly changes the completion contract. |
| P17-R3-24 | Browser evidence records the qualifying content-tree digest, routes, viewport, theme, task transcript, screenshots, console state, findings, repairs, and final disposition. Any qualifying source, test, configuration, or documentation change invalidates it. Evidence-only attestation metadata does not change the qualified content digest. | Content-scoped exactness preserves rigorous provenance without an infinite self-referential evidence commit loop. | A stronger content-addressed attestation system supersedes the path-set digest. |

### Branch, CI, authority, and completion

| ID | Decision | Rationale | Revisit trigger |
|:--|:--|:--|:--|
| P17-R3-25 | After explicit send-off, normally merge `origin/main` into `codex/ProcessBigraphs-Docs`, preserving the branch's existing commit, all interview and specification artifacts, and the owner's `paper.pdf` deletion. Perform all Phase 17 work on that branch. | This reconciles the qualified baseline without destructive history changes or a second implementation branch. | The owner explicitly authorizes another history operation. |
| P17-R3-26 | Autonomous authority includes intentional commits, pushing only this branch, opening or updating one draft pull request, and driving its required workflows to green. It excludes merging to `main`, publishing a registry release, production deployment outside the existing post-merge workflow, or weakening branch protection. | Hosted Linux, Windows, macOS, and exact-head evidence require branch publication, while merge and release remain owner-controlled actions. | The owner explicitly expands or narrows external authority at send-off. |
| P17-R3-27 | Stop only for missing credentials or authority, sustained external-service failure, unavailable newly required hardware, destructive ambiguity involving user work, or a contradiction requiring a scientific-claim or scope change. Ordinary engineering difficulty, test failures, budget misses, or QA defects are not stop conditions. | This gives the autonomous phase clear fail-closed boundaries without requiring oversight for recoverable implementation work. | A new safety or repository constraint creates another genuine external blocker. |
| P17-R3-28 | Phase 17 closes only when one exact qualifying content tree passes all package and integration tests, model oracles, API and internal-use scans, strict root and ProcessBigraphs documentation builds, macOS/Linux/Windows smokes, browser automation, accessibility, visual and performance budgets, three persona reviews, and the terminal browser-agent gate. The ProcessBigraphs documentation score must be at least 92/100 with no category below 8/10. | Completion must describe one coherent, tested product rather than a collection of individually green but mismatched artifacts. | A later accepted qualification contract supersedes Phase 17. |

## Required 35-page information architecture

The normative specification may refine page titles but not remove these outcomes.

### Home

1. ProcessBigraphs

### Learn

1. Install and verify the internal beta
2. The process-bigraph mental model
3. Your first multirate composite
4. Stores, ports, schemas, and updates
5. Compose and inspect a system
6. Logical time, scheduling, and publication
7. Write processes, steps, and observers
8. Integrate adapters and solvers
9. Change structure transactionally
10. Checkpoint, fail, restore, and replay

### Examples

1. Example gallery
2. Pulse and decay
3. Reusable nested composites
4. N-way junctions
5. SciML field adapter
6. Independent custom engine adapter
7. Divide, fail, and recover

### Scientific Case Studies

1. Scientific case-study boundary
2. Wortel 2021 — qualified source-bounded case study
3. Merks 2006 — qualified source-bounded case study

### Concepts and Guarantees

1. Architecture and compute ownership
2. Canonical structure and semantic identity
3. Logical state, effects, and reconciliation
4. Time, schedules, and visibility
5. Hierarchy and open composition
6. Dynamic structural transactions
7. Engines, adapters, and heavy computation
8. RNG, observation, checkpoints, and replay
9. Capability status, migration, and troubleshooting

### API

1. User authoring API
2. Semantic values, schemas, schedules, and effects
3. Process, step, observer, runtime, and checkpoint API
4. Composition and structure API
5. Extension protocols, experimental surface, and compatibility index

## Browser-agent closure protocol

The normative browser protocol must preserve this order:

1. Build the exact candidate site locally from the pinned package-local docs
   environment.
2. Run the ProcessBigraphs documentation contract checker.
3. Run strict Documenter with no warnings.
4. Run internal-link, external-link, DOM, Playwright cross-browser,
   accessibility, accessibility-tree, Lighthouse, and pinned visual-regression
   checks.
5. Confirm root Potts documentation still passes its independent quality
   contract.
6. Confirm macOS, Linux, and Windows clean-install/documentation smokes.
7. Serve the exact built site locally without mutating qualifying paths.
8. Run the complete browser-agent journey at all required viewports and themes.
9. Repair every finding and restart from the earliest affected deterministic
   gate.
10. Record content-addressed evidence and commit only permitted attestation
    metadata.
11. Recompute and compare the final qualifying content-tree digest.
12. Perform the terminal exact-content browser check without further tracked
    qualifying changes.

The record must identify the review as browser-agent and auditor led. It must not
be represented as external usability research, a human accessibility audit, or
an observed user study.

## Autonomous phase and commit shape

The implementation plan must define reviewable commits or commit groups for:

1. baseline merge and Phase 17 contract freeze;
2. ProcessBigraphs and CorePotts public-boundary closure;
3. Wortel and Merks downstream model migration;
4. package-local documentation system and manual;
5. scientific case studies and visual evidence;
6. deterministic browser, accessibility, performance, and visual QA;
7. qualification repairs; and
8. content-addressed evidence and closure metadata.

These are subgates and commit boundaries within one Phase 17 branch, not separate
product phases or separate implementation branches.

## Explicit nonclaims

Round 3 does not admit:

- ProcessBigraphs public release or registry publication;
- stable 1.x compatibility;
- complete pinned Process-Bigraph parity;
- Dagger, distributed, or alternate-executor qualification;
- broad biochemical, FBA, SBML, or whole-cell ecosystems;
- CNV case-study polish;
- Wortel Figure 2 reproduction;
- Merks Figure 5 morphometry or ensemble reproduction;
- source-author endorsement;
- external user-study evidence;
- a human WCAG conformance audit; or
- authority to merge the Phase 17 pull request.

## Owner disposition

The project owner accepted all 28 Round 3 recommendations without amendment on
2026-07-29.

The complete three-round owner interview is now closed. The next authorized work
is specification authoring only. Implementation begins only after the owner
reviews the Phase 17 specification packet and gives an explicit send-off.
