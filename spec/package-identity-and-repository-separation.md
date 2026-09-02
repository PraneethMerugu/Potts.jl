# Package Identity and Independent Repository Cutover

Status: Accepted

## Objective

The stabilized package family is released from four independent repositories:

```text
PottsEcosystem/
├── LocalMath.jl/
├── CorePotts.jl/
├── Potts.jl/
└── MakiePotts.jl/
```

The outer directory is an ordinary local workspace, not a package, repository,
runtime authority, or release artifact. The dependency direction is
`LocalMath -> CorePotts -> Potts -> MakiePotts`. Potts may also depend directly
on LocalMath where its public bounded-authoring API exposes LocalMath values.

## Package identities

The high-level `Potts` package, module, extensions, current documentation,
tests, configuration, and durable serialization identities are replaced
atomically by `Potts`. The repository remains `Potts.jl` and the package keeps
UUID `e4c62a4c-8889-4cc8-ad3a-75efc86c53b9`. No alias module, compatibility
package, deprecated import, old checkpoint decoder, or old/new selector is
retained.

The release-candidate versions are:

- LocalMath `0.2.0-rc1`;
- CorePotts `0.2.0-rc1`;
- Potts `0.3.0-rc1`;
- MakiePotts `0.3.0-rc1`.

The package projects contain ordinary UUID dependencies and compatibility
bounds. They do not contain sibling filesystem sources or committed root
manifests. Exact replay and supported-backend qualification environments may
retain manifests when those manifests identify upstream repositories and
revisions rather than local paths.

## Ownership and extraction

Before extraction, every current test, witness, benchmark, manual page, and
specification is assigned to its scientific or package owner. LocalMath and
CorePotts must qualify without loading downstream packages. Potts owns
cross-package symbolic and SciML integration. MakiePotts owns visualization and
rendering. Historical evidence remains historical and is not copied into every
release repository.

The qualified monorepo commit is retained as extraction provenance. New
repositories are produced only from disposable clones with history-preserving
filtering. LocalMath extraction includes both historical `lib/LocalWorksets`
and current `lib/LocalMath` paths. The active working repository is never
history-rewritten in place.

## Qualification and release boundary

Each repository must instantiate, precompile, load, test, build strict
documentation, and pass its owned quality and supported-backend checks from a
fresh clone. One sibling-checkout integration run validates the complete
dependency chain. Julia 1.12.6 is the current package and Metal qualification
version; the exact Potts replay claim remains pinned to Julia 1.12.1.

This cutover ends with independently qualified Git release-candidate tags in
dependency order. General registration is a later release operation. CUDA and
ROCm remain unsupported until separately qualified.

Every repository carries the MIT license, tailored contributor guidance, an
honest disclosure of substantial generative-AI assistance, and a
maintainer-owned release review. Automated audits support but do not replace
maintainer understanding.
