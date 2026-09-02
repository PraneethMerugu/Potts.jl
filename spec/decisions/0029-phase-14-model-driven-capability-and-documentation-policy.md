# Decision 0029: Phase 14 Model-Driven Capability and Documentation Policy

Status: Accepted; project-owner documentation and published-model interview complete

Current disposition: superseded in part by [Decision 0044](0044-pre-g6-cohesion-and-mtk-hardening.md)
for phase order, active authoring API, and documentation timing. Source-bounded model requirements
remain evidence for the G5H preservation and proof-model gates.

Date: 2026-07-24

## Context

The original Phase 14 treated documentation as a migration performed after the scientific API
freeze. That sequence is insufficient for the intended documentation product. The project owner
selected a biology-first manual, 12--15 guided tutorials, and 4--6 published-model
reimplementations, including flagship work associated with James Glazier, Inge Wortel, and Yi
Jiang. The published models are intended to reproduce named paper results as closely as the source
record permits, not merely resemble the papers visually.

An adversarial model audit found that faithful reimplementation may require capabilities beyond the
Phase 13 paper-core surface, including separately configurable spatial roles and attempt budgets,
evolving fields, accepted-copy site history, general per-cell dynamical state, dynamic relationship
graphs, degradable structures, staged protocols, and research observables. Hiding those mechanisms
inside tutorial scripts would produce an attractive gallery on an incomplete architecture. Adding
them without a post-freeze policy would weaken the Phase 13 API freeze.

## Decision

### Phase purpose and order

1. Phase 14 becomes a model-driven capability-completion and documentation phase with five ordered
   subphases:
   - 14.0: published-model corpus, source pinning, and adversarial capability audit;
   - 14.1: accepted modeling primitives and conformance;
   - 14.2: Learn and Examples documentation;
   - 14.3: published-model reproductions; and
   - 14.4: full manual, visualization, and in-scope satellite completion.
2. The initial release portfolio contains 4--6 published models. It MUST include at least one
   flagship model associated with each of Glazier, Wortel, and Jiang. The initial target set is:
   a foundational Glazier--Graner differential-adhesion model, a Wortel cell-migration/Act-CPM
   model, a Jiang collective-tumor-migration model, and a Glazier--Jiang angiogenesis model. Exact
   papers, figures, source revisions, and permitted assets are pinned during Phase 14.0.
3. A model implementation does not begin until its source record, target result, mechanistic
   requirements, execution schedule, validation method, and known ambiguities are recorded.

### Fidelity and claims

4. A published-model reproduction MUST target a named paper figure, table, statistic, or explicitly
   described qualitative result. It MUST record mechanistic, execution-protocol, initialization,
   parameter, output, and statistical fidelity independently.
5. Simplified or merely paper-inspired models belong in Examples and MUST NOT be described as
   published-model reproductions.
6. Qualitative reproduction is permitted only when the target result is intrinsically qualitative
   or the source record cannot support a quantitative target. It is not a fallback used because a
   quantitative test failed.
7. Quantitative tolerances, ensemble sizes, summary statistics, and stopping rules are registered
   before final reproduction runs. Deviations and unresolved ambiguities remain visible in the
   model page and machine-readable manifest.
8. `Author Reviewed` is an additional evidence badge, not a substitute for mechanistic or
   quantitative validation. It is used only after the named reviewer confirms the recorded scope
   and result.

### Capability and freeze policy

9. Reusable scientific mechanisms required by the portfolio belong in CorePotts or PottsToolkit
   protocols and conformance suites. They MUST NOT be stranded in documentation, examples,
   analysis scripts, or a model-specific private engine.
10. Existing frozen Phase 13 contracts remain frozen. Additive public capabilities are permitted
    when they are independently specified, reference-implemented by the sequential CPU path, tested
    through PottsToolkit when applicable, versioned, and included in persistence and inspection.
    An incompatible change to a frozen API or frozen RNG, IR, checkpoint, fingerprint,
    result-schema, or algorithm semantic contract requires an explicit versioned release decision
    and evidence-invalidation record under Decision 0028.
11. Phase 14.1 uses the smallest reusable abstraction justified by at least one selected model.
    Existing extension protocols are used when they express the mechanism without hidden state or
    semantic distortion. A new first-class primitive is added when the mechanism creates broadly
    reusable state, update ordering, persistence, or backend obligations.
12. Every new scientific capability receives an ordinary sequential CPU reference path. CPU,
    Metal, and ROCm qualification is required only for the backends on which that capability is
    advertised. An unsupported backend is reported explicitly and cannot be inferred from other
    core qualification.

### Documentation and release policy

13. The manual remains one Documenter site organized as Learn, Examples, Published Models,
    Concepts and Guarantees, and API. Reusable model source is executable Julia code; pages present
    it rather than becoming the only implementation.
14. Fast deterministic and bounded numerical checks run in pull-request CI. Long ensembles,
    expensive rendering, and full reproduction studies run in scheduled or release qualification
    tiers and publish content-addressed evidence.
15. All selected 4--6 models must reach their registered release status before Phase 14 closes. A
    difficult selected model may not be silently replaced, simplified, or relabeled. Changing the
    release portfolio requires an explicit owner-approved scope amendment that records the reason
    and claim impact.
16. The Glazier-, Wortel-, and Jiang-associated flagship records require review by the applicable
    collaborator before Phase 14 closes. If a collaborator is unavailable after recorded review
    attempts, only an explicit owner-approved exception can waive that gate; the model does not
    receive an `Author Reviewed` badge and the limitation remains visible.
17. Phase 15 consumes the frozen Phase 14 model manifests and evidence. It reruns bounded
    publication workloads and verifies the archived full studies; it does not decide model
    semantics after observing final results.

## Consequences

- Phase 14 is larger than a documentation rewrite, but its added engineering work is bounded by a
  preregistered model corpus and requirements matrix.
- The paper examples become architectural acceptance tests and expose missing abstractions before
  the release, while ordinary examples remain free to teach simplified models honestly.
- Phase 13 was not a failed refactor: it froze a qualified core. Phase 14 may grow that core
  additively, but cannot rewrite frozen contracts casually.
- Some new capabilities may initially be CPU-only. Documentation and manifests must make that
  support boundary visible.
- Published-model pages, implementation, analysis, and evidence remain traceable without moving
  reusable scientific logic into the documentation layer.

## Migration Impact Assessment

- No Phase 13 stable API, algorithm guarantee, RNG identity, IR version, checkpoint version,
  fingerprint version, or result-schema version changes as a direct result of this decision.
- The roadmap, documentation layout, and release gates change immediately.
- New Phase 14 capabilities will require their own accepted semantic updates and version impact
  assessments before implementation. Additive contracts may extend manifests and reports only
  through explicitly versioned optional fields or a new version that remains readable under the
  documented compatibility policy.
- Existing Phase 10 “five reference workloads” and Phase 13 realistic-model evidence retain their
  historical meaning. They are compiler and algorithm qualification fixtures, not claims that the
  new published-model reproduction portfolio is already complete.

## Alternatives Considered

- Migrate the existing tutorials first and add paper models later. Rejected because it would freeze
  the documentation around capabilities not tested by the intended scientific use cases.
- Implement missing mechanisms inside each model script. Rejected because state, update ordering,
  persistence, and backend behavior are library contracts.
- Reopen the entire Phase 13 API. Rejected because the identified gaps can be addressed through
  bounded additive work, with explicit decisions reserved for genuine incompatibilities.
- Publish simplified versions under the original paper names. Rejected because it obscures
  mechanistic and evidentiary differences.
- Require every new model feature on every GPU backend before any documentation release. Rejected
  because backend claims should follow actual qualification; explicit CPU-only support is more
  accurate than implied portability.

## Required Conformance Evidence

- A pinned 4--6-model corpus and model-to-capability requirements matrix.
- One accepted semantic record and sequential CPU reference path for every new scientific
  capability.
- Persistence, restart, inspection, semantic fingerprint, and PottsToolkit lowering evidence where
  applicable.
- Real-hardware qualification for every advertised backend/capability pair.
- Per-model manifests, preregistered validation plans, clean-run commands, raw results, generated
  outputs, deviations, and evidence status.
- A documentation build that executes the fast model checks and resolves every page to reusable
  source and archived evidence.
