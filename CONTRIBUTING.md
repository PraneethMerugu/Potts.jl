# Contributing to Potts.jl

Potts.jl is a single Julia workspace (`Project.toml` `[workspace]`) that requires Julia 1.12 or later.
The workspace keeps one gitignored `Manifest.toml` at the repository root. Never commit a `Manifest.toml` or a nested `[workspace]`.

## Test suites and `test_groups.toml`

Each test directory declares its groups in `test_groups.toml` (`test/test_groups.toml` and `lib/<Pkg>/test/test_groups.toml`).
`test/runtests.jl` dispatches the `GROUP` environment variable against those tables and rejects unknown names with `ArgumentError`.

```sh
GROUP=Potts julia --project=test test/runtests.jl
```

| `GROUP` | Scope |
|---|---|
| `All` (default) | All `in_all = true` packages (`LatticeFields`, `LatticePDE`, `CorePotts`, `MakiePotts`, `Potts`, `PottsModels`) |
| `Potts`, `CorePotts`, `LatticeFields`, `LatticePDE`, `MakiePotts`, `PottsModels` | All `in_all = true` groups of that package |
| `<Sublib>_<group>` | One group in `Potts` or `lib/<Sublib>` |
| `GPU` | Device suites across `LatticeFields_gpu`, `CorePotts_gpu`, `LatticePDE_gpu`, and `Potts_gpu` (`POTTS_GPU=metal\|rocm`); `PottsModels_gpu` is opt-in |
| `Multithreaded` | 4-thread checkerboard and `cell_sums` invariants (`julia -t 4`) |

Common `GROUP=<Sublib>_<group>` selectors:

- `Potts_*`: `Potts_core`, `Potts_fields`, `Potts_symbolic`, `Potts_qa`, `Potts_gpu`, `Potts_All`
- `CorePotts_*`: `CorePotts_core`, `CorePotts_qa`, `CorePotts_gpu`, `CorePotts_All`
- `LatticeFields_*`: `LatticeFields_exec`, `LatticeFields_ir`, `LatticeFields_compile`, `LatticeFields_schedule`, `LatticeFields_problems`, `LatticeFields_solvers`, `LatticeFields_qa`, `LatticeFields_solvers_gate`, `LatticeFields_gpu`, `LatticeFields_All`
- `LatticePDE_*`: `LatticePDE_core`, `LatticePDE_qa`, `LatticePDE_gpu`, `LatticePDE_All`
- `MakiePotts_*`: `MakiePotts_core`, `MakiePotts_qa`, `MakiePotts_acceptance`, `MakiePotts_adversarial`, `MakiePotts_allocations`, `MakiePotts_downstream_conformance`, `MakiePotts_saved_state_channels`, `MakiePotts_visual`, `MakiePotts_All`
- `PottsModels_*`: `PottsModels_core`, `PottsModels_qa`, `PottsModels_acceptance`, `PottsModels_reproductions`, `PottsModels_guardrails`, `PottsModels_gpu` (opt-in), `PottsModels_All`

See [test/README.md](test/README.md) for per-package environment variables (`POTTS_TEST_WORKERS`, `POTTS_QA`, `POTTSMODELS_SHARD`, `*_TEST_NAME`).

## Fast local loop (`test/dev.jl`)

Start an interactive `Revise` and `ReTestItems` session from the repository root to rerun individual `@testitem`s without restarting Julia:

```sh
julia --project=test -i test/dev.jl
```

```julia
ti("F4-E5")                    # items whose name contains "F4-E5"
ti(r"^F3-17: a Coarse")        # items whose name matches a regex
ti(; tags = :fields_coarse)    # items carrying a tag
ti("F4-E7"; nworkers = 1)      # run in a fresh worker process
tf("fields_short_tests.jl")    # all items in one file
```

Re-run via `test/runtests.jl` before pushing; a long interactive session can retain mutated state.

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
