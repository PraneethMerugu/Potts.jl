# Documentation Interview Round 2

Date: 2026-07-27

Participants: project owner, Codex documentation auditor

Baseline: `a6862e7` plus the uncommitted `codex/documentation-redesign` worktree

Status: accepted

## Decisions

| ID | Decision | Rationale | Owner | Revisit trigger |
|:--|:--|:--|:--|:--|
| DOC-R2-01 | The required gallery contains Relaxing Cell, Two Populations Sort, Follow the Gradient, Grow/Divide/Retire, Elongated Network, Fluctuating Droplet, Boundaries and Obstacles, Same Model in 2D and 3D, Stop and Resume, and Reproducible Ensemble. | These ten examples cover the stable non-Phase-16 scientific and research workflow without inventing unsupported mechanisms. | Project owner | Stable capability or audience scope changes |
| DOC-R2-02 | Persistent Wanderer and the patrol example become required only if Round 3 classifies the Act facade as stable. | The documentation portfolio must follow API stability rather than creating stability by presentation. | Project owner | Act stability is decided or changed |
| DOC-R2-03 | The patrol example is titled “Selective Migration Through a Dense Monolayer” and makes no validated immune-cell claim. | Neutral framing preserves the useful multicellular teaching pattern without implying biological validation. | Project owner | A separately validated biological model is admitted |
| DOC-R2-04 | Competitor-informed examples use clean original PottsToolkit implementations and cite teaching inspiration without line-by-line translation. | Original implementations fit PottsToolkit semantics and minimize licensing and accidental-parity risk. | Project owner | An adaptation is demonstrably preferable and passes DOC-R2-05 |
| DOC-R2-05 | MIT-licensed adaptation requires exact file, revision, license, notice, and modification records; CC3D material requires file-level license approval. | Repository-level availability is not sufficient provenance for every source or asset. | Project owner | Legal/provenance policy is superseded |
| DOC-R2-06 | Sorting, migration, division, and network formation receive animations; other examples use deterministic figures and traces. | Motion is used only when it materially teaches temporal behavior. | Project owner | Usability testing shows another output type is necessary |
| DOC-R2-07 | Fast examples target 15 seconds each and five minutes for the complete warm documentation suite; expensive media has a 30-minute per-artifact ceiling and runs separately. | The budget keeps pull-request feedback bounded without constraining reproducible media generation unnecessarily. | Project owner | CI capacity or example complexity changes materially |
| DOC-R2-08 | Mechanism names require quantitative assertions; “equilibrium,” “reproduction,” and “backend agreement” require their separate evidence gates. | Visual plausibility and successful execution are not scientific qualification. | Project owner | Scientific evidence policy changes |
| DOC-R2-09 | The project owner or a formally delegated science/documentation maintainer approves external adaptations and scientific claim labels. | Approval authority must be explicit and attributable. | Project owner | Maintainer governance changes |
| DOC-R2-10 | The three unreferenced MP4 files are removed after their useful scenarios are replaced by canonical reproducible sources. | Replacement prevents information loss while eliminating unexplained generated binaries. | Project owner | A file is proven to be a licensed canonical source asset |

## Rejected Alternatives

| Alternative | Why rejected |
|:--|:--|
| Require all twelve examples regardless of API stability | Documentation must not make Act stable by relying on it. |
| Present the patrol example as immune-cell validation | The teaching model does not provide that scientific evidence. |
| Translate competitor code directly because it is convenient | API semantics, provenance, and licensing would be harder to audit. |
| Animate every example | It would increase maintenance and runtime without improving every learning objective. |
| Use visual output as the acceptance test | Visual plausibility is weaker than deterministic numerical assertions. |
| Delete the old MP4s immediately | Their scenarios should first be preserved in canonical replacement sources. |

## Open Items

- Round 3 must classify the Act facade and determine whether the two conditional examples enter the
  required gallery.
- Exact stable API coverage rules, ownership, link schedules, visual regression, and the final
  9/10 gate remain for Round 3.

## Changes to the Audit

- the required launch portfolio is fixed at ten examples plus two Act-conditional examples;
- the patrol example receives neutral scientific framing;
- clean original implementation is the default provenance class;
- visual types and runtime budgets are fixed;
- scientific terminology requires explicit evidence;
- media removal is sequenced after canonical replacement.
