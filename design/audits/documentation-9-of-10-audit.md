# Documentation 9/10 Audit — Non-Phase-16 Scope

Status: implementation audit; numeric 9/10 target met, cross-platform release gate pending

Audit date: 2026-07-27

Implementation snapshot: current `codex/documentation-redesign` worktree

Excluded implementation scope: all Phase 16 hierarchy, structural-transaction, and adapter
behavior except the documentation handoff rule

Interview status: Rounds 1–3 accepted; see
[Documentation Interview Round 1](documentation-interview-round-1.md) and
[Documentation Interview Round 2](documentation-interview-round-2.md), and
[Documentation Interview Round 3](documentation-interview-round-3.md)

## Decision Summary

The redesigned manual now scores **91/100** against the accepted rubric, up from the audited
baseline of **62/100**. The score is calibrated to user outcomes rather than page count: fourteen
guided tutorials, ten quantitative examples, classified API references, reproducible media, and
three rendered-site task walkthroughs are implemented.

The documentation is not release-gate complete yet. The clean macOS CPU installation smoke passes,
but the accepted gate also requires Linux and Windows evidence produced by the CI matrix. The
numeric score therefore records the quality of the implementation; it does not override those two
missing platform results.

The route to 9/10 is not to document every exported implementation name or write more disconnected
prose. It is to:

1. establish one progressive biology-first learning path;
2. create an original, visual, executable example gallery covering the stable engine;
3. classify the public API and document the supported surface by subsystem;
4. teach complete analysis, restart, backend, and research workflows;
5. add a small number of durable documentation checks to existing CI; and
6. encode the accepted audience, example, claim, and maintenance decisions in one TOML
   specification and one Julia checker.

This is intentionally narrower than a documentation platform project. Documenter remains the site
generator. Julia sources remain the executable authority. No custom database, content service, or
second documentation framework is warranted.

## Accepted Product Direction

Round 1 freezes these requirements:

- audience priority is biologist/CPM newcomer, model builder/reproducibility user, extension
  author, then backend specialist;
- the first session produces a relaxing cell, a deterministic volume trace, and before/after
  rendering;
- visualization is optional for headless use but part of the normal beginner path;
- CPU installation covers macOS, Linux, and Windows;
- GPU documentation is an advanced research path;
- unsupported and experimental capabilities remain visible in a status matrix;
- Published Models remains visible with an admission/status table while empty;
- tutorials are tested public interfaces whose breakage requires migration notes and an
  intentional compatibility decision.

Round 2 freezes these requirements:

- ten examples are required; Persistent Wanderer and Selective Migration Through a Dense Monolayer
  are conditional on stable Act classification;
- competitor-informed examples use clean original PottsToolkit implementations by default;
- adaptations require file-level provenance, license, notices, and approval;
- only sorting, migration, division, and network formation require animation;
- fast examples target 15 seconds each and the warm suite targets five minutes;
- expensive media runs separately with a 30-minute per-artifact ceiling;
- scientific mechanism names require quantitative assertions, while equilibrium, reproduction,
  and backend agreement retain their independent evidence gates;
- the three unreferenced MP4s are removed only after canonical sources replace their scenarios.

Round 3 freezes these requirements:

- all public names use one of five API classifications;
- Act remains experimental while its accepted registry status is provisional, leaving the required
  gallery at ten examples;
- stable user and extension APIs require complete docstrings, while internal exports do not create
  a whole-package coverage target;
- deterministic documentation defects fail pull requests and the complete external-link audit runs
  weekly;
- selected CairoMakie outputs use tolerant visual regression, while animation validation uses
  canonical source, metadata, and representative frames;
- the final gate requires the accepted rubric, structural and executable checks, three clean CPU
  platform smokes, reproducible media, and three audience task reviews;
- implementation is limited to one TOML specification, one Julia checker, and focused fixtures.

## Scope

### Included

- PottsToolkit stable biological authoring;
- CorePotts stable execution, state, observation, persistence, backend, and extension contracts;
- MakiePotts stable render-frame and two-dimensional/slice visualization paths;
- current non-Phase-16 reference models;
- installation, troubleshooting, performance orientation, and contribution paths;
- published-model documentation policy and any independently admitted pre-Phase-16 reproductions;
- documentation CI, provenance, and maintenance ownership.

### Excluded

- unfinished ProcessBigraphs Phase 16 behavior;
- dynamic structural transactions and hierarchy tutorials;
- Potts adapter behavior that has not passed its slice gate;
- Phase 17 biochemical/FBA ecosystem documentation;
- claims unsupported by current conformance or evidence;
- producing new scientific qualification merely to make a documentation page look complete.

The manual may state that an excluded capability is unavailable or in development. It may not
teach roadmap behavior as if it were implemented.

## Evidence Snapshot

### Baseline and current manual

| Measure | Audited baseline | Current implementation |
|:--|--:|--:|
| Curated Markdown pages | 19 | 42 |
| Approximate prose words | 4,435 | 9,732 |
| Learn pages | 4 | 14 |
| Canonical executable examples | 3 | 10 |
| Documenter `@example` blocks | 19 | 27 |
| Generated gallery assets | 0 | 10 |
| Required animations | 0 | 4 actual-state animations with quantitative traces |
| Published-model reproductions | 0 | 0 |
| Tracked, uncurated MP4 files | 3 | 0 |
| Strict Documenter build | Passing | Passing |
| Clean CPU installation evidence | None | macOS passed; Linux/Windows pending |
| Rendered-site audience reviews | None | 3 passed, auditor-led |

The navigation uses Learn, Examples, Published Models, Concepts and Guarantees, and API. The strict
build executes doctests and examples, resolves cross-references, and renders HTML with
`warnonly = false`. Canonical tutorial and example sources execute independently of the prose,
while the media manifest verifies source paths, generation commands, accessible descriptions, and
output checksums.

### API documentation coverage

Coverage was measured with `Docs.undocumented_names(module; private = false)` against public names.
This is a broad diagnostic, not itself a stability classification.

| Package | Public names | Undocumented | Approximate coverage |
|:--|--:|--:|--:|
| PottsToolkit | 246 | 29 | 88.2% |
| CorePotts | 768 | 351 | 54.3% |
| MakiePotts | 75 | 0 | 100% |

These counts remain the historical diagnostic that motivated classification. The current reference
uses the Phase 13, Phase 14, and MakiePotts inventories to separate stable user, stable extension,
experimental, and internal-export surfaces. Stable reference pages are filtered by those
inventories; experimental names appear on a separately labeled page.

### CI behavior

The build is strict for executable blocks, doctests, cross-references, and Documenter errors.
Three deliberate blind spots remain:

- `checkdocs = :none` does not enforce documented-name coverage;
- `pagesonly = true` ignores unlisted Markdown;
- HTML size warning and failure thresholds are disabled.

`pagesonly = true` is appropriate for a curated manual. `checkdocs = :none` should eventually be
replaced by a stability-aware coverage check rather than Documenter's all-exported-name rule.

## 9/10 Rubric

The rubric totals 100 points. A 9/10 manual scores at least 90 overall and meets every mandatory
gate; strengths in one category cannot hide a failed installation or scientific-claim gate.

| Category | Weight | Baseline | Current | 9/10 target | Current evidence |
|:--|--:|--:|--:|--:|:--|
| Accuracy and scientific boundaries | 15 | 14 | 15 | 15 | Capability matrix, bounded claims, and Phase 16 exclusion agree with accepted inventories |
| Guided learning path | 18 | 10 | 16 | 16 | Fourteen executable pages cover install through research workflow; beginner walkthrough passed |
| Example portfolio | 15 | 7 | 13 | 13 | Ten original or concept-inspired sources have deterministic quantitative checks and gallery results |
| API and extension reference | 14 | 8 | 13 | 13 | Stable surfaces are inventory-filtered, experimental API is separate, and extension walkthrough passed |
| Research and reproducibility workflows | 12 | 6 | 10 | 10 | Typed analysis, checkpoint equality, seed policy, ensemble, archive, and bounded interpretation are taught |
| Visual communication | 8 | 3 | 7 | 7 | Ten reproducible SVG assets include four reviewed actual-lattice animations, quantitative traces, alt text, and reduced-motion fallbacks |
| Navigation and problem solving | 8 | 7 | 8 | 8 | Audience routes, progressive Learn order, status matrix, troubleshooting, and task-oriented API navigation are present |
| CI and maintainability | 10 | 7 | 9 | 9 | Strict build, canonical-source registry, API classification, media hashes, evidence files, and CI matrix are enforced |
| **Total** | **100** | **62** | **91** | **91** | |

The three task reviews were auditor-led rendered-site walkthroughs, not external-user studies. Their
evidence records state this limitation explicitly. That is sufficient for the accepted executable
gate and leaves a genuine external usability round as useful follow-up rather than fabricated
evidence.

### Mandatory gates

A numeric score cannot override these gates:

1. documented installation works from a clean supported environment;
2. every fast tutorial and example executes from canonical source in CI;
3. no page claims unsupported backend or scientific qualification;
4. stable user and extension API docstrings are complete and every public name is classified;
5. every external-derived example has recorded provenance and license disposition;
6. generated media is reproducible and not committed as an unexplained binary;
7. no Phase 16 capability appears as supported before its gate;
8. a novice, a model builder, and an extension author can each complete their critical-path task.

Current gate status:

| Gate | Status |
|:--|:--|
| Strict build and executable fast sources | Passed locally |
| Scientific, backend, provenance, media, API, and Phase 16 checks | Passed locally |
| macOS clean CPU installation | Passed |
| Linux clean CPU installation | Pending CI evidence |
| Windows clean CPU installation | Pending CI evidence |
| Beginner, model-builder, and extension-author walkthroughs | Passed; auditor-led limitation recorded |

## Surface-by-Surface Findings

| Surface | Current quality | Strongest property | Remaining gap |
|:--|:--:|:--|:--|
| Home and orientation | 9/10 | Audience routes, visible result, support boundary, and gallery entry | External-user observation could refine wording |
| Learn | 9/10 | Complete executable path from installation through a bounded research study | Publication-scale variants remain deliberately out of scope |
| Examples | 9/10 | Ten canonical quantitative examples with reproducible visual results | Act examples remain correctly deferred while provisional |
| Published Models | 8/10 | Empty portfolio is paired with a visible status matrix and a strict admission contract | First entry requires a separately reviewed scientific reproduction |
| Concepts and Guarantees | 9/10 | Architecture, status, algorithms, observation, reproducibility, and troubleshooting are explicit | More domain-specific troubleshooting can grow from real reports |
| PottsToolkit reference | 9/10 | Stable authoring surface is inventory-filtered and task-linked | Inventory ownership must remain part of API review |
| CorePotts reference | 9/10 | Stable extension protocols and experimental names are visibly separated | More worked third-party extension examples would help mature ecosystems |
| MakiePotts reference | 9/10 | Stable filtered reference is paired with complete visualization and export workflows | Tolerant image regression remains a future refinement |
| Installation and operations | 8/10 | Direct dependencies, verification, matrix, performance guidance, and troubleshooting are documented | Linux and Windows clean-smoke results are still pending |
| Documentation maintenance | 9/10 | Strict build, source registry, API inventories, media hashes, task evidence, and CI gates are encoded | Weekly operation and cross-platform results require the hosted workflow |

The Concepts section is already near the desired standard. Rewriting it again would provide less
value than finishing Learn, Examples, API classification, and operations.

## External Benchmark

The benchmark is about teaching patterns, not API parity or literal source reuse.

### CellularPotts.jl

Official sources reviewed:

- [documentation home and gallery](https://robertgregg.github.io/CellularPotts.jl/dev/);
- [Hello World](https://robertgregg.github.io/CellularPotts.jl/dev/ExampleGallery/HelloWorld/HelloWorld/);
- [Let's Get Moving](https://robertgregg.github.io/CellularPotts.jl/dev/ExampleGallery/LetsGetMoving/LetsGetMoving/);
- [On Patrol](https://robertgregg.github.io/CellularPotts.jl/dev/ExampleGallery/OnPatrol/OnPatrol/);
- [Bringing ODEs To Life](https://robertgregg.github.io/CellularPotts.jl/dev/ExampleGallery/BringingODEsToLife/BringingODEsToLife/);
- [Going 3D](https://robertgregg.github.io/CellularPotts.jl/dev/ExampleGallery/Going3D/Going3D/);
- [repository and MIT license declaration](https://github.com/RobertGregg/CellularPotts.jl).

Patterns worth adopting:

- inviting, biology-oriented example names;
- a visual gallery that lets users select by outcome rather than API name;
- progressive composition: one cell, movement, multiple populations, coupling, then 3D;
- canonical source transformed into documentation with Literate.jl;
- visible evaluated values near the code that produced them;
- a complete animation at the end of a short example;
- direct source/edit links.

Patterns not to reproduce:

- tutorials and examples serving the same role without an explicit distinction;
- examples that rely on hidden defaults or unseeded randomness;
- visual success standing in for a quantitative or scientific acceptance claim;
- a thin API page without stability classification;
- expensive animation as the only proof that the source still works.

CellularPotts.jl's MIT license permits reuse under its terms, but the preferred approach here is an
original implementation of the teaching idea against PottsToolkit semantics. If any source is
adapted rather than independently written, preserve the required notice and record exact source
revision, files, license, and modifications.

### CompuCell3D

Official sources reviewed:

- [CompuCell3D 4.9 manuals index](https://compucell3d.org/Manuals);
- [CompuCell3D 4.9 reference manual](https://compucell3dreferencemanual.readthedocs.io/en/latest/);
- [CompuCell3D developer manual](https://compucell3ddevelopersmanual.readthedocs.io/en/master/);
- [QuickModels visual examples](https://compucell3d.org/QuickModels);
- [CompuCell3D source repository and demos link](https://github.com/CompuCell3D/CompuCell3D).

Patterns worth adopting:

- separate user, how-to, real-world, and developer material;
- problem-oriented pages such as mitosis, growth, cell death, chemotaxis, parameter scans, and
  restarts;
- small visual answers linked to a downloadable complete project;
- explicit prerequisites for advanced extension material;
- broad example coverage that demonstrates what the system can express;
- visible caveats when a model is preliminary, uncalibrated, or only a starting point;
- workshop-style sequences that build skills over multiple sessions.

Patterns not to reproduce:

- fragmented current and legacy manuals with overlapping ownership;
- version-mixed examples;
- downloadable archives without executable CI or canonical source;
- GUI instructions as the only usable path;
- model breadth without machine-readable provenance and evidence.

The CC3D website and manuals display copyright and trademark notices, while the exact repository
and demo licensing can vary by file or distribution. No CC3D text, image, archive, or source should
be imported until file-level license and attribution are recorded. Concepts and task selection can
inform original examples without copying protected expression.

## Implemented Documentation Architecture

The five top-level sections remain. The change is depth and source ownership.

### Learn: 14-page guided sequence

| Order | Page | Outcome | Fast CI |
|--:|:--|:--|:--:|
| 1 | Install and verify | Install all selected packages and run a diagnostic | Yes |
| 2 | Cellular Potts concepts | Understand lattice, owners, energy/work, MCS, and temperature | Yes |
| 3 | First simulation | Build, preflight, run, and inspect one cell | Yes |
| 4 | Compose a biological model | Use identities, declarations, validation, reports, and fingerprints | Yes |
| 5 | Domains and initialization | Choose topology, boundaries, layouts, capacity, and overlap policy | Yes |
| 6 | Adhesion and mechanics | Use volume, surface, elongation, connectivity, and contact laws | Yes |
| 7 | Fields and chemotaxis | Bind a prescribed field and interpret response/mode choices | Yes |
| 8 | Rules and lifecycle | Add properties, schedules, growth, transition, division, and death | Yes |
| 9 | Algorithms and guarantees | Select algorithms without conflating compatibility and evidence | Yes |
| 10 | Observe and analyze | Request typed observables, create tables, and preserve identity | Yes |
| 11 | Checkpoint and reproduce | Capture, restore/import, seed ensembles, and record manifests | Yes |
| 12 | Visualize and export | Build frames, figures, legends, channels, and bounded recordings | Yes |
| 13 | Backends and performance | Preflight CPU/GPU, interpret transfers, and benchmark responsibly | Yes |
| 14 | Complete research workflow | Run a small preregistered study from model to archived result | Yes |

Advanced extension authoring belongs in a separately labeled guide or CorePotts developer section,
not in the biology-first sequence.

### Examples: original gallery

The gallery borrows the successful outcome-first organization of CellularPotts.jl and the task
breadth of CC3D. Names and implementations remain original.

| Example | Stable mechanisms | Visual/result | External teaching analogue | Disposition |
|:--|:--|:--|:--|:--|
| Relaxing Cell | volume, adhesion, one cell | initial/final shape and volume trace | Hello World / basic CC3D | Build |
| Two Populations Sort | pairwise adhesion | segregation metric and animation | CC3D cell sorting | Expand current |
| Follow the Gradient | prescribed field, chemotaxis | trajectory and displacement | CC3D chemotaxis / Over Here | Expand current |
| Persistent Wanderer | Act activity | track and persistence plot | Let's Get Moving | Conditional on stable Act classification |
| Selective Migration Through a Dense Monolayer | two populations, selective activity | paths through dense layer | On Patrol | Conditional on stable Act classification; neutral biological framing |
| Grow, Divide, Retire | rules and lifecycle | lineage/population plot | CC3D mitosis/death | Expand current |
| Elongated Network | elongation, connectivity | morphology and caveat | angiogenesis-style demos | Build from reference model |
| Fluctuating Droplet | mechanical noise, contact energy | distribution and trace | generic CPM droplet | Build from reference model |
| Boundaries and Obstacles | mixed boundaries, fixed exterior | side-by-side outcomes | Tight Spaces / CC3D wall tasks | Build |
| Same Model in 2D and 3D | dimension-generic authoring | 2D image and 3D slice/volume | Going 3D | Build |
| Stop and Resume | canonical checkpoint | uninterrupted/restarted equality | CC3D restart | Build |
| Reproducible Ensemble | seed policy, typed observations | aggregate with uncertainty | CC3D parameter scan | Build |

### Deferred examples

These should not be created merely because competitors show them:

- dynamic extracellular diffusion until its non-Phase-16 public authoring/execution path is
  stable and supported;
- intracellular ODE coupling until the user-facing continuous-system surface is admitted;
- SBML/network solvers, which are Phase 17 scope;
- dynamic hierarchy and structural rewriting, which are Phase 16 scope;
- published-model reproductions without their independent evidence gate.

An explicit “not yet supported” capability map is better than fictional tutorial coverage.

## Canonical Source Pattern

Each Learn or Example page has one source under:

```text
docs/models/
  tutorials/
  examples/
  shared/
```

A source defines:

- a `build_*` function returning the model/problem;
- a fast `smoke_*` function with deterministic assertions;
- an optional `render_*` function for media;
- a small metadata record identifying page, support level, runtime class, backend, seed, and
  expected outputs.

Documenter includes or generates prose-facing code from that source. Fast smoke assertions run in
ordinary CI. Media generation runs separately and writes an artifact with source commit,
environment, command, and checksum.

Literate.jl is a reasonable implementation option because CellularPotts.jl demonstrates the
single-source workflow, but it is not part of the quality contract. A small tooling spike may
choose annotated Julia generation or explicit Markdown that includes canonical Julia source. The
invariant is that two independently editable copies are forbidden.

## Page Contract

Every tutorial and example should answer:

1. What will the reader build or learn?
2. What prior page or knowledge is required?
3. Which APIs and support levels are used?
4. What scientific mechanism is represented?
5. What defaults materially affect interpretation?
6. What result should appear?
7. What does the result establish—and what does it not establish?
8. Which backend, runtime class, and seed are used?
9. Where is the canonical source?
10. How is the fast check or expensive output reproduced?

Examples additionally record provenance classification:

- `original`;
- `concept_inspired`, with sources and a clean implementation;
- `adapted`, with file-level license and required notice;
- `published_reproduction`, with the separate reproduction contract.

## API Remediation

### Step 1: classify, do not blindly document

Create a curated stability inventory for exported names:

- `stable_user`;
- `stable_extension`;
- `experimental`;
- `internal_export`;
- `deprecated`.

The inventory should identify package, symbol, subsystem, owning page, and documentation
requirement. Stable names require a docstring and subsystem placement. Internal exports must have a
reason to remain exported; otherwise remove them in a normal API change rather than polishing them
into accidental promises.

### Step 2: split CorePotts by task

Replace the single flat reference experience with:

- solving and solution access;
- logical state and identity;
- scientific components;
- algorithms and schedules;
- lifecycle;
- observations;
- semantic RNG;
- persistence;
- backends and compiled execution;
- extension protocols and conformance helpers;
- experimental surfaces.

`@autodocs` may remain as a complete index, but it should not be the primary navigation.

### Step 3: enforce the classified surface

The checker requires:

- 100% docstrings for `stable_user` and `stable_extension`;
- a visible experimental label for `experimental`;
- no unclassified public name;
- no reference to an internal name from Learn or ordinary Examples.

This is more meaningful than enabling `checkdocs = :exports`.

## Visual and Media Remediation

Required visual set:

- one architecture diagram;
- one MCS/observation timeline;
- one lifecycle identity/lineage diagram;
- one algorithm/support matrix;
- one gallery thumbnail for every visual example;
- deterministic figures for each analysis-focused example;
- bounded animation only when temporal behavior is the teaching objective.

Media rules:

- generate from canonical source in a pinned environment;
- record command, source revision, and checksum;
- keep small source assets in `docs/src/assets`;
- store large video/data as artifacts or release assets;
- include accessible alt text and textual result summaries;
- never make a video the only representation of an outcome.

The three baseline MP4 files were uncurated and unreferenced. They were removed after canonical
reproducible sources and manifest-tracked SVG replacements covered their useful scenarios.

## Installation and Operations Gaps

The manual must add:

- installation for PottsToolkit, CorePotts development, and MakiePotts;
- a supported Julia/platform matrix;
- a clean installation verification command;
- “which algorithm?” and “which snapshot policy?” decision guides;
- CPU/GPU capability and evidence matrices;
- troubleshooting for validation, capacity, unsupported backend, unsaved observable, checkpoint
  compatibility, and rendering errors;
- expected compile time versus simulation runtime;
- versioned docs and migration notes.

## Research Workflow Gaps

A complete small study should demonstrate:

1. declare a hypothesis and observable;
2. build and validate the model;
3. pin algorithm, numerical policy, backend, seeds, and environment;
4. preflight the exact combination;
5. run replicates;
6. retain typed observations;
7. compute a predefined statistic;
8. visualize uncertainty;
9. checkpoint or archive as applicable;
10. save fingerprints, manifest, raw results, analysis version, and figure checksum;
11. state the bounded conclusion and limitations.

This tutorial should be small enough for documentation CI in reduced form, with a separate command
for publication-scale replication.

## Prioritized Work Plan

Implementation status at this snapshot:

| Slice | Status |
|:--|:--|
| P0 decision/spec foundation | Complete |
| P1 critical learning path | Complete |
| P2 example and visual portfolio | Complete for the ten required stable examples; provisional Act examples correctly deferred |
| P3 reference and extension path | Complete |
| P4 research and release polish | Content and task reviews complete; Linux/Windows install evidence pending |

### P0 — freeze decisions and prevent regression

1. Preserve the accepted interview records and specification authority.
2. Freeze audience priority, stable API classification policy, example portfolio, and media policy.
3. Add the minimal executable documentation specification.
4. Fix installation coverage and dispose of the stale MP4s.

Exit: no unresolved decision can change the information architecture or invalidate more than two
planned pages.

### P1 — critical learning path

1. Build canonical source infrastructure.
2. Complete Learn pages 1–11.
3. Add the algorithm, observation, and troubleshooting decision guides.
4. Validate clean installation and fast execution.

Exit: a new user can install, model, run, observe, analyze, and restart without reading source.

### P2 — example and visual portfolio

1. Implement the ten required examples in bounded slices.
2. Add the two Act examples only as visibly experimental pages while Act remains provisional.
3. Add deterministic figures and thumbnails.
4. Generate only the animations whose learning objective requires time.
5. Add provenance records.

Exit: every stable non-Phase-16 mechanism has a discoverable original example or an explicit
unsupported/deferred entry.

### P3 — reference and extension path

1. Classify public names.
2. Close stable PottsToolkit/CorePotts/MakiePotts docstring gaps.
3. Split CorePotts reference by subsystem.
4. Add extension prerequisites and one conformance-tested extension walkthrough.

Exit: stable user and extension API docstrings are complete, all public names are classified, and
extension authors can locate the required contracts.

### P4 — research and release polish

1. Complete backend/performance and research-workflow tutorials.
2. Add glossary, migration guide, and external-link checking.
3. Conduct task-based usability review.
4. Admit published models only through their independent scientific gate.

Exit: rubric score is at least 90 and all mandatory gates pass.

## Minimal Executable Specification

The accepted interview decisions are encoded in:

```text
spec/documentation-quality-v1.toml
scripts/check_documentation_quality.jl
```

The TOML should contain only durable, machine-checkable facts:

- required navigation sections and page IDs;
- page records with kind, audience, support level, canonical source, runtime class, and owner;
- example provenance and media records;
- API class mappings and authoritative inventory paths;
- minimum coverage thresholds;
- prohibited Phase 16 feature tags for current public pages;
- required clean-build commands.

The Julia checker does:

1. parse the registry;
2. verify referenced files and unique IDs;
3. verify every curated page is registered and every required page is in navigation;
4. verify canonical sources and provenance records;
5. verify the accepted API inventories, stable docstring evidence, and Phase 14/Makie mappings;
6. delegate live unclassified-export rejection to the registered API commands;
7. reject tracked generated media without an artifact/source record;
8. emit a concise failure report.

Documenter continues to execute examples and validate links. Existing package tests continue to
validate behavior. The checker must not reimplement Markdown parsing, scientific tests, or
Documenter.

## Effort Shape

The work should be planned by independently reviewable slices, not one large documentation PR:

- decision/spec foundation: small;
- canonical source and first three tutorials: medium;
- remaining learning path: medium-to-large;
- example/visual portfolio: large;
- API classification and reference: large;
- research workflow and usability review: medium;
- published-model evidence: separate scientific projects.

The audit does not assign calendar dates because implementation and review capacity have not been
scheduled.

## Risks

| Risk | Control |
|:--|:--|
| Documentation races Phase 16 | Keep Phase 16 excluded and merge only qualified slice handoffs |
| Examples promise unsupported behavior | Capability crosswalk and support label before authoring |
| Competitor examples are copied improperly | Original implementations by default; file-level provenance for adaptations |
| Tutorial code drifts | One canonical source plus fast CI |
| API coverage creates accidental stability | Classify before documenting |
| Animations make CI slow | Separate fast assertions from artifact rendering |
| Rubric becomes bureaucracy | One TOML registry, one checker, existing Documenter |
| Published models consume the docs project | Keep scientific qualification as separately gated work |

## Audit Conclusion

The implementation now reaches the accepted 91/100 quality target. It combines
CellularPotts.jl's approachable executable-gallery pattern with CC3D's task breadth and separate
developer path, while adding stricter provenance, reproducibility, backend, API-classification, and
scientific-claim boundaries. All required content, media, and audience walkthroughs are present.
The only remaining release-gate work is to collect passing Linux and Windows clean-install evidence
from the configured CI matrix.

The three-round interview sequence in
[`documentation-interview-rounds.md`](documentation-interview-rounds.md) is complete. The next
action is to run the hosted cross-platform matrix and retain its Linux and Windows evidence.
