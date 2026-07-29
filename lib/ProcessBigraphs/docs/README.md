# ProcessBigraphs.jl documentation

This is the independent Documenter environment for ProcessBigraphs.jl.

From the repository root:

```sh
julia --project=lib/ProcessBigraphs/docs -e 'using Pkg; Pkg.instantiate()'
julia --project=lib/ProcessBigraphs/docs lib/ProcessBigraphs/docs/make.jl
```

The build is strict: doctest, executable-example, and cross-reference failures
are errors. Every executable manual page displays and evaluates the same
complete program stored under `models/`; reader-facing pages do not hide model
construction behind `include`.

The Wortel and Merks case studies use public package APIs, exercise fixed-seed
stochastic runs, and generate their native Makie figures and animations during
the build. Generated output lives in `docs/build/` and is ignored.

External-link checking is intentionally optional because network failures
should not block an ordinary code change. Run it with:

```sh
PROCESS_BIGRAPHS_DOCS_LINKCHECK=true \
  julia --project=lib/ProcessBigraphs/docs lib/ProcessBigraphs/docs/make.jl
```

Historical browser baselines and phase specifications are retained for
provenance, but they are not release or pull-request gates.
