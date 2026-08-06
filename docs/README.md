# Potts.jl documentation

Status: temporary pre-1.0 hardening manual

The active build is intentionally limited to the current architecture, runtime boundary, and
capability status. The previous Learn, Examples, and API corpus uses the retired `PottsModel`
surface. Those Markdown files remain rewrite material but are excluded from active navigation and
are not support or compatibility claims.

G5H-5 rebuilds the complete executable manual against the final `PottsSystem` lifecycle, including
serial Wortel and Merks authoring/integration programs on the target Mac.

## Build locally

From the repository root:

```bash
julia --project=docs --startup-file=no -e 'using Pkg; Pkg.instantiate(; julia_version_strict=true)'
julia --project=docs --startup-file=no docs/make.jl
```

The active status build remains strict: doctest, example, and cross-reference failures are errors.
`docs/build/` is generated and ignored.

## Source-of-truth rules

- The normative specification and accepted decisions outrank implementation and documentation.
- Export status is not a stability or scientific-support claim.
- Backend compatibility and scientific qualification are documented separately.
- A draft page excluded from `docs/make.jl` is not user-facing documentation.
- When the complete manual returns, every user-facing example must use the final public spelling
  and run in the documentation build.
- Literature-derived examples disclose provenance. Only admitted, evidence-backed work appears
  under Published Models.
