# PC job queue (D-248)

Branch checks on the PC (D-157) run in two lanes of a [pueue](https://github.com/Nukesor/pueue) queue. The queue is installed on the PC at `~/potts-queue` (a copy of this directory), with `pueue`/`pueued` 4.0.4 in `~/.local/bin`, and the daemon runs as the user service `pueued.service`.

| Lane | pueue group | Cores | Runs | Gives way to |
|---|---|---|---|---|
| S: suites | `suites`, one at a time | 0-11/16-27 (D-232's `parallel.sh` layout) | `item.sh`: instantiate, frozen check, `.github/ci/parallel.sh`, optional docs and extras | CI (kill and re-run the step), an A/B (drain) |
| A: A/B | `ab`, one at a time | 12-15/28-31 (`ab.jl`'s own pinning) | `ab.sh`: drains lane S, then `benchmark/ab.jl` | nothing; D-242 quiet window |

## Queueing an item

```bash
P=~/.local/bin/pueue
# the coordinator fetches the bundle into ~/potts-full first; item.sh makes ~/potts-ci/<item> from it
s=$($P add -p -g suites -l q8 -- ~/potts-queue/item.sh q8 <commit> --docs)
$P add -g ab -l q8-cpu --after $s -- ~/potts-queue/ab.sh q8 ~/potts-ci/<base> ~/potts-ci/q8 all cpu
```

- `--after` runs the A/B only if the suites pass. A suites step that CI interrupts is re-run inside the same task, so the task does not fail because of CI.
- Use `--extra '<command>'` for steps beyond the standard suites, such as one ROCm acceptance file. Each extra runs from the checkout, pinned to 0-11/16-27, and `$JULIA` is the scoped wrapper.
  - pueue joins everything after `--` into one `sh -c` string, so inner quotes are lost unless the whole command is passed as a single quoted string:

    ```bash
    pueue add -p -g suites -l q9 -- "$HOME/potts-queue/item.sh q9 <commit> --extra 'julia --project=lib/PottsModels/test path/to/file.jl'"
    ```

    Unquoted, `item.sh` exits 64 ("unknown argument"), as q14 did on 2026-10-15.
- The base checkout of an A/B must exist and be instantiated. `ab.jl` creates the `-abctl` worktrees itself.

## Watching and stopping

- `pueue status` and `pueue log <id>`. The per-item files in `~/potts-ci` keep the old names: `<item>-status`, `<item>-<step>.log` and `<item>-ci-logs/`.
- Kill by PID file, never by pattern:
  - `kill -- -$(cat ~/potts-ci/<item>-step.pid)` stops the running step's process group;
  - `~/potts-ci/<item>-run.pid` holds the item script itself;
  - alternatively, use `pueue kill <id>`.
- **Holding lane S by hand.** For an A/B or a screen started outside the queue, run `pueue pause --group suites --wait` and wait until `pueue status` shows no suites task running. Create `~/potts-ci/lane-s.hold` so `ab.sh` does not release the lane, and later remove the file and run `pueue start --group suites`.

## Setup

`setup.sh` is idempotent. It writes the pueue config (a fixed socket path, so ssh clients without `XDG_RUNTIME_DIR` reach the daemon) and the user unit, and creates both groups with parallelism 1.
