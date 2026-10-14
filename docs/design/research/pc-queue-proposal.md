# PC job queue: two lanes (proposal, 2026-10-14)

Status: **approved 2026-10-14 (approvals 1–3; D-248). The BIOS change (4) is not approved.** Under D-157, D-232 and D-242. None of these decisions is reopened, and a second machine is not proposed.

## 1. Measured (2026-10-14, read-only)

| What | Value | Source |
|---|---|---|
| Load at 13:50 EDT | 1.11 / 1.05 / 1.01 on 32 threads (~3 %) | `uptime` |
| Running | one Julia process (q3 PottsModels, `-t 4` but ~1 core busy) on 12-15/28-31 | `ps` |
| Memory | 62 GB visible, 55 GB available; VRAM carve-out 64 GiB, GTT 31 GiB | `free`, sysfs |
| Serial 4-core suites per item | 74 min (rngw), 93 min (p6.5b), 94 min (mb28) | q1/mb28 log mtimes |
| CPU A/B, all cases | 43-44 min | q1, mb28 |
| ROCm A/B, all cases | 52 min | q1, mb28 |
| One whole item (suites + CPU + ROCm A/B) | ~3 h 10 min | mb28: 21:53 → 01:03 |
| CI duty since D-232 (25 h) | 5 runs, 23-45 min, ~2.6 h in total (~10 %) | `gh run list` |
| CI parallel block (D-232 trials) | 22.5 min wall for all suites on 24 threads | D-232 |

The queue as of 13:50: q3 in suites, then a scoped A/B. q5 (suites, then CPU and ROCm A/B on all cases) waits on `q3-run.pid`, and q6 (suites, then CPU A/B) waits on `q5-run.pid`. All three reuse the `~/potts-ci/mb25` checkout through `git checkout`, which is a second reason the chain is serial. The `rngw2`/`rngw3`/`mb26cpu`/`mb29` "waiting" lines are stale status text: those processes are gone, so the status file is the only thing that is wrong.

q7 (P6.5c: suites, part B on ROCm and docs, no A/B) has since been added behind q6.

Projected finish with the serial chain: about 21:30-22:00 EDT. The steps are q3's suites ending around 14:15, then q3's A/B, then 3 h 10 min for q5, 2 h 15 min for q6 and about 1.5 h for q7.

## 2. Why the PC is idle

1. **One lane.** Each item's suites wait for the previous item's A/B, but suites do not need a quiet machine.
2. **Branch suites use the 4-core benchmark slice.** CI's 24 threads sit idle about 90 % of the day.
3. **PID chains and one shared checkout.** These force strict order, fail silently, and leave stale status text behind.
4. **RAM.** With 62 GB visible, at most about two 24 GB-capped test processes can run at once.

## 3. Recommended design

### Lane S: suites (parallel-capable, preemptible)

- One branch at a time runs the **unchanged `.github/ci/parallel.sh`** layout on 0-11/16-27: six pinned processes, the same layout CI uses. Before it, the frozen check and a one-time precompile; after it, the docs build when the item needs one. Expected time is about 25-30 min per item, against about 90 min now.
- Each item gets its **own git worktree**: `~/potts-ci/wt/<item>` from the bundle. The A/B later reads that path, so no two items share a checkout.
- Each Julia process keeps today's `systemd-run --user --scope -p MemoryMax=24G` wrapper, through `JULIA=tools/pc/julia-scoped.sh`, so `parallel.sh` itself does not change. `CPUWeight=10` is added, and `OPENVT_PACKAGE_BULK` is still exported. The cpu and memory controllers are delegated to the user slice, which I checked.
- The queue scripts keep **PID files** (`~/potts-ci/wt/<item>.pid`) as well as the scope names, so any job can still be killed by PID (standing rule).
- **It yields to CI by kill-and-requeue.** A small user service polls every 15 s for a `Runner.Worker` process (the same test `benchmark/machine.jl` uses). When one appears, it stops the running suites scope (`systemctl --user stop`, a kill by unit rather than by pattern), requeues the item, and holds the lane until the worker exits.
  - Why not freeze: a frozen process keeps its RAM and its KFD GPU handle. Eight suite files also time things (`@elapsed` and similar), so freezing them would make those tests flaky.
  - Cost: at most one lost suites run (≤ 30 min) per CI run, about 4 a day.
- Lane S never touches 12-15/28-31.

### Lane A: A/B (exclusive; D-242 unchanged)

- Before an A/B, the lane **drains** Lane S: no new starts, and it waits for the running item to finish (≤ 30 min). It does not freeze or kill.
  - Drain, not freeze: `wait_idle(gpu = true)` in `ab.jl` treats every KFD client as busy, and D-242's 7.9 % drift shows that memory-bandwidth load on 0-11 disturbs the controls even on separate cores.
- `ab.jl` runs exactly as now, with its own CI and GPU wait and the machine lock. The coordinator announces the window as D-242 requires, and Lane S is released when the A/B ends.
- **Batching (D-242).** It stays the coordinator's call for each batch. For q5 + q6 the coordinator declined (2026-10-14):
  - q6 is expected to fail frozen p6_0bk2:287, and the rng session needs those PC values;
  - the two branches were reviewed and merge separately;
  - a failed batch would need a bisect.

### The queue: pueue

- Two groups: `suites` (parallelism 1) and `ab` (parallelism 1). An item is two tasks, and the A/B task is added with `--after <suites-task>`, so it runs only if the suites pass. This replaces the `while kill -0 $(cat prev.pid)` chains.
- The A/B drain is `pueue pause --group suites --wait`, which lets the running task finish and starts nothing new. The release is `pueue start --group suites`.
- `pueue status` and `pueue log` replace the ad hoc `*-status` files. The existing status-file format can be kept as each task's own log for continuity.
- Scripts live in the repo under `tools/pc/`: `item.sh` (bundle → worktree → suites), `ab-window.sh` (drain → `ab.jl` → release) and `ci-yield.sh` (the watcher). That keeps them reviewable and versioned with `parallel.sh`.
- Fallback if pueue is not wanted: the same three scripts over a `flock`-guarded spool directory. They need no install, but they lack pueue's status, dependencies and logs.

### Expected effect (estimate)

- **Today's queue (q3, q5, q6, q7) is not migrated.** The coordinator's handover rule is not to touch it while it is live.
- On a queue like it, the suites for q5, q6 and q7 (about 25 min each, against about 90) would run on 0-11 while q3 is still in its own suites. After that only the A/Bs would be left, back to back: q3 scoped, then q5 CPU + ROCm, then q6 CPU. q7 has no A/B.
- The serial chain finishes around 21:30-22:00 tonight. The two-lane version would finish around 17:30-18:00.
- More generally, suites throughput goes up about 3.5×, and the PC's wall time becomes bound by the A/Bs, not the suites.

## 4. The other proposals

- **Scoping suites to the change (proposal 4): not recommended now.** At about 25 min, a full `parallel.sh` run costs little. Scoping would also need a new rule next to AUTONOMY §7.4 ("all must pass on the merged tree"), and its wrong-scope risk would land on CI. The one exception worth adopting: a docs-only change runs the docs build only.
- **Shrinking the VRAM carve-out (proposal 5): recommended, but as a separate change.** The queue gain does not depend on it.
  - It would move the BIOS UMA frame buffer from 64 GiB to its minimum (0.5-2 GiB) and raise GTT through kernel parameters (`ttm.pages_limit` / `amdgpu.gttsize`, sized at about 110 GiB). The OS would then see about 120 GB, so Lane S could run two items at once and P6.0cd's record-size run gets its single-GPU memory.
  - It needs a BIOS change at the machine (physical access) plus a reboot. CI and every PC job stop for that time.
  - After the reboot: a ROCm A/B same-commit control (its offset may move) and a `gate.jl rocm` check that baselines still read the same. If they do not, re-baseline under a DECISIONS entry.
- **The Mac running CPU suites (proposal 6): not recommended.** Lane S removes the bottleneck it was meant to fix, and D-157's "no intensive compute on the Mac" can stand.

## 5. Approvals needed from the maintainer

1. **Adopt the two-lane policy.** Lane S on the CI cores, preempted by CI. Lane A drains Lane S. This becomes **D-248** (the number was reserved with the coordinator) amending D-232's statement that 0-11/16-27 serve CI and FULL runs.
2. **Install pueue on the PC.** A static release binary in `~/.local/bin`, run as a user service. No root, and no apt package was found.
3. **The `ci-yield` user service** that stops Lane S scopes when a CI job starts. It never touches the runner itself, and the runner is never paused.
4. **(Separate, optional) the BIOS carve-out and GTT change**, with a date when you can be at the PC to reboot it.

## 6. Plan after approval

1. Write `tools/pc/{item.sh,ab-window.sh,ci-yield.sh}` plus a README section. Code-review them, and commit to `monorepo` in the coordinator's next push batch (D-232 push cadence).
2. Install pueue, then trial one item outside any A/B window. Record the scope's `memory.peak` to set `MemoryMax`, and confirm that kill-and-requeue works against a real CI run.
3. Switch-over happens between items, after q3, q5, q6 and q7 finish. The coordinator will leave the next item unqueued at that point. Nothing in `~/potts-ci` or `~/actions-runner` changes, and no status file is deleted, while those items are live. The old `*-run.sh` chains finish as they are; none is killed.
4. A DECISIONS entry and a PROGRESS note.
