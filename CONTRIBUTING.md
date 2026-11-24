# Contributing to Potts.jl

Potts.jl is a single Julia workspace (`Project.toml` `[workspace]`) that requires Julia 1.12 or later.
The workspace keeps one gitignored `Manifest.toml` at the repository root. Never commit a `Manifest.toml` or a nested `[workspace]`.

## Test suites and `test_groups.toml`

Every package runs its tests with one runner, `test/runner/PottsTestRunner.jl`. Each test directory declares its groups in `test_groups.toml` (`test/test_groups.toml` and `lib/<Package>/test/test_groups.toml`).
Environment variables choose what runs, with the same names in every package; an unknown `GROUP` throws an `ArgumentError`.

```sh
GROUP=Potts julia --project=test test/runtests.jl
POTTS_TEST_NAME="coarse field" GROUP=Potts julia --project=test test/runtests.jl
```

| `GROUP` | Scope |
|---|---|
| `All` (default) | `LatticeFields`, `LatticePDE`, `CorePotts`, `MakiePotts`, `Potts`, `PottsModels` |
| `Potts` | Every item of `test/` |
| `CorePotts`, `LatticeFields`, `LatticePDE`, `MakiePotts`, `PottsModels` | The `All` group of that package |
| `<Package>_<group>` | One group of `lib/<Package>/test` (for example `CorePotts_qa`, `LatticeFields_solvers`, `PottsModels_acceptance`) |
| `Potts_core`, `Potts_fields`, `Potts_symbolic`, `Potts_qa`, `Potts_gpu` | Parts of `Potts` |
| `GPU` | `LatticeFields_gpu`, `LatticePDE_gpu`, `CorePotts_gpu` and `Potts_gpu` on one device (`POTTS_GPU=metal\|rocm`); `PottsModels_gpu` is opt-in |
| `Multithreaded` | 4-thread checkerboard and `cell_sums` invariants (`julia -t 4`) |

The other variables are `POTTS_TEST_NAME`, `POTTS_TEST_TAGS`, `POTTS_TEST_QA`, `POTTS_TEST_WORKERS`, `POTTS_TEST_SHARD` and `POTTS_GPU`. [test/README.md](test/README.md) describes them, the groups of each package, and the `test_groups.toml` schema.

## Fast local loop (`test/runner/session.jl`)

Start a warm session to rerun individual `@testitem`s without restarting Julia. Test titles are plain descriptions, so select items by words in their titles, by a regex, or by tag:

```sh
julia --project=test -i test/runner/session.jl
```

```julia
run_tests(name = "coarse field")             # items whose name matches "coarse field"
run_tests(name = r"^a Coarse\(4\)")          # a regex
run_tests(tags = :fields_coarse)             # the items with a tag
run_tests(file = "fields_short_tests.jl")    # every item of one file
run_tests(name = "is_kind", workers = 1)     # in a fresh worker process
```

The same file starts a session for a package: `julia --project=lib/CorePotts/test -i test/runner/session.jl`. Revise picks up `src` edits when it is on the load path. Rerun through `runtests.jl` before you push: a long session can keep state that tests changed.

## Bounds checking (`--check-bounds`)

`test/runtests.jl` launches sublibrary runners with `--check-bounds=auto` unless the parent process sets `--check-bounds=yes` or `--check-bounds=no`.
Run with `--check-bounds=yes` when changing indexing, kernel bounds, or lattice layouts:

```sh
GROUP=LatticeFields julia --check-bounds=yes --project=test test/runtests.jl
```

CI runs `LatticeFields` under `--check-bounds=yes` on every push to `monorepo`.

## Multithreaded tests (`-t 4`)

Run the multithreaded group with 4 Julia threads:

```sh
GROUP=Multithreaded julia -t 4 --project=test test/runtests.jl
```

## QA checks

Run the QA group of any package you touch:

```sh
GROUP=Potts_qa julia --project=test test/runtests.jl
GROUP=CorePotts_qa julia --project=test test/runtests.jl
GROUP=LatticeFields_qa julia --project=test test/runtests.jl
GROUP=LatticePDE_qa julia --project=test test/runtests.jl
GROUP=MakiePotts_qa julia --project=test test/runtests.jl
GROUP=PottsModels_qa julia --project=test test/runtests.jl
```

The unified 6-package QA suites check `Aqua.jl` hygiene (including method ambiguities), `JET.jl` type stability, `AllocCheck.jl` zero-allocation hot paths, `ExplicitImports.jl` clean imports with extension loading, `Docs.undocumented_names` plus `docs/src` API documentation coverage, and core-package model-name and host-transfer guards.

## Formatting (`Runic.jl`)

The repository adopts [Runic.jl](https://github.com/fredrikekre/Runic.jl) for new and modified Julia code (matching `lib/MakiePotts/CONTRIBUTING.md`).
Format only the Julia files you edit; do not mechanically reformat unrelated files in feature or bugfix PRs.

```sh
runic --check --diff path/to/changed_file.jl
runic --inplace path/to/changed_file.jl
```

## Tracking known failures (`@test_broken`)

Never weaken tolerances, add version gates, or pin incidental literals to keep a broken test green.
Mark an unresolved, tracked failure with `@test_broken` and an adjacent comment naming the tracking issue (or `deviations.tsv` entry for paper reproductions) so CI keeps running the remaining checks and reports if the test starts passing.

## Documentation and doctests

Build the documentation and run all doctests offline from the repository root:

```sh
julia --project=docs docs/make.jl
```

Follow [docs/design/STYLE.md](docs/design/STYLE.md) for prose, docstrings, and terminology (American spelling, no em dashes).

## CI workflows

- `.github/workflows/ci.yml`: runs on pushes to `monorepo` (ignoring `docs/design/**`) using the self-hosted ROCm runner, including parallel CPU suites (`PottsModels` in 3 shards, `Potts`, `LatticeFields`, `LatticePDE`, `CorePotts`, `MakiePotts`), the ROCm `GPU` suite, benchmark tooling tests, `LatticeFields` under `--check-bounds=yes`, and a non-gating coverage summary (`.github/ci/coverage_summary.jl`).
- `.github/workflows/docs.yml`: builds documentation and runs doctests (`doctest = true`) on pushes to `monorepo` in its own concurrency group so docs failures never mask test failures.
- `.github/workflows/compat-1.12.yml`: runs `GROUP=Potts` and `GROUP=PottsModels` on Julia 1.12 on a weekly schedule and manual dispatch. Julia 1.10 LTS is out of range because `Project.toml` sets `compat julia = "1.12"`.
