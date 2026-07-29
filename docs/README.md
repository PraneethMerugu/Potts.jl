# Potts.jl documentation

The manual is organized by reader intent:

1. **Learn** — a guided path from installation through analysis and visualization.
2. **Examples** — small reusable programs demonstrating implemented behavior.
3. **Published Models** — evidence-backed reproductions that pass the separate admission contract.
4. **Concepts and Guarantees** — architecture, semantics, support boundaries, and scientific claims.
5. **API** — package reference material.

## Build locally

From the repository root:

```bash
julia --project=docs --startup-file=no -e 'using Pkg; Pkg.instantiate(; julia_version_strict=true)'
julia --project=docs --startup-file=no docs/make.jl
```

The build is strict: doctest, example, and cross-reference failures are errors. `docs/build/` is
generated and ignored.

## Check the accepted quality target

The accepted documentation target lives in `spec/documentation-quality-v1.toml`:

```bash
# Validate the accepted decisions and registry structure.
julia --project=. --startup-file=no scripts/check_documentation_quality.jl --spec-only

# Measure the repository against the complete 9/10 release target.
julia --project=. --startup-file=no scripts/check_documentation_quality.jl
```

The second command is intentionally red while target content, platform smokes, task reviews, or
replacement media remain incomplete. It prints each unmet gate. It must pass before the
documentation claims 9/10 readiness.

## Source-of-truth rules

- Implemented code, public contracts, and conformance tests outrank historical prose.
- Export status is not a stability or scientific-support claim.
- Backend compatibility and scientific qualification are documented separately.
- Every user-facing example uses a supported public spelling and runs in the documentation build.
- Expensive validation, rendering, and publication output has a reproducible command and artifact
  identity rather than being embedded as an executable page block.
- Literature-derived examples disclose provenance. Only admitted, evidence-backed work appears
  under Published Models.
- Internal ProcessBigraphs behavior stays package-local until its applicable runtime or adapter
  gate passes.

## Adding ProcessBigraph material

Add a ProcessBigraph workflow to Learn or Examples only after its public integration contract
passes. Add hierarchy, transaction, failure, or checkpoint semantics to Concepts and Guarantees
at the same time. Add new names to API only at their declared stability level.

Documentation must never imply that a not-yet-cut Potts path uses ProcessBigraphs or that internal
runtime alpha/beta status is a public release.
