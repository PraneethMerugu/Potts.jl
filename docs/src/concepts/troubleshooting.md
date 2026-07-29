# [Troubleshooting](@id troubleshooting)

Start from the boundary that failed. Avoid changing several model or execution choices at once.

| Symptom | First checks | Do not do |
|:--|:--|:--|
| Package cannot install | `versioninfo()`, `Pkg.status()`, network/proxy, Julia 1.12.6 | Delete manifests blindly |
| Model validation fails | Read every diagnostic from `validate(model)` | Add hidden defaults |
| Problem construction fails | Domain, layout identities, obstacles, fields, capacity | Resize or relabel silently |
| Backend preflight is red | Full `backend_report`, algorithm, dimension, scalar policy | Substitute backend or algorithm silently |
| Run completes but analysis is missing | Observation declarations and snapshot policy | Read private storage |
| Render conversion fails | Complete host snapshot or retained ownership, request channels | Trigger hidden device transfer |
| Checkpoint restore fails | Contract versions, algorithm, numerical profile, checksum | Fall back to import silently |
| Different result with same seed | Model/algorithm fingerprints, RNG contract, backend, observation | Treat seed as complete identity |
| Cell histories merge | Join by cell ID and generation | Join by slot alone |
| GPU is slower | Separate compilation, transfers, observation, and steady-state time | Quote first-call latency as throughput |

## Collect a minimal report

Include:

```julia
versioninfo()
using Pkg
Pkg.status()
```

Also retain the complete validation or compatibility report, model and execution fingerprints,
algorithm guarantee profile, backend/numerical policy, problem dimensions and capacity, seed
policy, snapshot policy, and the smallest canonical source that reproduces the failure.

## Documentation failures

The docs build does not silence errors:

```bash
julia --project=docs --startup-file=no docs/make.jl
```

Doctests, executable examples, cross-references, and document checks are required. The
stability-aware quality checker additionally rejects unregistered pages, missing canonical
sources, provenance gaps, and API-registry drift:

```bash
julia --project=. --startup-file=no scripts/check_documentation_quality.jl
```

`checkdocs = :none` disables Documenter's indiscriminate all-export rule; the curated inventories
replace it so internal exports do not become accidental stability promises.

## Report a defect

Provide the minimal source, full exception, expected and observed result, environment identity, and
whether the issue reproduces on CPU. Do not include private data or unpublished model inputs
without reviewing the issue destination.
