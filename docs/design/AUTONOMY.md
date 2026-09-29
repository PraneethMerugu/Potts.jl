# Autonomous development protocol

Goal: the rewrite proceeds without maintainer input. This works because (1) decisions
are pre-made in `DECISIONS.md`, (2) every milestone has command-checkable acceptance,
and (3) a standing authorization covers the actions needed.

## 1. Loop

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
5. Scientific disputes: brute-force oracle > reference implementation > literature
   reading (D-022).

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
- **Cut-over: pre-authorized** once §5 passes. Because it necessarily pushes (`legacy/*`
  and `archive/*` tags, the `monorepo` branch, the merge into `main`) and archives
  repos, that push is the first and only GitHub action, and it happens only when the
  checklist passes. Force pushes remain forbidden (D-025).

## 5. Cut-over checklist (pre-authorized when all pass)

- ROADMAP.md complete; CI green on `monorepo` for Core, QA, Reference; GPU group green
  locally.
- Every published model matches the reference (KS p > 0.01 on every saved observable
  over 16 seeds) or has a D-022 entry.
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
