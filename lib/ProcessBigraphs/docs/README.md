# ProcessBigraphs.jl documentation

This is the independent, pinned documentation environment for the
ProcessBigraphs internal beta. It builds only the 35 curated pages registered in
`spec/process-bigraph-phase17-documentation-quality-v1.toml`.

From the repository root:

```sh
julia --project=lib/ProcessBigraphs/docs -e 'using Pkg; Pkg.instantiate()'
julia --project=lib/ProcessBigraphs/docs lib/ProcessBigraphs/docs/make.jl
```

Every executable manual page displays and evaluates the same complete program
stored under `models/`. Reader-facing pages never use `include`. Generated
assets are checked against `assets/provenance.toml`; deployment is disabled
unless an explicit GitHub Actions-only environment flag is present.
