# ProcessBigraphs Phase 17 Owner Interview — Round 1

Date: 2026-07-29

Participants: project owner, Codex architecture and documentation auditor

Research baseline: qualified Phase 16 and semantic-preserving consolidation on `origin/main`

Status: accepted

## Scope of this round

Round 1 fixes the product boundary, maturity claim, audiences, documentation ownership,
information architecture, scientific-model content class, model portfolio, quality target, and
explicit exclusions for one autonomous phase. It does not yet freeze exact public API names,
compatibility actions, model source placement, migration mechanics, or qualification commands.
Those belong to Rounds 2 and 3.

## Research basis

The accepted ProcessBigraphs architecture establishes an independent, domain-neutral Julia
runtime. ProcessBigraphs owns orchestration, logical state, reconciliation, publication, failure,
observation, checkpoints, and replay; CorePotts and injected solvers own authorized heavy
scientific computation. ProcessBigraphs remains an unpublished internal beta until complete pinned
parity and a whole-cell-style acceptance composite pass.

The current Potts manual has a separately qualified documentation contract with a progressive
learning path, visible executable programs, strict Documenter builds, public-name
classification, cross-platform clean-install evidence, quantitative example assertions,
reproducible visual output, and audience task reviews. That contract deliberately excludes
ProcessBigraphs publication. ProcessBigraphs currently has package-local internal-beta prose but
not an independent Documenter site or a comparable product-quality gate.

Primary external research supports a layered manual. Process-Bigraph presents typed stores,
processes, composites, and orchestration as a composition protocol and teaches basics before
wrapping an external solver and presenting an end-to-end reference application. Scientific Julia
documentation similarly separates newcomer workflows, end-to-end examples, conceptual material,
and developer/API reference.

The qualified Merks implementation is a runnable source-bounded assembly, not the paper's full
Figure 5 ensemble or morphometry analysis. The qualified Wortel evidence proves the reusable
Act-CPM mechanism and its CPU/Metal/ROCm execution, but not the paper's complete parameter study or
Figure 2 result. Neither model currently satisfies the accepted Published Models reproduction
contract.

## Accepted decisions

| ID | Decision | Rationale | Revisit trigger |
|:--|:--|:--|:--|
| P17-R1-01 | Create one **Phase 17: ProcessBigraphs Model and Documentation Productization**, ordered through subgates 17.A–17.F. | One bounded phase can freeze contracts, close public authoring gaps, migrate the two models, build the manual, and qualify the exact tree without fragmenting product ownership. | A required dependency cannot be qualified inside the phase without materially broadening scope. |
| P17-R1-02 | ProcessBigraphs remains a **qualified unpublished internal beta** throughout Phase 17. | Documentation and usability do not satisfy the existing pinned-parity and whole-cell public-release gates. | A later release decision closes the independent release prerequisites. |
| P17-R1-03 | Publish a versioned development manual with a persistent internal-beta banner and repository-install instructions. | Publicly readable development documentation improves usability without representing a package registry release or 1.0 promise. | Public documentation is shown to create unavoidable release confusion that cannot be corrected through explicit status presentation. |
| P17-R1-04 | Build an independent package-local ProcessBigraphs Documenter site; the Potts manual links to runtime-backed workflows without duplicating the runtime manual. | This preserves independent package identity, documentation ownership, and the existing Potts documentation contract. | Repository separation or documentation hosting architecture changes. |
| P17-R1-05 | Audience priority is scientific model composer, adapter/solver author, reproducibility researcher, runtime contributor, then domain user consuming an existing model. | The runtime's primary value is composing heterogeneous scientific processes; the learning path should lead with that task rather than implementation internals. | Observed user research identifies a materially different primary audience. |
| P17-R1-06 | The first-session outcome is a multirate pulse-and-decay composite with typed shared state, independent schedules, an observation trace, a composition diagram, and exact checkpoint/restart. | This is fast and domain-neutral while demonstrating the runtime's distinguishing orchestration, visibility, and persistence behavior. | The admitted API cannot express the example without introducing a toy-only special case. |
| P17-R1-07 | Navigation is Home, Learn, Examples, Scientific Case Studies, Concepts and Guarantees, and API. | The structure separates progressive teaching, reusable programs, bounded scientific assemblies, semantic explanation, and reference material. | Rendered task review demonstrates a clearer information architecture. |
| P17-R1-08 | Add the visible content class **Qualified Source-Bounded Case Study**. | It truthfully distinguishes a source-traced, qualified runnable assembly from both a teaching example and a completed qualitative or quantitative reproduction. | The published-model evidence contract admits the model at a stronger status. |
| P17-R1-09 | Wortel receives a high-level ProcessBigraph assembly, a versioned source-trace registry, and one bounded declared configuration. The 51-parameter/30-seed Figure 2 study and reproduction claims remain excluded. | Current evidence proves Act mechanics and backend execution, not the full paper study. | A separately preregistered reproduction phase is authorized. |
| P17-R1-10 | Merks retains its canonical 500×500 qualification. Documentation uses a visibly labeled reduced CPU profile; full-size evidence and media remain separate reproducible workflows. | Pull-request documentation must stay bounded without presenting the reduced profile as the source configuration. | The canonical model becomes fast enough for ordinary documentation CI without weakening other budgets. |
| P17-R1-11 | CNV remains visible in capability and architecture material but does not receive a polished Phase 17 case study. | The requested showcase portfolio is Wortel and Merks; adding CNV polish would broaden the phase without closing the identified usability gap. | The owner explicitly amends the Phase 17 portfolio. |
| P17-R1-12 | ProcessBigraphs receives its own documentation contract scoring at least 90/100 and requiring strict Documenter, visible executable programs, complete intentional API classification, complete admitted user/extension docstrings, macOS/Linux/Windows clean smokes, reproducible visuals, and three audience task reviews. | Matching the existing documentation quality requires executable, API, platform, scientific, visual, and usability evidence rather than page count alone. | A later accepted documentation audit supersedes the rubric. |
| P17-R1-13 | Phase 17 excludes public release, complete parity, Dagger/distributed execution, broad biochemical/FBA/SBML work, CNV case-study polish, quantitative paper reproduction, and whole-cell qualification. | These features have separate prerequisites and would make the phase scientifically and operationally unbounded. | An explicit owner-approved scope amendment includes a dependency and claim-impact plan. |
| P17-R1-14 | Every required tutorial and case-study source is a tested internal-beta interface. Breaking one requires an intentional API disposition and migration note. | Tutorial reliability is part of product quality even before 1.0, while the internal-beta label still permits reviewed evolution. | A later formal versioning policy supersedes this rule. |

## Phase shape accepted in principle

- **17.A — Contract freeze:** interviews, decision, normative specification, entry registry, API
  inventory, documentation-quality contract, model claim records, implementation plan, and
  qualification ledger.
- **17.B — Public boundary closure:** admit only the smallest model- and adapter-authoring surface
  needed by qualified downstream programs.
- **17.C — Model migration:** implement downstream-only Merks and Wortel assemblies through the
  admitted surface and preserve bounded behavior and evidence.
- **17.D — Manual:** build the independent ProcessBigraphs learning, concept, example, and API
  manual.
- **17.E — Case studies:** publish the source-bounded model narratives, reduced executable
  profiles, supported visuals, and links to full qualification evidence.
- **17.F — Reconciliation and attestation:** run all required package, integration,
  documentation, platform, performance, compatibility, and exact-head gates and close the phase.

## Explicit non-decisions

Round 1 does not decide:

- exact new function or type names;
- which existing qualified-only names become exported;
- whether model source lives in PottsToolkit, a dedicated examples project, or another downstream
  package boundary;
- compatibility-alias retention or removal;
- exact documentation page counts and runtime budgets;
- exact visual artifacts;
- exact CI command topology;
- performance thresholds;
- commit and attestation sequence; or
- autonomous stop conditions.

These questions remain open for researched Rounds 2 and 3.

## Owner disposition

The project owner accepted every Round 1 recommendation without amendment on 2026-07-29.
