# Contributing

Potts.jl follows the ordinary Julia package workflow. Julia 1.12 or a later
Julia 1.x release is required.

## Test

Run the independently installable package suites from the repository root:

```sh
julia --project=. -e 'using Pkg; Pkg.test()'
julia --project=lib/CorePotts -e 'using Pkg; Pkg.test()'
julia --project=lib/MakiePotts -e 'using Pkg; Pkg.test()'
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

The temporary pre-1.0 status manual uses a strict Documenter build: doctest, executable-example,
and cross-reference failures fail the command. Legacy `PottsModel` Learn, Examples, and API pages
remain draft rewrite material and are excluded from active navigation.

```sh
julia --project=docs -e 'using Pkg; Pkg.instantiate()'
julia --project=docs docs/make.jl
```

The full final-interface manual, including serial Wortel and Merks programs and their Makie output,
is a G5H-5 qualification deliverable and must not be claimed before that gate passes.

## Continuous integration

Pull requests target the three package suites, the behavioral integration suite, applicable
platform installation smokes, and the active documentation build.
GPU hardware tests, benchmarks, performance comparisons, and external-link
checks are manually dispatched when relevant. Releases use the same tests and
documentation build as normal development; there is no separate evidence
refresh or one-time qualification ceremony.

Current specifications and decisions live under `spec/`. Historical interviews and evidence under
`design/audits/`, and retired qualification scripts under `scripts/archive/`, document earlier
repository states but are not active development gates.
