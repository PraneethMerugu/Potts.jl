# The Potts test suites

Every package of the monorepo keeps its tests in its own test environment: `test/` for
`Potts` (the `src/` package) and the monorepo as a whole, and `lib/<Package>/test/` for each
package in `lib/`. The tests are [ReTestItems](https://github.com/JuliaTesting/ReTestItems.jl)
test items: every `*_tests.jl` file holds `@testitem`s, and the models and helpers that they
share are `@testsetup` modules or files in `shared/`.

One runner runs them all: `test/runner/PottsTestRunner.jl`. CI, the gate scripts, people at a
REPL and agents call the same function, `run_tests`, and choose what runs with the same
environment variables.

## Layout

```
test/
  runtests.jl            # the monorepo's tests: calls PottsTestRunner.run_tests
  test_groups.toml       # the groups of the monorepo's tests
  runner/
    PottsTestRunner.jl   # the runner of every package
    session.jl           # a warm REPL session: Revise and the runner
  shared/                # fixtures that the items of test/ share
  *_tests.jl             # the items of Potts
  device_coverage.jl     # the ROCm check at the end of GROUP=GPU
lib/<Package>/test/
  runtests.jl            # calls the same runner with this directory
  test_groups.toml       # the groups of this package
  shared/                # fixtures that the items of this package share
  *_tests.jl
```

## Run tests

```sh
julia --project=test test/runtests.jl                                  # GROUP=All
GROUP=Potts julia --project=test test/runtests.jl                      # the Potts suite
GROUP=CorePotts_qa julia --project=test test/runtests.jl               # one group of a package
GROUP=qa julia --project=lib/CorePotts/test lib/CorePotts/test/runtests.jl   # the same group
POTTS_TEST_NAME="coarse field" GROUP=Potts julia --project=test test/runtests.jl
```

The environment variables choose what runs. Every package reads the same names.

| Variable | What it selects | Default |
|---|---|---|
| `GROUP` | a group of the package's `test_groups.toml` or `All`; at the root also `<Package>_<group>` | `All` |
| `POTTS_TEST_NAME` | the items whose name matches this regex | every item |
| `POTTS_TEST_TAGS` | the items with any of these tags (a comma list) | every item |
| `POTTS_TEST_QA` | `false` (or `0`) skips the `:qa` items and drops the qa groups from `All`; a qa group named in `GROUP` still runs | `true` |
| `POTTS_TEST_WORKERS` | the number of worker processes; `0` runs the items in the calling process | the package's `workers` |
| `POTTS_TEST_SHARD` | `k/n` with 1 ≤ k ≤ n: only the k-th of n shards of the test files | `1/1` |
| `POTTS_GPU` | the device backend: `rocm`, `metal`, or empty for no device | empty |

These variables are for tools and logs:

| Variable | What it does |
|---|---|
| `POTTS_TEST_ORDER` | the order of the test files: `default`, `reverse`, or `random[:seed]` |
| `POTTS_TEST_PASSLOG` | a file that gets one line per top-level testset of each item: item, testset, and the counts of pass, fail, error and broken results |
| `POTTS_TEST_END_EXPR_FILE` | a file with one Julia expression that runs after every item |
| `POTTS_DEVICE_IR_DIR` | the directory of the device code that GROUP=GPU scans (a temporary directory when not set) |

Each runner takes one form of group name. A package's runner (`lib/<Package>/test`) takes
the plain names of its own table, for example `GROUP=qa`. The root runner takes its own
groups and `<Package>_<group>` for a group of a package that it runs, for example
`GROUP=CorePotts_qa`. An unknown `GROUP` throws an `ArgumentError` that lists the valid
groups of that runner.

A qa group is a group whose `tags` name `qa`. With `POTTS_TEST_QA=false`, `GROUP=All` leaves
out the qa groups, and the other groups skip their `:qa` items. A qa group named in `GROUP`
(`GROUP=qa`, `GROUP=PottsModels_qa`) runs its items whatever `POTTS_TEST_QA` says.

A `runtests.jl` takes at most one command-line argument: an item-name pattern, the same as
`POTTS_TEST_NAME`. This is the form in which `Pkg.test(; test_args)` and the Kaimon
`run_tests` tool pass a pattern. `GROUP` and the other selections are environment variables
only. When both the argument and `POTTS_TEST_NAME` are set, the run throws an
`ArgumentError`. A selection that matches no item logs `0 test items match the selection`
and passes.

```sh
julia --project=lib/CorePotts/test lib/CorePotts/test/runtests.jl geometry
```

### Kaimon's `run_tests`

The Kaimon MCP tool `run_tests(project_path, pattern)` is a supported route. It runs
`runtests.jl` of the package's test environment with the pattern as the argument;
`project_path` is the package root (the repository root, or `lib/<Package>`). Its summary
counts the results of the calling process only, so at the root (the default `GROUP=All`)
it counts the Potts items, and a package's subprocess shows only as a failure of the run.
On the PC, Kaimon starts Julia through `~/potts-queue/kaimon-julia.sh`, which waits while
an A/B, a CI job or a gate runs, then runs on the gate cores in the 24G scope.

A group of another package runs in a subprocess, in that package's test environment, with
the same variables. The subprocess gets `--check-bounds=auto` unless the caller set
`--check-bounds=yes` or `--check-bounds=no`.

### The groups of the monorepo

| GROUP | What runs |
|---|---|
| `All` (default) | `LatticeFields`, `LatticePDE`, `CorePotts`, `MakiePotts`, `Potts` and `PottsModels`, in that order |
| `Potts` | the `:potts` items: every item of `test/` |
| `Potts_core`, `Potts_fields`, `Potts_symbolic` | parts of `Potts` without the `:qa` items, chosen by file tag |
| `Potts_qa` | the `:qa` items of `Potts` |
| `Potts_gpu` | the items of `Potts` that name a device (`:device`) and the device files' items (`:gpu`), on one device |
| `Multithreaded` | the `:multithreaded` items, in the calling process; run with `julia -t 4` |
| `GPU` | `LatticeFields_gpu`, `LatticePDE_gpu`, `CorePotts_gpu` and `Potts_gpu` on one device (`POTTS_GPU`, else the platform's), without the `:qa` items; on ROCm, then `device_coverage.jl` |
| `<Package>` | the `All` group of `lib/<Package>/test` |
| `<Package>_<group>` | one group of `lib/<Package>/test` |

The groups of each package are in its `test_groups.toml`.

## Workers, threads and time limits

The items run on worker processes, one item at a time on each worker. The defaults fit the
24G memory scope of a run:

| Package | Workers | Threads per worker | Time limit per item |
|---|---|---|---|
| `Potts` (`test/`) | 4 | 1 | 20 min |
| `CorePotts`, `LatticeFields`, `LatticePDE` | 3 | the caller's | 60 min |
| `MakiePotts` | 2 | the caller's | 60 min |
| `PottsModels` | 0 (the calling process) | the caller's | 120 min |

`POTTS_TEST_WORKERS` replaces the number of workers in every package. A group that needs the
calling process (`Multithreaded`) and a group with `device = true` use no workers. With
`POTTS_GPU` set, the other groups keep their workers for the items that do not use the
device; the items that do run in the calling process (passes 3 and 4 below).

At the root, a worker restarts after an item when the memory in use is above 80 % of the
limit. The runner does not retry a failed item.

Each run has up to five passes, in this order:

1. every selected item that is not in the next passes;
2. the `:timing` items (they time code in the process) and the `:subprocess` items (they
   start Julia processes): one at a time, on at most one worker;
3. with a device selected, the items that use it (`:gpu`, `:gpu_only`, `:device`): in the
   calling process;
4. the device items of pass 3 that are `:timing` or `:subprocess`: in the calling process;
5. the `:device_scan` items: in the calling process, which compiled the device code of the
   earlier passes.

A pass with no items is skipped. When a pass fails, the next passes still run, and the run
throws the first error.

`POTTS_TEST_WORKERS=0` also gives the line coverage of a run (`--code-coverage=@$PWD`): with
workers, every worker writes its own `.cov` files, and the record of a line depends on which
process exited last.

## The `test_groups.toml` schema

The settings at the top of the file apply to every group of the package:

| Key | Meaning |
|---|---|
| `all` | the groups of `GROUP=All`, in order (required) |
| `workers` | the number of workers when `POTTS_TEST_WORKERS` is not set |
| `worker_threads` | the threads of each worker (default: the caller's) |
| `testitem_timeout` | seconds before an item fails (default 3600) |
| `memory_threshold` | the memory fraction above which a worker restarts after an item |
| `logs` | the ReTestItems `logs` mode |

Each table is a group. A group has one of three forms.

- A group of items. It selects with `tags` (items with any of these tags; every item when
  absent; a group whose `tags` name `qa` is a qa group), `exclude_tags`, and the file rules `dirs` (the files under these directories),
  `files` and `exclude_files`. The keys `device = true` (the group runs on a device),
  `workers` (a fixed worker count) and `min_threads` (the caller needs at least this many
  threads) set how it runs. A group with file rules runs alone; other consecutive groups
  run as one ReTestItems run.
- `package = "<Package>"`: the `All` group of `lib/<Package>/test`, in a subprocess.
- `groups = [...]`: these groups in turn. With `device = true` they share one device; with
  `qa = false` they skip the `:qa` items; `rocm_check` names a script that runs last, on
  ROCm only.

A runner checks every key and throws an `ArgumentError` on one it does not know.

## Run some items in a warm session

A session keeps its compiled code between runs:

```sh
julia --project=test -i test/runner/session.jl
julia --project=lib/CorePotts/test -i test/runner/session.jl
```

```julia
run_tests(name = "coarse field")             # items whose name matches "coarse field"
run_tests(name = r"^a Coarse\(4\)")          # a regex
run_tests(tags = :fields_coarse)             # the items with a tag
run_tests(file = "fields_short_tests.jl")    # every item of one file (no group, no shard)
run_tests(name = "is_kind", workers = 1)     # in a fresh worker process
```

The keywords of `run_tests` override the variables: `group`, `name`, `tags`, `file`, `qa`,
`workers` and `shard`. `file` runs every selected item of one file and ignores `group` and
`shard`. `shard` is a tuple `(k, n)` of integers; any other value throws an
`ArgumentError`. A `Regex` name keeps its flags (`i`, `m`, `s`, `x`) when it passes to a
package's subprocess. In a session, the items run in the session's process
(`POTTS_TEST_WORKERS=0`), and at the root `GROUP` is `Potts`, so that a name selects among
the Potts items and starts no subprocess. Set either variable before you load the file to
choose otherwise.

The test files are read again on every call. Revise picks up `src` edits when it is on the
load path (for example in your default environment); the session warns when it is not. The
items share one process, so state that an item changes stays for the next call. Results that
you report come from a fresh process (`runtests.jl`).

Agents use the same session through the Kaimon MCP server: one session per test
environment, which loads `test/runner/session.jl` with its first `ex`, then calls
`run_tests`. For a result from a fresh process, agents use Kaimon's `run_tests` tool
(above). The VS Code test explorer also runs single `@testitem`s.

## Tags

- `:potts`: every item of `test/`; `:corepotts` and `:latticepde`: every item of those
  packages.
- The file's name without `_tests.jl` (for example `:fields_coarse`).
- `:qa`: Aqua, JET, ExplicitImports and the other quality checks.
- `:gpu`: the items of a device file (`gpu_tests.jl`, `transfer_counts_tests.jl`,
  `device_ir_tests.jl`); `:rocm`: on ROCm only.
- `:gpu_only`: an item that runs only on a device.
- `:device`: an item that names a device; it also runs in `GROUP=GPU`. In a package with
  workers, every item that uses the device when `POTTS_GPU` is set carries `:device`,
  `:gpu` or `:gpu_only`, so that it runs in the calling process. (PottsModels runs every
  item in the calling process; its acceptance items use the device untagged.)
- `:device_scan`: the scan for `double` in the device code; it runs last, in the process
  that compiled the kernels.
- `:multithreaded`: an item that needs four threads; only a group that names this tag runs
  it.
- `:timing`, `:subprocess`: they run in the second pass.

An item with `:gpu` or `:gpu_only` runs only when a device is selected (`POTTS_GPU` set, or
a group with `device = true`). With `POTTS_GPU` set, these items join any run: `POTTS_GPU=rocm
GROUP=All` runs every suite on ROCm.

## Write an item

- An item sees `Test`, the names of the setups it declares (`setup = [...]`), and nothing
  else. Each setup ends with `include(joinpath(@__DIR__, "shared", "export_visible.jl"))`,
  which exports every name visible in it (its definitions and its `using`s), so its items
  see the namespace of the setup.
- A setup used by the items of one file stays in that file. A setup used by several files is
  a `*_testsetup.jl` file (`couple_testsetup.jl`, `fields_testsetup.jl`,
  `implicit_testsetup.jl`, `ports_testsetup.jl`).
- Two setups that one item declares must not define the same name: Julia resolves neither.
- Do not read or write `Main`, and do not depend on another item having run. A warning
  with `maxlog = 1` is shown once per process, and a worker runs many items: assert it
  with `@test_logs` (its logger counts afresh), not by counting earlier output.
- Keep each top-level `@testset` inside its `@testitem`, so the results nest as before.
