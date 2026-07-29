# Documentation Interview Round 3

Date: 2026-07-27

Participants: project owner, Codex documentation auditor

Baseline: `a6862e7` plus the uncommitted `codex/documentation-redesign` worktree

Status: accepted

## Decisions

| ID | Decision | Rationale | Owner | Revisit trigger |
|:--|:--|:--|:--|:--|
| DOC-R3-01 | Every public name is classified as `stable_user`, `stable_extension`, `experimental`, `internal_export`, or `deprecated`. | Classification separates documentation completeness from accidental export breadth. | Project owner | Public API governance changes |
| DOC-R3-02 | `Act` remains experimental while `phase-14-public-api-v2.toml` is `wortel-vertical-slice-provisional`; its two examples remain optional experimental examples. | Strong mechanism evidence does not implicitly promote a provisional API. | Project owner | The Phase 14 API registry explicitly promotes Act |
| DOC-R3-03 | Stable user APIs appear in ordinary pages, stable extension APIs in a developer reference, experimental APIs in a visibly labeled section, and internal exports only package-locally. | Readers should not infer stability from implementation location or export status. | Project owner | Site information architecture changes |
| DOC-R3-04 | `stable_user` and `stable_extension` require 100% docstrings; every public name requires classification; publicly shown experimental names require docstrings and visible status. No whole-package percentage is imposed on internal exports. | The gate protects intentional public contracts without rewarding unnecessary internal-export prose. | Project owner | Stability policy changes |
| DOC-R3-05 | Package maintainers propose classifications and the project owner approves stable promotions; unclassified new exports fail CI. | Classification and promotion need attributable ownership. | Project owner | Maintainer governance changes |
| DOC-R3-06 | Pull requests fail on missing stable documentation, unregistered pages, broken internal links, missing canonical sources, or missing provenance. | These deterministic repository defects are suitable for required CI. | Project owner | Required CI policy changes |
| DOC-R3-07 | Changed external links are reviewed where practical and the complete external-link audit runs weekly. | Full network checks on every pull request would add avoidable flakiness. | Project owner | Reliable hermetic external-link checking becomes available |
| DOC-R3-08 | Numerical assertions are the primary visual-example gate; selected CairoMakie PNGs use tolerant explicit-acceptance regression, while animations are checked through source, metadata, and representative frames. | The policy tests scientific output without byte-locking video encoders. | Project owner | Visual tooling or backend policy changes |
| DOC-R3-09 | API or behavior changes rerun tutorials tagged with affected symbols or capabilities; scientific claims, support labels, adaptations, and golden changes require owner review. | Impact follows declared dependencies and high-risk changes remain intentional. | Project owner | Dependency tracking changes |
| DOC-R3-10 | Project owner approves stable status, package maintainers approve experimental documentation, science/documentation maintainers approve inspired or adapted examples, and published reproduction status follows its independent gate plus owner approval. | Different claims require different authority. | Project owner | Governance changes |
| DOC-R3-11 | The 9/10 gate requires rubric score at least 90, every mandatory gate, fourteen Learn pages, ten required examples, CPU install smokes on macOS, Linux, and Windows, strict Documenter, the registry checker, complete stable API docs, reproducible media, and three audience task reviews. | This combines structural, executable, scientific, and usability evidence. | Project owner | A later accepted audit supersedes the rubric |
| DOC-R3-12 | The executable mechanism is one TOML specification, one Julia checker, and focused fixtures; no custom documentation framework. | Existing Documenter and package tests already own rendering and behavior. | Project owner | The minimal mechanism proves insufficient |

## Rejected Alternatives

| Alternative | Why rejected |
|:--|:--|
| Promote Act because its vertical slice passed | The public API registry still explicitly labels the surface provisional. |
| Require 95% coverage across every CorePotts export | It would encourage documenting internal exports as accidental public promises. |
| Hide experimental APIs | A visible experimental section is more useful and honest. |
| Run all external-link checks on every pull request | Network instability would make required CI flaky. |
| Byte-compare animations | Encoder and metadata variation is not the scientific or visual contract. |
| Build a custom documentation quality service | TOML, Julia, Documenter, and existing tests are sufficient. |

## Open Items

No interview decision remains open. The documentation quality specification may now be implemented.
It will report incomplete target content until remediation is finished.

## Changes to the Audit

- Act is experimental and the required gallery remains ten examples;
- stable and extension documentation coverage is fixed at 100%;
- all public names require classification;
- deterministic pull-request and scheduled network checks are separated;
- visual regression and change-impact policies are fixed;
- final quality gates and approval authorities are fixed;
- executable implementation is bounded to one TOML file, one checker, and fixtures.
