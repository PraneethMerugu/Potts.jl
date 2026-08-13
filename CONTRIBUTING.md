# Contributing

Potts.jl follows the ordinary Julia package workflow. Julia 1.12 or a later
Julia 1.x release is required.

## Test

Run the independently installable package suites from the repository root:

```sh
julia --project=. -e 'using Pkg; Pkg.test()'
julia --project=lib/CorePotts -e 'using Pkg; Pkg.test()'
julia --project=lib/LocalWorksets -e 'using Pkg; Pkg.test()'
julia --project=lib/MakiePotts -e 'using Pkg; Pkg.test()'
```

Run cross-package behavior with:

```sh
julia --project=integration -e 'using Pkg; Pkg.instantiate()'
julia --project=integration integration/runtests.jl
```

The fail-closed native replay suite is qualified on Julia 1.12.1 with the
exact dependency versions in `integration/Project.toml`. The PottsToolkit,
CorePotts, and LocalWorksets package suites are qualified on macOS/Apple M1
with Julia 1.12.6 because they exercise reviewed LocalWorksets evidence;
LocalWorksets' real-Metal evidence uses that same Julia minor. Use those exact
environments for qualification commands. Source portability does not create
a new runtime evidence row.

The package suites include Aqua checks. Published stochastic models test both
exact fixed-seed replay and seed-sensitive, bounded behavior. A random seed is
part of a reproducible run identity, not a claim that different seeds produce
the same trajectory.

## Format Julia changes

This repository adopts [Runic](https://github.com/fredrikekre/Runic.jl) for
new and modified Julia code. During incremental adoption, check only the files
you touched; do not mechanically reformat the repository as part of an
unrelated change. With Runic 1 installed as a Julia app, check explicit files
without modifying them:

```sh
runic --check --diff path/to/file.jl another/file.jl
```

Use `runic --inplace` on those same explicit paths to apply formatting. A
future dedicated baseline commit may extend the check to all tracked Julia
files.

## Build the documentation

The temporary pre-1.0 status manual uses a strict Documenter build: doctest, executable-example,
and cross-reference failures fail the command. Legacy `PottsModel` Learn, Examples, and API pages
remain draft rewrite material and are excluded from active navigation.

```sh
julia --project=docs -e 'using Pkg; Pkg.instantiate()'
julia --project=docs docs/make.jl
```

The strict final-interface manual includes executable serial Wortel and Merks
programs and their Makie output. Those are product-integration witnesses, not
paper-source scientific reproductions.

## Continuous integration

Pull requests target the four package suites, the behavioral integration suite, applicable
platform installation smokes, and the active documentation build.
GPU hardware tests, benchmarks, performance comparisons, and external-link
checks are manually dispatched when relevant. Releases use the same tests and
documentation build as normal development; there is no separate evidence
refresh or one-time qualification ceremony.

Current specifications and decisions live under `spec/`. Historical interviews and evidence under
`design/audits/`, and retired qualification scripts under `scripts/archive/`, document earlier
repository states but are not active development gates.
