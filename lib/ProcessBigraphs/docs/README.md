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

## Rendered-site checks

The pull-request gate intentionally stays small: it builds both manuals and
runs the ProcessBigraphs route, interaction, and accessibility suite in
Chromium. This is the normal feedback loop.

Release-grade rendered-site qualification is deliberately separate. A version
tag, or a manual **Documentation** workflow dispatch with
`full_qualification` enabled, runs:

- Chromium, Firefox, and WebKit;
- the pinned Lighthouse budget; and
- Chromium visual regression.

A version tag additionally regenerates clean-install evidence on Linux, macOS,
and Windows. A manual rendered-site dispatch reuses the already-qualified
platform evidence instead of repeating three unrelated jobs.

Run the same browser profiles locally from `docs/browser` with:

```sh
pnpm test --project=chromium
pnpm test --project=chromium --project=firefox --project=webkit
pnpm lighthouse
pnpm test:visual
```

Generated integrity inventories are maintained evidence, not ordinary PR
blockers. Check or refresh them explicitly with
`scripts/check_project_baseline_freshness.jl` and
`scripts/update_project_integrity_baselines.jl`.
