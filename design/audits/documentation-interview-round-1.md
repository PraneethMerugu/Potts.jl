# Documentation Interview Round 1

Date: 2026-07-27

Participants: project owner, Codex documentation auditor

Baseline: `a6862e7` plus the uncommitted `codex/documentation-redesign` worktree

Status: accepted

## Decisions

| ID | Decision | Rationale | Owner | Revisit trigger |
|:--|:--|:--|:--|:--|
| DOC-R1-01 | Audience priority is biologist/CPM newcomer, model builder/reproducibility user, extension author, then backend specialist. | The manual must teach scientific modeling before implementation detail while retaining a clear advanced path. | Project owner | Target audience or product positioning changes |
| DOC-R1-02 | The first-session outcome is a single cell relaxing toward target volume with a before/after rendering and deterministic volume trace. | It is visually legible, scientifically bounded, fast, and demonstrates model, execution, observation, analysis, and visualization. | Project owner | The stable first-run API cannot support the bounded example |
| DOC-R1-03 | Visualization is optional for headless execution but included in the normal first-session path. | Headless use remains supported while most new users receive immediate visual feedback. | Project owner | MakiePotts installation or first-use cost becomes incompatible with the beginner path |
| DOC-R1-04 | CPU installation is documented for macOS, Linux, and Windows; GPU setup remains in separate backend guides. | The beginner path must be portable and GPU setup must not block first use. | Project owner | Supported platform policy changes |
| DOC-R1-05 | GPU use is an advanced research workflow, not a learning prerequisite. | Backend complexity should appear only after the scientific workflow is understood. | Project owner | GPU becomes the ordinary default execution path |
| DOC-R1-06 | Unsupported and experimental capabilities remain visible in a capability matrix with explicit status. | Honest negative documentation prevents roadmap intention from being mistaken for support. | Project owner | Capability classification system changes |
| DOC-R1-07 | Published Models remains visible with an admission/status table even while no model is admitted. | An honest empty portfolio is preferable to hiding the reproduction standard or misclassifying examples. | Project owner | The portfolio information architecture changes |
| DOC-R1-08 | Tutorials are tested public interfaces; breaking one requires migration notes and an intentional compatibility decision. | Tutorials must be dependable entry points rather than disposable examples. | Project owner | A formal versioning policy supersedes this rule |

## Rejected Alternatives

| Alternative | Why rejected |
|:--|:--|
| Lead with CorePotts extension authors | It would optimize the main learning path for a secondary audience. |
| Require visualization for all execution | It would weaken headless, CI, and remote workflows. |
| Include GPU setup in installation | It would add platform-specific complexity before the first scientific result. |
| Hide unsupported or empty sections | It would make product limitations and admission requirements harder to discover. |
| Treat tutorial breakage as ordinary documentation maintenance | It would allow the primary user workflow to drift without an explicit compatibility decision. |

## Open Items

No Round 1 item remains open. Example selection, visual type, runtime budgets, scientific language,
external adaptation, and stale-media disposition belong to Round 2.

## Changes to the Audit

- audience order is now owner-approved;
- the first-session example is fixed as Relaxing Cell;
- cross-platform CPU installation is mandatory;
- GPU documentation is an advanced path;
- the capability matrix and empty Published Models status remain visible;
- tutorials receive an explicit tested-interface compatibility policy.
