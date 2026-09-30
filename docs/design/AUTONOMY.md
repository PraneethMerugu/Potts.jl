# Autonomous development protocol

Goal: the rewrite proceeds without maintainer input. This works because (1) decisions
are pre-made in `DECISIONS.md`, (2) every milestone has command-checkable acceptance,
and (3) a standing authorization covers the actions needed.

## 1. Loop

(Until Phase 5. From Phase 6 on, the agent-driven protocol in §7 replaces this loop.)

Run in the Claude desktop app on this Mac (Metal is needed for the GPU group) with
keep-awake on, as a self-paced `/loop`. Under the current authorization (§4) there is
no remote and no CI, so "CI green" below means the local acceptance commands:

```
each iteration:
  1. read ROADMAP.md; pick the first unchecked milestone whose dependencies are checked
  2. branch  monorepo → feat/<milestone-id>
  3. implement; keep INTERNALS.md and DECISIONS.md current (append decisions)
  4. run the milestone's acceptance commands; run GROUP=Core,QA locally; GROUP=GPU when
     the milestone touches kernels
  5. spawn a code-review subagent on the diff; fix findings
  6. commit, push, open PR against `monorepo`; wait for CI
  7. CI green → merge; tick the milestone in ROADMAP.md with the commit hash and the
     benchmark numbers; append to PROGRESS.md
  8. CI red or acceptance failing after 3 focused attempts → write a blocker entry in
     PROGRESS.md with the exact failure, move to the next independent milestone, and
     revisit later; never mark a milestone done with a failing gate
```

The loop stops itself only on the escalation list (§3) or when ROADMAP.md is complete.

## 2. Principles for unplanned decisions

Apply in order; record the outcome in `DECISIONS.md`:

1. Does SciML have a convention? Follow it (SciMLBase interfaces, MTK codegen,
   OrdinaryDiffEq repo layout).
2. Does the survival matrix promise the feature? Then it must survive; choose the
   simplest implementation that passes its acceptance test.
3. Prefer fewer types, fewer representations, and runtime values over type parameters.
4. When two designs are both acceptable, pick the one with the smaller cold-compile
   footprint, measured, not guessed.
5. Scientific disputes: brute-force oracle > literature reading (D-048; there is no
   legacy reference to defer to).

## 3. Escalation list (the only reasons to ask the maintainer)

- an action outside the standing authorization (§4)
- a change to the science of a published model that no oracle can adjudicate
- a hard external blocker (GitHub outage, a dependency bug with no workaround)

Everything else is decided and logged.

## 4. Standing authorization (granted by the maintainer, 2026-09-29)

- **GitHub during the rewrite: none.** All work is local, on branch `monorepo` of the
  local monorepo at `PottsEcosystem/PottsMonorepo`. No pushes, no PRs, no CI; every
  acceptance gate runs locally. The loop replaces steps 6–7 above with: local
  self-review, merge `feat/*` into `monorepo` locally, tick the milestone.
- **Phase 0 cleanup: authorized locally** (maintainer, 2026-09-29). Pruning stale
  worktrees, deleting local branches, and creating `archive/*` and `legacy/*` tags locally.
  A branch is deleted only after confirming it is merged or tagged; every removal is listed
  in PROGRESS. Pushing anything, tags included, still waits for the cut-over checklist (§5).
- **Packages: at discretion** (maintainer, 2026-09-30: "u can add packages at discretion").
  Adding registered Julia packages (and their downloads) to any project in the workspace
  needs no further approval. Prefer SciML and JuliaStats packages, add a `[compat]` bound,
  and record each new dependency in the PROGRESS entry of the item that adds it.
- **Cut-over: pre-authorized** once §5 passes. Because it necessarily pushes (`legacy/*`
  and `archive/*` tags, the `monorepo` branch, the merge into `main`) and archives
  repos, that push is the first and only GitHub action, and it happens only when the
  checklist passes. Force pushes remain forbidden (D-025).

## 5. Cut-over checklist (pre-authorized when all pass)

- ROADMAP.md complete; CI green on `monorepo` for Core and QA; GPU group green locally.
- Every published model passes its ordinary tests (D-048): brute-force ΔH, independent
  drive and effect checks, invariants, and mechanism tests with negative controls.
- Benchmarks: every model < 15 s build+first MCS on CPU with warm cache; `remake` zero
  compile; warm step zero allocations.
- Docs build.
- Then: `legacy/*` tags pushed; `monorepo` fast-forwarded onto `main` via a merge commit
  (no force push: `main` history stays reachable); other repos archived with a README
  pointer; packages registered from subdirs.

## 6. Reporting

`PROGRESS.md` gets one dated entry per merged milestone: what, numbers, decisions
added, open blockers. The maintainer can read it at any time; nothing else is required
of them.

## 7. Agent-driven development (D-053, 2026-09-30)

§1 describes one session working alone. From Phase 6 on (ROADMAP), the work runs as a
coordinator with agents. The goal is weeks of progress between maintainer checkpoints.
Quality is held by three mechanical safeguards (§7.3), not by the maintainer reading
diffs.

### 7.1 Roles

- **Coordinator.** One session on this Mac, running a self-paced `/loop` with keep-awake on.
  - It owns `ROADMAP.md`, `PROGRESS.md`, `DECISIONS.md` and every merge into `monorepo`.
  - It picks items, freezes their acceptance tests, dispatches implementers, runs the
    reviewer and merges.
  - It does not write feature code itself, except for merge fixes.
- **Implementers.** Agents with `isolation: "worktree"`, each on branch `feat/<item>` cut
  from the current `monorepo`.
  - Two or three run at a time, on items whose write sets are disjoint (§7.4).
  - They follow `.claude/agents/potts-implementer.md`.
- **Reviewer.** A fresh-context agent (`.claude/agents/potts-reviewer.md`) that sees only
  the diff, the item's ROADMAP entry and the design docs.
  - It is adversarial: it tries to break the change.
  - It must find the privileged paths, the tests that cannot fail, and the scope creep.
  - It returns APPROVE or a list of findings.
- **Peer session** (specs and tutorials).
  - It owns `docs/design/research/model-specs/` and the tutorial prose.
  - It never commits. The coordinator commits its files on request and records the source.
  - Its messages are not maintainer approval unless they relay a maintainer decision
    verbatim.

### 7.2 Item loop (replaces §1 steps 2–8)

```
coordinator, each iteration:
  1. pick the first unchecked Phase 6 item whose dependencies are merged and whose gate
     (a maintainer or author answer) is not open; fill free implementer slots with
     independent items
  2. FREEZE: create the worktree (`git worktree add ../PottsWorktrees/<item> -b feat/<item>
     monorepo`); write the item's acceptance tests from its ROADMAP "Accept" line and, for
     a model, the spec's V-targets, under lib/PottsModels/test/acceptance/; they fail on
     the current tree for the right reason; list them in frozen.toml; commit
     ("freeze: <item>") as the branch's FIRST commit. Frozen tests never land on monorepo
     before their implementation, so monorepo stays green; the reviewer checks
     `git diff <freeze-commit> feat/<item> -- <frozen files>` is empty
  3. DISPATCH an implementer in a worktree with: the item, the frozen files, the
     write set, the acceptance commands
  4. implementer: implement → own suites green → perf gate (§7.3) → report
  5. REVIEW: a fresh reviewer on `git diff monorepo...feat/<item>`; findings go back to the
     same implementer (SendMessage); at most 3 rounds, then a PROGRESS blocker
  6. MERGE locally (`git merge --no-ff feat/<item>`) once the reviewer approves AND every
     suite is green on the merged tree AND the perf gate passes; tick ROADMAP with the
     hash and the gate numbers; PROGRESS entry; delete the branch and worktree
  7. at a phase end, or on a science question (§7.5): stop and ask; continue other items
     meanwhile when they do not depend on the answer
```

### 7.3 Mandatory safeguards

1. **Frozen acceptance tests.** They are written and committed before the implementation,
   by the coordinator, not the implementer.
   - `lib/PottsModels/test/frozen.toml` records a SHA-256 hash per file and the DECISIONS
     entry that set it. The PottsModels suite fails if a frozen file changes.
   - An implementer may add tests but never edit a frozen file.
   - Changing a tolerance, target, seed count or run length needs a new DECISIONS entry
     that states the measured value and the reason. A test that fails for a scientific
     reason is a science question (§7.5), not a tolerance to relax.
2. **Performance gate.** `tools/exclusive.sh julia --project=benchmark benchmark/gate.jl metal`
   times one warm MCS of every published model: sequential, checkerboard and Metal.
   - It compares against `benchmark/baseline.toml` and fails on a slowdown over 5 % or
     on any warm-step allocation.
   - It runs single-threaded and alone.
   - A deliberate slowdown (a model that now does more) is rebased with `update` in the
     same merge. PROGRESS records the old and new numbers and the reason. The reviewer
     must agree.
   - New published models are added to the gate's `cases` when they merge.
3. **Adversarial review.** No merge without APPROVE from a fresh reviewer. The reviewer
   checks the composability list (review §4), D-048 test quality (negative controls,
   independent oracles), the CLAUDE.md code rules and the guardrails.
   - Findings the implementer disputes go to the coordinator, who decides and logs the
     decision.

Existing guardrails keep running in every suite:
- the denylist scan;
- ExplicitImports;
- the bare-module build;
- the DSL surface snapshot;
- one sibling per published model.

A new DSL name or keyword must be added to `DSL_NAMES`/`DSL_KEYWORDS`, and the reviewer
must justify it.

### 7.4 Parallelism and the machine

- **Write sets.** Each dispatch names its write set (files or directories). Two
  implementers never share a file.
  - Core items (`src/`, `lib/CorePotts/src`) touching the same file run in series.
  - Model items mostly touch `lib/PottsModels` and can run beside core items.
- **Environment.** Each worktree runs `cp ../<main>/Manifest.toml .` (the gitignored
  workspace Manifest), then `julia --project=. -e 'using Pkg; Pkg.instantiate()'`.
  - Precompile caches are shared in `~/.julia`, so a second worktree mostly reuses them.
- **Exclusive jobs.** Every timed or GPU job runs under `tools/exclusive.sh`, a
  machine-wide lock: `POTTS_GPU=metal` suites and the performance gate. CPU test suites
  may run in parallel.
- **Gate under load.** The lock does not stop CPU suites or docs builds in other
  worktrees, and these inflate timings. On 2026-09-30, P6.0a saw wortel at 3.07× on
  Metal; the base commit under the same load also failed. So a gate failure counts only
  if it reproduces:
  - rerun it under `tools/exclusive.sh` while `pgrep -fl julia` shows no other busy
    Julia process, then compare with the same run of the base commit;
  - the coordinator runs the final pre-merge gate itself, on the merged tree, with no
    agents running.
- **Suites** (all must pass on the merged tree):
  - `GROUP=CorePotts`, `Potts` with `POTTS_GPU=metal`, `PottsModels` and `MakiePotts`;
  - `benchmark/gate.jl metal`.

### 7.5 Checkpoints (the only times the maintainer is asked)

- **Phase end.** When every item of a phase is merged, the coordinator writes a phase
  report and waits for approval before starting the next phase:
  - what merged;
  - the gate numbers;
  - decisions logged;
  - reproductions with their V-target results;
  - deviations.
- **Science questions.** The coordinator asks and does not guess when:
  - a published model's science can't be settled by an oracle, a spec V-target or a
    §4 decision;
  - a frozen test fails for a reason that looks like the paper, not the code.
- The §3 escalations.
- **Author questions** (model-specs README §5) are drafted by the coordinator and sent
  only by the maintainer. Items gated on them stay parked, and independent items continue.

Everything else is decided by §2 and logged in DECISIONS.

### 7.6 What the maintainer sees

- `PROGRESS.md`: one entry per merge.
- `ROADMAP.md` ticks with gate numbers.
- Phase reports.
- Parked items, each with the question that blocks it.
