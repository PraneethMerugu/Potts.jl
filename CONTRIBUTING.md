# Contributing

Potts.jl follows the ordinary Julia package workflow. Julia 1.12 or a later
Julia 1.x release is required.

## Test

Run the independently installable package suites from the repository root:

```sh
julia --project=. -e 'using Pkg; Pkg.test()'
julia --project=lib/CorePotts -e 'using Pkg; Pkg.test()'
julia --project=lib/MakiePotts -e 'using Pkg; Pkg.test()'
julia --project=lib/ProcessBigraphs -e 'using Pkg; Pkg.test()'
```

Run cross-package behavior with:

```sh
julia --project=integration -e 'using Pkg; Pkg.instantiate()'
julia --project=integration integration/runtests.jl
```

The package suites include Aqua checks. Published stochastic models test both
exact fixed-seed replay and seed-sensitive, bounded behavior. A random seed is
part of a reproducible run identity, not a claim that different seeds produce
the same trajectory.

## Build the documentation

Both manuals are strict Documenter builds: doctest, executable-example, and
cross-reference failures fail the command.

```sh
julia --project=docs -e 'using Pkg; Pkg.instantiate()'
julia --project=docs docs/make.jl

julia --project=lib/ProcessBigraphs/docs -e 'using Pkg; Pkg.instantiate()'
julia --project=lib/ProcessBigraphs/docs lib/ProcessBigraphs/docs/make.jl
```

The Wortel and Merks tutorials display their complete public-API programs and
generate their figures and animations with Makie during the documentation
build.

## Continuous integration

Pull requests run the four package suites, the behavioral integration suite,
small macOS and Windows installation smokes, and both documentation builds.
GPU hardware tests, benchmarks, performance comparisons, and external-link
checks are manually dispatched when relevant. Releases use the same tests and
documentation build as normal development; there is no separate evidence
refresh or one-time qualification ceremony.

Historical specifications, interviews, evidence records, and retired
qualification scripts remain under `spec/`, `design/`, and `scripts/archive/`.
They document past decisions but are not active development gates.
