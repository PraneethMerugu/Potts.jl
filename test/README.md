# The Potts test suite

The tests of `src/` (package `Potts`) are [ReTestItems](https://github.com/JuliaTesting/ReTestItems.jl)
test items: every `*_tests.jl` file in this directory holds `@testitem`s, and the models and
helpers they share are `@testsetup` modules. The lib packages (`lib/*/test`) keep their own
runners.

## Run the suite

```sh
GROUP=Potts julia --project=test test/runtests.jl
```

`test/runtests.jl` maps the `GROUP` values of CI to sets of items:

| GROUP | Potts items that run |
|---|---|
| `Potts`, `All` | tagged `:potts`, not `:gpu`; `:qa` too unless `POTTS_QA=false` |
| `GPU` | tagged `:device` or `:gpu` (`:rocm` only on ROCm), with `POTTS_GPU` set, one worker |

The items run on `POTTS_TEST_WORKERS` worker processes (default 4), one thread each. All
workers share the memory limit of the run: a worker restarts after an item when the memory in
use is above 80 % of the limit, and an item that runs longer than 20 min fails
(`test/shared/rti.jl`). Items tagged `:timing` (they time code in-process) or `:subprocess`
(they start Julia processes) run after the others, one at a time.

`POTTS_TEST_PASSLOG=<file>` appends one line per top-level testset of each item: item,
testset, and the counts of pass, fail, error and broken results.

`POTTS_TEST_WORKERS=0` runs the items in this process instead of in worker processes. Measure
line coverage that way (`--code-coverage=@$PWD`): every worker writes its own `.cov` files, so
the per-line record of a worker run is an artifact of which process exited last.

## Run some items

In a session that keeps its compiled code between runs (Revise picks up `src` edits):

```sh
julia --project=test -i test/dev.jl
```

```julia
ti("F4-E5")                    # items whose name contains "F4-E5"
ti(r"^F3-17: a Coarse")        # items whose name matches a regex
ti(; tags = :fields_coarse)    # the items of fields_coarse_tests.jl
ti("F4-E7"; nworkers = 1)      # in a fresh worker process
tf("fields_short_tests.jl")    # every item of one file
```

Revise must be in an environment on the load path (for example your default environment). The
VS Code test explorer also runs single `@testitem`s.

## Tags

- `:potts`: every item of this directory.
- the file's name without `_tests.jl` (for example `:fields_coarse`).
- `:qa`: Aqua, JET, ExplicitImports and the other quality checks (qa_tests.jl).
- `:gpu`: the device files (gpu_tests.jl, transfer_counts_tests.jl, device_ir_tests.jl); `:rocm`: ROCm only.
- `:device`: an item that names a device; it also runs in GROUP=GPU.
- `:device_scan`: the D-157 no-`double` scan; it runs last in GROUP=GPU, in the process that
  compiled the kernels (`PottsRTI.device_suite`).
- `:gpu_only`: an item that cannot run in a fresh worker (the scan reads the process cache);
  GROUP=GPU without `POTTS_DEVICE_ONLY=false` only.
- `:timing`, `:subprocess`: run serially (see above).

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
