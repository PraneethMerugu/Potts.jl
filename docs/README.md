# Potts.jl documentation

The active manual is the executable final-interface documentation product. It
covers symbolic authoring, structural compilation, the SciML lifecycle,
dynamic identity and relationships, native ModelingToolkit components,
fields, batching, ensembles, replay, package boundaries, and the exact support
matrix. Complete scientific factories and their executable modeling tutorials
live in the sibling PottsModels package; this manual executes the owning API
examples, including the custom-model authoring and continuation workflow.

## Build locally

From the repository root:

```bash
julia --project=docs --startup-file=no -e 'using Pkg; Pkg.instantiate(; julia_version_strict=true)'
julia --project=docs --startup-file=no docs/make.jl
```

Doctest, example, cross-reference, and document checks are errors.
`docs/build/` is generated and ignored.

## Source-of-truth rules

- The normative specification and accepted decisions outrank documentation.
- Export status alone is not a stability or scientific-support claim.
- Support is an evidenced conjunction; compilation alone never broadens it.
- Published-model integration programs do not claim scientific reproduction.
- The manual documents only the final public lifecycle and has no migration
  guide for unpublished APIs.
