# ProcessBigraphs Phase 17 Specification Audit

Date: 2026-07-29

Status: accepted specification packet; implementation authorized

Baseline: qualified Phase 16 and semantic-preserving consolidation at
`origin/main` commit `04f39dc05f847b7dd84f24f12cce24d1ed0229a6`

## Packet

| Authority | Path | Purpose |
|:--|:--|:--|
| Accepted owner interviews | `design/audits/process-bigraph-phase17-owner-interview-round-{1,2,3}.md` | Product, API, compatibility, documentation, browser, authority, and completion decisions |
| Decision 0042 | `spec/decisions/0042-process-bigraph-model-and-documentation-productization.md` | Architectural disposition and consequences |
| Normative specification | `spec/phase-17-process-bigraph-model-and-documentation-productization.md` | MUST/MUST NOT behavior and evidence |
| Entry contract | `spec/process-bigraph-phase17-entry-v1.toml` | State, ordering, scope, dependencies, authority, autonomy, and closure |
| API contract | `spec/process-bigraph-phase17-api-v1.toml` | Binding classes, narrow additions, internal boundary, and compatibility |
| Documentation contract | `spec/process-bigraph-phase17-documentation-quality-v1.toml` | Exact 35-page registry, budgets, media, rubric, and task reviews |
| Browser contract | `spec/process-bigraph-phase17-browser-qa-v1.toml` | Cross-browser, WCAG, Lighthouse, visual, journeys, and invalidation |
| Qualification ledger | `spec/process-bigraph-phase17-qualification-v1.toml` | 44 required rows across 17.A–17.F |
| Implementation plan | `design/audits/process-bigraph-phase17-implementation-plan.md` | Dependency-ordered autonomous execution and repair protocol |
| Specification checker | `scripts/check_process_bigraph_phase17_spec.jl` | Fail-closed internal consistency |
| Checker mutation tests | `scripts/test_process_bigraph_phase17_spec.jl` | Proves critical contract mutations are rejected |

## Decision coverage

The packet encodes all accepted Round 1 decisions:

- one Phase 17 with 17.A–17.F;
- qualified unpublished internal beta;
- independent versioned manual;
- prioritized audiences;
- first multirate tutorial;
- six-section navigation;
- qualified source-bounded case-study class;
- bounded Wortel and Merks scopes;
- CNV exclusion;
- strict 90+ quality floor strengthened to 92; and
- explicit exclusions and tutorial interface treatment.

It encodes all accepted Round 2 decisions:

- PottsToolkit model ownership and direct dependency;
- model-family file split;
- complete API classification;
- qualified public extension hooks;
- `managed_field_process`;
- public schema access;
- `ActivityPottsProblem`;
- retained coupled internals;
- topology-based `static_relation`;
- downstream Merks and reusable Wortel;
- zero-internal enforcement;
- semantic versions and migration;
- downstream and lifecycle qualification;
- one-branch baseline merge; and
- full inline tutorial assembly.

It encodes all 28 accepted Round 3 decisions, including:

- explicit authoring syntax;
- exact page inventory;
- visual, runtime, and asset budgets;
- WCAG, Playwright, Lighthouse, and visual regression;
- terminal browser journeys;
- no-waiver repair loops;
- qualifying-content invalidation;
- branch/PR authority;
- autonomous stop conditions; and
- exact completion.

## Closed ambiguities

### CorePotts activity access

The packet avoids redundant activity-specific accessor names. The façade reuses:

- `logical_state`;
- `current_mcs_report`;
- `capture_checkpoint`;
- `restore_checkpoint`;
- ProcessBigraphs `observation_records`; and
- SciMLBase `init`/`step!`.

Only `ActivityPottsProblem`, `static_relation`, and `site_property_value` are
newly promoted user bindings. Concrete integrators remain internal.

### Browser exactness

The browser result binds to qualifying product content rather than the evidence
file that records the result. Evidence-only paths cannot affect the build or
tests. After evidence is committed, the content digest is recomputed and must
match. This closes the attestation recursion without weakening exactness.

### Visual regression

Cross-browser functional tests are separate from screenshot authority.
Screenshots are compared only in a pinned Linux/Chromium environment, consistent
with Playwright's documented rendering variability.

### Accessibility

Automated axe checks require zero supported A/AA violations and permit no rule
disabling or broad exclusions. The browser agent separately assesses criteria
requiring judgment. The evidence cannot claim a human conformance audit.

## Remaining implementation discoveries

The following are implementation facts to measure, not owner decisions:

- exact consolidated source paths after the authorized baseline merge;
- generated complete binding inventory;
- exact media encoding parameters within frozen budgets;
- visual diff tolerance small enough to detect all prohibited regressions;
- reduced Wortel and Merks run lengths that meet fixed semantic outcomes and
  budgets; and
- whether the checked device-impact map requires hardware reruns.

These discoveries cannot change the accepted boundary. A conflict with a fixed
requirement triggers repair or an autonomous stop, not silent specification
relaxation.

## Audit conclusion

The packet is sufficient to implement Phase 17 autonomously after explicit
owner send-off. It defines product ownership, exact public additions, forbidden
internals, model versions, compatibility, complete documentation outcomes,
budgets, deterministic and agent browser gates, evidence invalidation, branch
authority, stop conditions, and completion.

The packet itself grants no authority. The owner subsequently authorized Phase
17 implementation through the persistent goal “finish phase 17.”
