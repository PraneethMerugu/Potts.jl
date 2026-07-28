# Documentation Interview Rounds

Status: Rounds 1–3 accepted; consolidation in progress

Companion audit: [Documentation 9/10 Audit](documentation-9-of-10-audit.md)

## Purpose

The interviews resolve decisions that cannot be inferred safely from source code. They are not
open-ended brainstorming sessions. Each round produces bounded decisions that feed the next round
and, ultimately, `spec/documentation-quality-v1.toml`.

Three rounds are sufficient. Additional rounds require a named unresolved decision.

## Round 1 — Audience, Outcomes, and Boundaries

Goal: freeze who the manual serves first and what each audience must accomplish.

Result: accepted on 2026-07-27. See
[Documentation Interview Round 1](documentation-interview-round-1.md).

### Questions

1. Rank these audiences:
   - biologist or CPM newcomer;
   - computational model builder;
   - research workflow/reproducibility user;
   - CorePotts extension author;
   - performance/backend specialist.
2. What is the single “aha” result the first-session user should see?
3. Should a first-session path require MakiePotts, or should visualization remain an optional next
   step?
4. Which operating systems and Julia installation paths must the docs explicitly support?
5. Is GPU use a normal research workflow, an advanced optimization path, or both?
6. Which non-Phase-16 capabilities must be visibly documented as unsupported or experimental?
7. Should the empty Published Models section remain visible until models are admitted?
8. What compatibility promise should a documented tutorial receive?

### Required decisions

- ordered audience list;
- first-session outcome;
- supported installation matrix;
- GPU placement;
- visible unsupported-capability policy;
- tutorial compatibility policy.

### Exit condition

Every proposed Learn page has a primary audience and outcome. No information-architecture decision
remains dependent on “all users.”

## Round 2 — Example Portfolio, Scientific Claims, and Provenance

Goal: freeze the example gallery and what each example is allowed to establish.

Result: accepted on 2026-07-27. See
[Documentation Interview Round 2](documentation-interview-round-2.md).

### Questions

1. Which proposed examples are essential for launch?
2. Which examples should be original versus explicitly inspired by CC3D or CellularPotts.jl?
3. Is “Immune Patrol” scientifically appropriate for an original example, or should it use a more
   neutral two-population framing?
4. Should the Act example teach persistent migration now, or remain deferred until its stability
   status is clarified?
5. Which examples need animations, and which are better served by deterministic figures?
6. What maximum fast-CI runtime is acceptable per example and for the complete docs suite?
7. What evidence is required before an example may use words such as sorting, chemotaxis,
   persistence, equilibrium, reproduction, or backend agreement?
8. May MIT-licensed CellularPotts.jl code be adapted with attribution, or should all competitor-
   informed examples use clean original implementations?
9. Who approves file-level licensing for external assets or adapted source?
10. Which existing three MP4 files should be removed, archived, or regenerated?

### Required decisions

- launch example list and deferred list;
- visual type for each example;
- fast and expensive runtime budgets;
- scientific-language policy;
- external adaptation policy;
- stale media disposition.

### Exit condition

Every gallery card has a title, learning objective, supported mechanism set, claim boundary,
canonical-source owner, output type, runtime class, and provenance disposition.

## Round 3 — API Stability, Maintenance, and Release Gate

Goal: freeze the durable rules that become executable.

Result: accepted on 2026-07-27. See
[Documentation Interview Round 3](documentation-interview-round-3.md).

### Questions

1. Which current exports are intended for ordinary users versus extension authors?
2. Should experimental and internal exports appear in the public site, a separate developer
   section, or only package-local documentation?
3. Is 100% documentation required for stable APIs, with 95% used only as the whole-package
   threshold?
4. Who owns classification when a new exported name appears?
5. Should a missing stable docstring block every pull request?
6. Which external links must be checked on every pull request versus scheduled CI?
7. What constitutes acceptable visual regression for documentation figures?
8. Which changes require tutorial reruns, artifact regeneration, or owner review?
9. Who can mark a page stable, experimental, inspired, or published reproduction?
10. What exact evidence closes the 9/10 documentation gate?

### Required decisions

- public-name classification policy;
- coverage thresholds;
- page and API ownership;
- PR versus scheduled checks;
- visual acceptance policy;
- final release gate.

### Exit condition

Every proposed TOML field has an agreed meaning and owner. The checker has no subjective prose-
quality rule.

## Interview Record Template

Create one record per round:

```markdown
# Documentation Interview Round N

Date:
Participants:
Baseline commit:

## Decisions

| ID | Decision | Rationale | Owner | Revisit trigger |
|:--|:--|:--|:--|:--|

## Rejected alternatives

| Alternative | Why rejected |
|:--|:--|

## Open items

| Item | Blocking? | Owner | Required evidence |
|:--|:--:|:--|:--|

## Changes to the audit

- ...
```

## Consolidation Procedure

After Round 3:

1. update the audit where owner decisions supersede hypotheses;
2. write `spec/documentation-quality-v1.toml`;
3. implement `scripts/check_documentation_quality.jl`;
4. add focused checker tests using one valid and several invalid fixture registries;
5. run the checker, strict Documenter build, and clean-install smoke;
6. record the accepted baseline and unresolved deferred work;
7. begin implementation in the P0–P4 order from the audit.

The interviews should not generate a second roadmap. Decisions either update the audit, enter the
executable specification, or remain explicitly deferred.
