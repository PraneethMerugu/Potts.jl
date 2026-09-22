# Worktree and branch preservation ledger

Status: read-only audit snapshot, 2026-09-22

This ledger describes every worktree classified on 2026-09-21 as
`HARD-PRESERVE` or `REVIEW-PRESERVE`. It intentionally omits the 67 clean,
attached worktrees classified as immediately removable. Omission from this
document therefore does not mean that a branch never existed; it means that
the branch had no open pull request, dirty state, primary-checkout role, unique
tip, or detached-review reason in that audit.

No branch, ref, stash, worktree, or file was changed by this audit. Several
`/private/tmp` directories disappeared between the initial inventory and the
review on 2026-09-22. Their Git registrations and commit identities remain
listed, with the loss of the live directory called out explicitly.

## Reading the ledger

Quality ratings are engineering assessments, not merge authorization:

- **High**: focused ownership, ordinary behavioral tests, and either merged or
  strong qualification evidence.
- **Medium**: substantive tested work, but stale ancestry, mixed ownership, or
  incomplete joined qualification remains.
- **Low**: known architectural or scientific blockers make the branch unsafe
  to merge as written.
- **Unknown**: the checkout disappeared or evidence was insufficient for a
  current source review.

“Unique” means the tip contained commits not reachable from another ref known
locally at the time of the audit. It does not mean the patch is absent from a
squash merge or aggregate candidate. Before cleanup, use patch and tree
equivalence, not commit reachability alone.

Path abbreviations:

- `ROOT` = `/Users/praneethmerugu/Documents/Jiang/CPM 1.6/Potts.jl`
- `ECO` = `/Users/praneethmerugu/Documents/Jiang/CPM 1.6/PottsEcosystem`
- `WT` = `ROOT/.worktrees`

## Executive disposition

| Class | Count | Required disposition |
|---|---:|---|
| Hard preserve | 61 | Retain until the stated dependency, dirty-state, PR, or unique-patch resolution is complete. |
| Review preserve | 18 | Retain only long enough to confirm reproducibility/evidence value; most are detached duplicates. |
| Immediately removable | 67 | Excluded from this ledger; remove only in a separately authorized cleanup. |
| Total registered at initial audit | 146 | No cleanup occurred during this review. |

The deliverable stack is much smaller than the preservation set. The intended
spine remains LocalMath `origin/main` → Core C10 → Potts R09/C11 → corrected
Core R10 → corrected Potts R11 → Core R49 → Potts R50 → dependency/CI layers,
followed by attempt-budget and native Act/lifecycle work. Historical source
branches remain here only until their observable contracts are shown to exist
on that spine.

## CorePotts — hard preserve

| Branch / worktree | HEAD | What it does | Quality | Potential resolution | Owner / action |
|---|---|---|---|---|---|
| `main` — `ECO/CorePotts.jl` | `b6ded93` | Primary Core line with merged typed composition/lifecycle and Cartesian domain ownership. | **High**: R08 and C10 are merged with local/full hosted CPU, docs, quality, independent-review, macOS, and real-Metal evidence. | No C10 reconciliation remains; the canonical checkout was fast-forwarded after merge. | Corrected R10 now stacks here. |
| `codex/ecosystem-core-candidate` — `/private/tmp/corepotts-ecosystem-candidate` | `7568341` | Integrated C10/R10/R49 compiler and behavior candidate. | **Medium**: clean and tested, but collapses three owners. | Superseded as integration tree by `b82c873`; retain only as comparison oracle. | Compare against split C10→R10→R49 stack, then archive. |
| `codex/scd-r49-restack` — `/private/tmp/corepotts-scd-r49` | `d909a4d` | Joined R10/R49 plus neutral-proposal and pausable-MCS changes. | **Medium**: real tests, but noisy merge history and 17-file drift from preferred aggregate chain. | Dependency inversion, reversions, and history noise. | Use only as conflict oracle; transplant semantic deltas and archive. |
| `codex/scd-pausable-sequential-runtime` — `/private/tmp/corepotts-scd-sequential` | `c701de4` | Opaque pause/resume token for transactional sequential MCS/lifecycle boundaries. | **High**: focused execution, receipt, acceptance, and abort tests. | Needs Potts native-lifecycle canary and final API/naming review. | Preserve as distinct post-R49 lifecycle child. |
| `codex/addressed-process-rng` — `WT/corepotts-addressed-rng` | `334cbe6` | Qualified operation keys and versioned Philox addressing. | **Medium**: broad scientific/RNG tests; old-base branch. | Separate already-merged equivalents from genuinely missing address law. | Preserve as deterministic-RNG source; rebase only a demonstrated missing delta. |
| `codex/authoring-execution` — `WT/corepotts-authoring-execution` | `aa94e1c` | Isolates intentional provider failures in the owner task. | **High**: tiny focused correction; patch-equivalent upstream. | No live product delta. | Record equivalence, then archive. |
| `codex/checkerboard-oracle-snapshots` — `WT/corepotts-checkerboard-oracle-snapshots` | `15b1e61` | Corrects independent checkerboard oracle snapshots and fixture ownership. | **High**: focused oracle changes; patch-equivalent upstream. | No live delta. | Record equivalence, then archive. |
| `codex/fixed-vector-operations` — `WT/corepotts-fixed-vector-operations` | `809334a` | Fixed-vector construction/indexing in static operations. | **High**: focused tests; patch-equivalent upstream. | No live delta. | Record equivalence, then archive. |
| `codex/history-execution` — `WT/corepotts-history-execution` | `8822297` | Dense history sampling, retained samples, and copy-transaction ownership. | **Medium**: substantial named history/ownership tests. | Stale base and overlap with current lifecycle banks/C10/R10. | Extract the final durable history contract onto its future owner; do not merge wholesale. |
| `codex/lifecycle-numeric-conversion` — `WT/corepotts-lifecycle-numeric-conversion` | `779deae` | Exact lifecycle product conversions and identity-capacity handling. | **Medium**: conversion validation and device fixes, but broad/stale. | Needs narrow extraction plus CPU/Metal requalification. | Preserve as source material for R08 lifecycle follow-up. |
| `codex/logical-state` — `WT/corepotts-logical-state` | `75519fe` | Separates snapshot ordering from structured-storage admission. | **High**: focused implementation; both patches are upstream-equivalent. | No live delta. | Record equivalence, then archive. |
| `codex/maintained-quantities-integration` — `WT/corepotts-maintained-quantities-integration` | `094bb3a` | Integrates site sums, source-aware refresh, and structured owner sums. | **Medium**: extensive CPU/Metal quantity tests; unique item is mostly merge topology. | R10 scientific blockers remain; topology is not product semantics. | Preserve until final R10 tree comparison, then archive. |
| `codex/model-state-reads` — `WT/corepotts-model-state-reads` | `d5bd5a0` | Model-owned state reads in proposal energy and site stages. | **Medium**: focused energy/stage tests. | Public/private ownership boundary needs current-stack review. | Transplant only a still-missing public-interface delta. |
| `moment-geometry-metal-witness` — `WT/corepotts-moment-metal` | `79256e0` | Independent Metal oracle for moment geometry. | **High**: explicit independent witness; patch-equivalent upstream. | No live delta. | Record equivalence, then archive. |
| `codex/periodic-cell-geometry` — `WT/corepotts-periodic-cell-geometry` | `fbd043e` | Stable periodic cell-geometry tracking. | **Low**: extensive work, but canonical review records unresolved owner, spacing, oracle, rejected-machinery, and compiler issues. | Pre-C10, 87-file overlap; unsafe wholesale merge. | Preserve as oracle and reimplement the durable geometry law after corrected R10. |
| `codex/scheduled-process-draws` — `WT/corepotts-scheduled-process-draws` | `12873dc` | Invocation-addressed scheduled draws and static real trigonometry. | **High**: dedicated tests; all four patches upstream-equivalent. | No live delta. | Record equivalence, then archive. |
| `codex/scheduled-scope-contexts` — `WT/corepotts-scheduled-scope-contexts` | `ea403e2` | Binds scheduled cell/site anchor operations to selected identities. | **Medium**: focused scope-context tests; no exact descendant. | Current authoring/lowering compatibility is unverified. | Preserve as a future scoped-context feature, not current G05. |
| `codex/structured-lifecycle-integration` — `WT/corepotts-structured-lifecycle-integration` | `486380b` | Integrated structured state, cell stages, and numeric conversion. | **Medium**: broad lifecycle/device testing, but 89-file stale integration. | Early patches are upstream-equivalent; last cell-stage/conversion patches need isolation. | Split only absent semantics, then archive the integration branch. |
| `codex/native-act-leader-follower-core` — `WT/native-act-leader-follower/CorePotts.jl` | `2bb3b2f` | Realized contact owners, Act mean/reduction, and bounded owner-filtered gathers. | **High**: focused contact, ownership, LocalMath, geometry, and energy tests. | Coordinate its public payload with Potts leader/drive lowering; duplicate ancestry with `c701de4`. | Preserve as the G06 Core semantic tip or retain history through `c701de4`, not both. |
| `codex/site-minimum-tracker` — `WT/corepotts-site-minimum` | `a4fb6c8` | Open R10 maintained-site-minimum branch. | **Medium**: focused CPU/Metal work; known G05 gaps remain. | Worktree is behind remote branch `daca17f`; periodic/connectivity blockers remain. | Keep for PR evidence; do not develop from this stale tip. |
| `codex/quantity-consumption-contract` — `WT/corepotts-quantity-consumption` | `b8423a8` | Quantity-consumption SPI over maintained spatial relationships. | **Medium**: broad tracker/downstream tests. | Old R49/R10 ordering and joined C08/C09/C10 qualification remain. | Fold the contract delta into corrected R10 rather than add another canonical PR. |
| `codex/cartesian-domain-ownership` | `94fad1a` (merged as `b6ded93`) | C10 owner-at-site, domain metadata, and authoritative mutable-site set. | **High and merged**: reconstructed on current main; complete local/hosted qualification and independent review passed. | No live delta remains. Both verified-clean C10 worktrees were removed after merge; refs and the checksummed preservation archive remain. | Archive the subsumed branch after downstream pins record `b6ded93`. |
| `codex/relation-measure-sensing` — `WT/corepotts-relation-measure-sensing` | `c353a87` | Maintained spatial relation/query measurement. | **Medium**: substantial CPU/Metal and surface tests. | Must prove C08/C09 rebuilds, C10 fixed owners, and C11/R11 lowering. | Fold corrected relation delta into R10. |

## CorePotts — review preserve

| Worktree | HEAD | What it does | Quality | Potential resolution | Action |
|---|---|---|---|---|---|
| detached `/private/tmp/artifact-reuse-corepotts` | `b4e5bda` | Kaimon/artifact-reuse snapshot at the historical R49 tip. | **Unknown tree / medium revision**: recorded hosted-green revision, but directory is gone. | Registration is now prunable; duplicate of `corepotts-ka-downstream`. | Preserve commit evidence through attached R49 refs, then remove stale registration. |
| detached `/private/tmp/core-attempt-budget-dep` | `7183bce` | Attempt-budget/compiler benchmark dependency snapshot. | **High**: clean merged PR29 commit. | No unique code; redundant ancestor. | Archive/remove after recording ancestry. |
| detached `/private/tmp/corepotts-ka-downstream` | `b4e5bda` | Downstream Kaimon/compiler canary at the same R49 tip. | **Unknown tree / medium revision**: directory is gone. | Duplicate prunable registration. | Retain commit-level evidence only, then remove registration. |
| detached `WT/corepotts-aggregate-input-validation` | `1f40718` | Target-aware adaptation integrated into source-sum execution. | **Medium**: clean intermediate R10 merge. | No independent final contract; value is inherited by descendants. | Keep until R10 tree comparison, then archive. |
| detached `WT/corepotts-structured-owner-validation` | `aa10812` | Structured owner-sum validation snapshot. | **Medium-high**: focused CPU/Metal tests. | Duplicate of the attached structured-owner-sums head. | Retain attached ref; archive detached duplicate after R10 preservation. |

## Potts current-workspace registry — hard preserve

| Branch / worktree | HEAD | What it does | Quality | Potential resolution | Owner / action |
|---|---|---|---|---|---|
| `codex/compiler-diagnostics-contract` — `ROOT` | `54687b967837` | Moves compiler attribution into reproducible diagnostics instead of ordinary package tests. | **High**: clean, narrow diagnostic ownership. | Must reconcile onto current `origin/main`; not the scientific integration tip. | R49/R50 diagnostics; preserve and review as focused change. |
| `codex/final-potts-integration` — `/private/tmp/potts-final-integration` | `7eef49b52f44` | Exact joined Potts/Core execution candidate. | **Medium**: broad integration evidence, but a 150-commit aggregate. | Mixes science, dependency, planning, and qualification ownership. | Use only as tree/behavior oracle for the published stack. |
| `codex/reconcile-canonical-planning` — `/private/tmp/potts-reconcile-canonical` | `4390f5570e23` | Planning and audit-record reconciliation. | **Medium-high**: clean documentation-only change. | Determine whether current canonical design already contains the text. | Transplant only current corrections, then archive. |
| `codex/ci-phase-telemetry` — `/private/tmp/potts-ci03` | `dcd82202047c` | Open PR64 compilation-phase/shard telemetry. | **High**: focused phase recording, CI wiring, summaries, and tests. | Depends on PR63 and the unmerged scientific stack. | Preserve untouched as the active CI PR worktree. |

## Potts current-workspace registry — review preserve

| Worktree | HEAD | What it does | Quality | Potential resolution | Action |
|---|---|---|---|---|---|
| detached `/private/tmp/artifact-reuse-potts` | `2d317fc02897` | Earlier R50 artifact-reuse/Kaimon snapshot. | **Unknown current tree**: directory has disappeared. | Registration is prunable; evidence may be superseded by later R50 audits. | Preserve commit until report comparison, then remove registration. |
| detached `/Users/praneethmerugu/.codex/worktrees/d089/Potts.jl` | `a6b342b555bd` | Atomic keyed-rebuild planning checkpoint. | **High historical**: merged through Potts PR57. | No live feature work. | Verify durable remote reachability, then remove. |

The current-workspace repository also has one stash containing a one-file
historical Phase-12.5 audit normalization. It is not a current product-stack
change; export it only if the archived text is still needed.

## Potts ecosystem registry — hard preserve

| Branch / worktree | HEAD | What it does | Quality | Potential resolution | Owner / action |
|---|---|---|---|---|---|
| `main` — `ECO/Potts.jl` | `5ebb690a654a` | Primary ecosystem clone and registry owner. | **High**: clean merged PR61 audit record. | One commit behind `origin/main`; owns two stashes. | Preserve, secure/classify stashes, then fast-forward normally. |
| `codex/attempt-budget-reconciliation` — `/private/tmp/potts-attempt-budget` | `f4f2e53691dc` | Multi-attempt sweep semantics, mutable-site accounting, replay, and rollback. | **High-medium**: focused behavioral/failure/continuation tests. | Old base; compare against C11’s authoritative mutable-site set and R11. | Preserve as a separate semantic layer before native lifecycle work. |
| `codex/scd-compositional-activity-drives` — `/private/tmp/potts-scd-activity` | `489484c9b52d` | Clean seven-commit leader/Act, runtime-reuse, lifecycle, and compositional-drive chain. | **High**: focused commits, tests/docs, patch-equivalent duplicate verified. | Based on unpublished aggregate `a2e94752`, not the published PR lineage. | Replay in order onto the selected post-R50/CI parent. |
| `codex/scd-r50-restack` — `/private/tmp/potts-scd-r50` | `e00021027c76` | Attempted replay of snapshot/runtime work onto R50. | **Low as current worktree**: expected changes are staged, but a cherry-pick conflict remains. | `test_sciml_problem_and_indexing.jl` is unresolved; concept is superseded by clean `b8b70d97`. | Preserve exactly until clean replay is accepted, then abort/archive rather than merge this history. |
| `codex/native-act-leader-follower-potts-integrated` — `WT/native-act-leader-follower/Potts-integrated.jl` | `96880ab316d3` | Complete native lifecycle, leader/Act, and activity-drive chain. | **High**: all seven patch IDs match the clean SCD chain. | Duplicate ancestry only; no extra semantics found. | Preserve through replay, then retain one realization. |
| `codex/native-act-leader-follower-potts` — `WT/native-act-leader-follower/Potts.jl` | `6c5344d68318` | Earlier partial leader-drive/Act implementation with seven dirty tracked edits. | **Medium/unknown WIP**: focused files/tests, but uncommitted and not patch-equivalent to final leader commit. | Determine whether any behavior is missing from `3b421faf`. | Preserve, semantically diff, salvage only missing behavior, then retire. |
| `codex/accepted-copy-fixture` — `WT/potts-accepted-copy-fixture` | `9b8393383cc5` | Explicit accepted-copy swap and extension-proposal fixtures. | **Medium-high**: focused behavioral coverage. | Later aggregates contain related behavior but exact oracle equivalence is unproved. | Retain missing oracle coverage, then retire after R09 comparison. |
| `codex/potts-addressed-rng` — `WT/potts-addressed-rng` | `32274682544d` | Namespaced semantic RNG keys for authored and initialization draws. | **Medium-high**: clean deterministic-randomness tests. | Verify exact replay/checkpoint cases survived R09. | Preserve until contract comparison; transplant only missing guarantees. |
| `codex/atomic-input-publication` — `WT/potts-atomic-input-publication` | `4fc9277ff621` | Open PR53 structured authoring, lifecycle, ingress, and execution identity. | **High historical/local**, but stale. | Behind remote PR53 tip `3790375c`; remote is authoritative. | Keep active PR worktree; update only through normal PR workflow. |
| `codex/bounded-site-minimum-authoring` — `WT/potts-bounded-site-minimum-authoring` | `4cec5535b664` | Open PR54 maintained aggregates and bounded minima. | **Medium-high**, but stale local tip. | Behind remote `6156511c`; depends on PR59 and corrected Core R10. | Keep as active R11 PR worktree; remote branch is authority. |
| `codex/cartesian-domain-authoring` — `WT/potts-cartesian-domain-authoring` | `1ae1fd439bb7` | Open PR59 typed Cartesian faces, obstacles/exterior, initialization, and lowering. | **Medium-high**, but stale local tip. | Behind remote `511413a5`; requires Core C10. | Preserve active C11 worktree. |
| `codex/cell-process-authoring` — `WT/potts-cell-process-authoring` | `c72a4d563827` | Public cell/retirement processes and shared CPU/Metal numerical oracles. | **Medium-high**: explicit cross-backend oracle evidence. | Confirm lifecycle/retirement tests survived R09 aggregation. | Preserve until R09 content audit; retain missing oracles. |
| `codex/declaration-control-flow` — `WT/potts-declaration-control-flow` | `9ed9a8592f9d` | Ordinary Julia branch/loop declaration enrollment. | **Medium-high**: direct authoring tests. | Ensure no second builder/declaration authority remains. | Compare with PR53, transplant missing observable contracts only. |
| `codex/dimensional-expression-scales` — `WT/potts-dimensional-expression-scales` | `3771488b4e7b` | Dimensional expression reference-scale normalization. | **Medium-high**: focused dimensional tests. | Confirm compatibility with current Symbolics and unit analysis. | Preserve through R09 comparison. |
| `codex/fixed-vector-parameters` — `WT/potts-fixed-vector-parameters` | `826e8eb621fc` | Fixed-vector parameter imports and enclosing anchors. | **Medium-high**: later stack has CPU/Metal vector witnesses. | Identify what R50 array-import fixes supersede. | Retain only contracts absent from R50. |
| `codex/history-authoring` — `WT/potts-history-authoring` | `926c07d8d3b5` | Structured history authoring and shared history fixtures. | **Medium-high**: initialization, lifecycle, ownership, and sample tests. | Verify all tests/docs survived PR53. | Preserve through R09 audit, then consolidate. |
| `codex/logical-state-authoring` — `WT/potts-logical-state-authoring` | `b87f0b27f545` | Logical-state declaration and initial-value semantics. | **Medium-high**: system-owned initialization/scheduling coverage. | Content equivalence with PR53 is not yet proven. | Transplant only missing state contracts. |
| `codex/metal-runner-qualification` — `WT/potts-metal-runner-qualification` | `9997d8d0e176` | Shared real-Metal qualification runners. | **Medium**: useful backend evidence; old tuple/layout. | Establish equivalent coverage in PR63/64 and selected stack. | Preserve as evidence until replacement qualification passes. |
| `codex/mixed-symbolic-mutation` — `WT/potts-mixed-symbolic-mutation` | `4b26e12f0ed1` | Mixed symbolic state mutation/publication. | **Medium-high**: implementation, fixtures, and Metal witness. | Verify no private Core detail became a downstream contract. | Preserve through R09 content audit. |
| `codex/model-state-reads` — `WT/potts-model-state-reads` | `e1228dbad561` | Model/site state reads and checkpoint continuation. | **Medium-high**: coupled continuation coverage. | Compare guarantees against current checkpoint tests. | Retain independent continuation oracle if absent. |
| `codex/product-state-authoring` — `WT/potts-product-state` | `a34ade4598f3` | Named-product initialization and reference ownership. | **Medium-high**: docs, defaults, and ownership tests. | Determine supersession by product-field/structured-state work. | Preserve until R09 semantic comparison. |
| `codex/scheduled-process-draws` — `WT/potts-scheduled-process-draws` | `7d2e50158535` | Addressed held-turn polarity draws and scalar trigonometry. | **Medium-high**: dedicated fixture, tests, and Metal witness. | Verify RNG identity and held-state continuation on selected stack. | Transplant missing witnesses only. |
| `codex/scoped-component-integration` — `WT/potts-scoped-component-integration` | `c16a4a5d3d2a` | Scoped component imports and enclosing anchors. | **Medium-high**: scoped/anchor tests. | Separate durable semantics from R50-superseded corrections. | Compare ranges, then consolidate. |
| `codex/state-contract-quality` — `WT/potts-state-contract-quality` | `b2a8f3b75237` | Public symbolic ownership and current-state dependency contracts. | **Medium-high**: public-interface/dependency tests. | Confirm corrections exist on remote PR53 tip. | Cherry-pick only missing corrections. |
| `codex/stochastic-field-authoring` — `WT/potts-stochastic-field-authoring` | `a495e654344e` | Stochastic field-rate authoring and isolated device witnesses. | **Medium-high**: explicit device witness isolation. | Confirm backend claims and optional integration boundaries. | Preserve for R09/G07 comparison. |
| `codex/structured-state-authoring` — `WT/potts-structured-state` | `e5bc82593bc2` | Typed fixed-size state values and vector-expression compilation. | **Medium-high**: assignments, literals, initialization, and expression tests. | Verify final LocalMath ownership and complete migration. | Preserve until R09/LocalMath ownership audit. |

## Potts ecosystem registry — review preserve

| Worktree | HEAD | What it does | Quality | Potential resolution | Action |
|---|---|---|---|---|---|
| detached `/private/tmp/potts-ka-downstream` | `40b2ddf37125` | Saved-state/Kaimon downstream canary. | **Unknown current tree / medium revision**: directory has disappeared; commit stabilized saved-state views. | Registration is prunable; later compiler work may fully supersede the evidence. | Preserve commit until evidence comparison, then remove registration. |

The ecosystem Potts repository has two stashes. The attempt-budget stash is
patch-equivalent to committed `f8735aa3` and becomes redundant once the branch
is secured. The 28-file aggregate/publication stash is not patch-equivalent to
one commit; export it and classify every hunk against PR53/R11/R50 before any
cleanup. Never apply it wholesale.

## LocalMath — hard preserve

| Branch / worktree | HEAD | What it does | Quality | Potential resolution | Owner / action |
|---|---|---|---|---|---|
| `main` — `ECO/LocalMath.jl` | `a1d60d1a` | Canonical LocalMath checkout, including merged pointwise payload narrowing. | **High**: clean merged PR24; required C01/C03–C14 are upstream. | One commit behind `origin/main=d3d2e553`. | Preserve and normally fast-forward; use origin/main as dependency authority. |
| `codex/pointwise-temporary-identity-segmentation` — `/private/tmp/localmath-c15` | `b68952aa` | Narrow pointwise segmentation payload. | **High historical**: focused 15-line production change, merged as PR24. | Directory disappeared and registration is prunable; fully contained by main. | Preserve ref only through cleanup confirmation; do not stack. |
| `codex/d2q9-animation` — `WT/localmath-d2q9-animation` | `af332b4a` | Exploratory D2Q9 animation scratch harness. | **Medium as research / not product**: isolated scratch project, large frozen manifest. | Explicitly throwaway and 19 commits behind main. | User decision: bundle/archive or delete; never stack into production. |
| `codex/trigonometric-stage-admission` — `WT/localmath-trigonometric-stages` | `d98af554` | Earlier native `sin`/math singleton admission. | **Medium historical**: CPU/Metal fixtures and docs, but superseded by stricter current logic. | Wholesale cherry-pick would regress later effect-analysis/settlement work. | Document equivalence, then archive; do not stack. |

## LocalMath — review preserve

| Worktree | HEAD | Purpose and quality | Potential resolution | Action |
|---|---|---|---|---|
| detached `/private/tmp/artifact-reuse-fusion-ir/localmath` | `a26cbfe4` | Exact C14 fusion/IR research snapshot; **high revision**, directory now absent. | Prunable and duplicate of two other C14 snapshots. | Confirm external artifacts, then remove registration. |
| detached `/private/tmp/artifact-reuse-identity-atlas/localmath` | `a26cbfe4` | Exact C14 identity-atlas snapshot; **high revision**, directory absent. | Duplicate/prunable. | Confirm evidence retention, then remove. |
| detached `/private/tmp/artifact-reuse-localmath` | `a26cbfe4` | General artifact-reuse baseline; **high revision**, directory absent. | Duplicate/prunable. | Confirm evidence retention, then remove. |
| detached `/private/tmp/localmath-attempt-budget-dep` | `b699002a` | Historical attempt-budget dependency baseline; **medium**, clean ancestor. | Too old for current C08–C14 consumers. | Keep only for an explicit reproduction; otherwise remove. |
| detached `/private/tmp/localmath-core-exact` | `d3d2e553` | Exact current LocalMath dependency checkout; **high**, clean and current. | Detached status only. | Retain while exact Core qualification needs it, otherwise redundant. |
| detached `/private/tmp/localmath-ka-coordinator` | `12b3fa98` | Exact C12 KA launch investigation; **high historical**, directory absent. | Superseded by C13/C14/PR24/PR25; prunable. | Evidence is in design records; remove registration after confirmation. |
| detached `WT/localmath-current-main` | `22e7b429` | Historical C06-era control; **high historical**, clean ancestor. | Duplicate of `localmath-main-validation`, 15 commits behind. | Keep at most one only for a named comparison. |
| detached `WT/localmath-fixed-value-validation` | `37838c62` | Exact C04 fixed-value validation snapshot; **high historical**. | Merged and superseded by later executor/settlement context. | Remove after any scheduled retrospective comparison. |
| detached `WT/localmath-main-validation` | `22e7b429` | Second C06-era control; **high historical**. | Exact duplicate detached HEAD. | Remove; retain neither unless a named comparison needs one. |
| detached `WT/native-act-leader-follower/LocalMath-integrated.jl` | `d3d2e553` | Exact LocalMath side of joined native-Act experiment; **high/current**, no LocalMath delta. | Meaningful changes are downstream; duplicate of current main revision. | Keep only during joined qualification, then remove. |

## PottsModels

| Branch / worktree | HEAD | What it does | Quality | Potential resolution | Owner / action |
|---|---|---|---|---|---|
| `codex/compositional-act` — `ECO/PottsModels.jl` | `9a6b5c46` | Rewrites Wortel Act behavior using public gather, canonical fold, and `ProposalDrive`. | **Medium-high**: compact, readable public composition and docs. | No direct tests changed; depends on unpublished Potts APIs and final R11/R13 semantics. | Preserve for Models R17 after corrected G05 and G06; add scientific parity tests. |
| `model-library` — `WT/PottsModels.jl` | `58eec61a` | Original R01 model-library source checkout and second clone registry. | **High historical**: PR1 content merged, clean. | Two main commits stale; duplicate clone registry. | Preserve until clone consolidation, then remove registry/checkout rather than restack code. |

## MakiePotts

| Branch / worktree | HEAD | What it does | Quality | Potential resolution | Action |
|---|---|---|---|---|---|
| `main` — `ECO/MakiePotts.jl` | `1ee091a6` | Canonical visualization package and merged candidate-CI work. | **High**: clean and equal to origin/main. | Future R19 must wait for G08 public observation/inspection contracts. | Preserve canonical checkout; no historical branch belongs in the current stack. |

## KaimonCompilerTools

| Branch / worktree | HEAD | What it does | Quality | Potential resolution | Action |
|---|---|---|---|---|---|
| `main` — `ECO/KaimonCompilerTools.jl` | `939aea4c` | Compiler diagnostic tooling used for bounded KCT evidence. | **High**: clean and equal to origin/main. | It is diagnostic tooling, never a product-stack predecessor or semantic authority. | Preserve canonical checkout; product packages own any measured fixes. |

## Recommended resolution order

1. Export the non-equivalent 28-file Potts stash and fingerprint both dirty
   Potts worktrees without resolving or resetting them.
2. Freeze refs or bundles for every unique tip before changing any worktree
   registration.
3. Compare historical R09/R10 source branches by patch and observable contract
   against the selected PR tips; transplant only missing focused behavior.
4. Repair C10 and corrected R10, then re-establish the C10 → C11 → R10 → R11
   → R49 → R50 joined tuple.
5. Review attempt-budget work as its own semantic layer.
6. Replay one clean Core/Potts native Act and lifecycle chain; retire the
   patch-equivalent duplicate only after exact tree and test comparison.
7. Keep `codex/compositional-act` for Models R17 after G06 public drive
   semantics exist.
8. Remove missing/prunable and detached duplicate registrations only in a
   separately authorized cleanup. Then remove merged/equivalent historical
   worktrees and consolidate duplicate Potts/PottsModels clone registries.

## Limits of this audit

The reachability analysis used refs already present locally; it did not fetch.
Quality assessments combine current source inspection, patch equivalence,
ordinary tests recorded in the repository, pull-request state, and canonical
planning records. They do not turn historical evidence into qualification for a
newly restacked tuple. Every delivered stack still requires ordinary owner
tests, integration/replay, documentation and quality checks, compiler/allocation
contracts where relevant, and portable KernelAbstractions behavior on real
Metal.
