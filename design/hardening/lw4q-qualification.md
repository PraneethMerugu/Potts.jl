# LW-4Q — qualification workflow

Status: authoritative for LW-4 qualification and LW-R2 review. Earlier LW-4
qualification documents and preserved bundles are historical evidence, not
additional workflow authorities. LW-4Q changes mechanics only; it does not
change LocalWorksets architecture, lifecycle, output semantics,
KernelAbstractions ordering, backend claims, or domain ownership.

## Three workflows

```sh
# Development: persistent Julia/Revise session; no evidence artifact.
julia --project=. -i benchmark/lw4_qualification.jl --development

# Check: focused package tests plus bounded CPU/real-Metal witnesses.
julia --project=. benchmark/lw4_qualification.jl --check

# Freeze: one clean committed candidate and one evidence artifact.
julia --project=. benchmark/lw4_qualification.jl \
  --freeze=design/hardening/lw4-final-qualification-bundle
```

Development requires Revise in the developer environment. Hostile method-table
tests still run only in the fresh disposable package-test processes. Check has
no performance comparison, bundle, or committee. Freeze has six product
commands and does not run qualification-tool tests.

Normal Freeze uses 1,000 paired microbenchmark samples. `--confirmation` uses
2,000 and is reserved for release tags, performance-sensitive lowering or
lifetime changes, disputed regressions, or a borderline normal result.

Qualification-tool CI is separate and writes an exact machine record:

```sh
julia --project=. benchmark/lw4_qualification.jl \
  --tool-self-test=design/hardening/lw4q-tool-validation.toml
julia --project=. benchmark/lw4_qualification.jl \
  --validate-tool-record=design/hardening/lw4q-tool-validation.toml
```

Run it only when the driver, validator, schema, or sealer changes. The record
contains the exact driver SHA-256, Julia version, time, covered rejection
classes, and pass disposition. A later tool-only validator change revalidates
an existing artifact without rerunning product commands:

```sh
julia --project=. benchmark/lw4_qualification.jl \
  --revalidate=ARTIFACT --record=REVALIDATION.toml
julia --project=. benchmark/lw4_qualification.jl \
  --validate-revalidation-record=REVALIDATION.toml
```

## Operational timing and coverage

The latest complete pre-LW-4Q execution took 48m11s. The laptop had just moved
between locations, so the elapsed time is not interpreted as a regression.
All times here are operational context, never performance evidence or gates.

| Command | Observed | Share | Unique purpose |
|---|---:|---:|---|
| tool self-test | 0m27s | 0.9% | tool/schema adversarial tests |
| LocalWorksets `Pkg.test` | 4m11s | 8.7% | standalone package/API/admission |
| CorePotts `Pkg.test` | 3m08s | 6.5% | domain adapter and scientific ownership |
| PottsToolkit root `Pkg.test` | 18m58s | 39.4% | integrated package/MTK/extensions |
| CPU witnesses | 0m31s | 1.1% | unrelated mechanism correctness |
| CPU performance | 1m58s | 4.1% | paired noninferiority only |
| real Metal | 18m58s | 39.4% | actual-device semantics and performance |

Expected ranges on this Mac are: Development seconds to a few minutes for a
chosen target; Check about 10–18 minutes; normal Freeze about 46–53 minutes;
confirmation Freeze about 50–60 minutes. The saving is avoiding Freeze during
iteration and avoiding product reruns for tooling, documentation, and review
changes—not weakening the real-hardware boundary.

| Boundary | Uniquely proves | Decision |
|---|---|---|
| LocalWorksets standalone | extraction independence, lifecycle, admission, hostile method worlds, mechanisms | retain complete boundary |
| CorePotts | conjunctive claims, Core-owned settlement/RNG/checkpoints, continuation, adapter worlds | retain; exact method attacks stay isolated and last |
| PottsToolkit root | authoring/MTK extensions and authoritative integration | retain; not a substitute for package independence |
| CPU witnesses | LBM, spring, FEM and z-buffer reference results | retain unrelated-consumer evidence |
| real Metal | selected-device compilation, KA ordering, failure visibility and performance | retain; portable source is not qualification |

No test body is deleted in LW-4Q. Shared subjects do not duplicate the package,
extraction, integration, or device boundary being proved. Aqua, formatting,
docs, compatibility and benchmarks remain separate concerns.

## Identity and invalidation

| Identity | Contents | Invalidated by | Does not invalidate |
|---|---|---|---|
| product | committed Git commit/tree: production, tests, tracked projects/manifests, extensions, integration | source, dependency, test or integration change | review prose |
| workload | committed witness, backend, parity and package-test Git objects | workload shape/order/oracle change | parser formatting |
| tool | driver SHA-256 | driver, validator, schema or sealer change | product-only change |
| environment/backend | digested snapshots and hashes of every used Project/Manifest, Julia, derived KA version, OS and CPU | dependency/environment/hardware change | memo edits |
| evidence | commands/statuses, raw logs/results/samples, summary | affected identity above | documentation/review edits |
| review | independent memos and chair decision bound to product/evidence | substantive finding or product/evidence change | memo formatting |

Detailed Metal package, selected-device and runtime identity lives in the
digested `results/metal.jls`; it is reconstructed during validation. It is not
misrepresented as a host-only `identity.toml` field.

Exact rules:

- Product, dependency, test or workload changes invalidate affected
  correctness evidence. Performance reruns only when the measured path,
  workload, environment or backend changes.
- Tool-only changes run tool CI and revalidate preserved raw evidence; they do
  not automatically rerun product commands.
- Documentation, memo, chair-summary and decision-format changes do not rerun
  product commands.
- Reuse requires exact product commit/tree, workload digest, environment and
  backend identity. Informal similarity is insufficient.
- A P0/P1 production fix invalidates affected product evidence. A tooling P1
  invalidates tool validation, not unrelated raw product execution.

## Reproducible performance sample decision

Five exact historical runs are preserved in the content-addressed
`lw4q-subsampling-inputs.jls`. It contains the four raw ordered 1,000-pair
timing series from each run plus each source/result digest; it is not narrative
evidence. `lw4q-subsampling.toml` records the input hash, all five source
identities, seeds/method, counts and machine results.

Reconstruct the table with:

```sh
julia -t auto --project=. benchmark/lw4_qualification.jl \
  --subsample=design/hardening/lw4q-subsampling-inputs.jls \
  --output=design/hardening/lw4q-subsampling.toml
```

For each candidate count, the analysis uses 100 SHA-256-seeded,
without-replacement subsets per source and 2,000 paired bootstrap resamples per
subset: 500 decisions per workload/count. These bootstrap draws are offline
arithmetic, not hardware executions. The exact machine record is authoritative;
the compact result is:

| Pairs | CPU D2Q9 failures | CPU z-buffer failures | Metal D2Q9 failures | Metal z-buffer failures | Worst upper bound |
|---:|---:|---:|---:|---:|---:|
| 50 | 0/500 | 0/500 | 63/500 | 232/500 | 1.47566 |
| 100 | 0/500 | 0/500 | 26/500 | 144/500 | 1.24000 |
| 200 | 0/500 | 0/500 | 4/500 | 73/500 | 1.10812 |
| 500 | 0/500 | 0/500 | 0/500 | 13/500 | 1.06805 |
| 1,000 | 0/500 | 0/500 | 0/500 | 0/500 | 1.02704 |

This corrects the earlier unbound 500-pair claim. One thousand is the smallest
tested fixed count that preserved every decision, with 0.02296 worst-subset
margin. Two thousand is the confirmation profile. CorePotts parity remains 50
expensive paired batches and 10,000 inexpensive bootstrap resamples; resamples
are not hardware runs.

## Exact artifact, validation and review

Freeze contains exactly `identity.toml`, snapshots of the ten used
Project/Manifest files, the six-command ledger, six raw logs, three serialized
raw results, `summary.toml`, `README.txt`, and one
`bundle-digest.txt`. Validation enforces the normal/confirmation profile,
identity schema, exact ordered commands and environments, canonical
bundle-contained paths, exact artifact inventory, nonempty successful logs,
commit-owned workload/tracked-project objects, snapshot hashes, raw host/Metal
environment agreement, raw-result invariants, and byte-for-byte-equivalent
summary reconstruction.
The digest proves integrity; reconstruction proves meaning.

Review adds five independent specialty memos, one chair memo, and one
`decisions.toml` bound to the product commit and evidence digest. The chair
alone performs the consolidated contradiction/red-team pass. Reviewers rewrite
only for material conflicts. Git owns memo integrity; there is no parallel
memo-hash graph.

The exact final sequence is:

```sh
julia --project=. benchmark/lw4_qualification.jl --validate=ARTIFACT
# add the five memos, chair memo and decisions.toml
julia --project=. benchmark/lw4_qualification.jl --seal=ARTIFACT
julia --project=. benchmark/lw4_qualification.jl --verify-seal=ARTIFACT
git add ARTIFACT && git commit
julia --project=. benchmark/lw4_qualification.jl --verify-final=ARTIFACT
```

`SEALED` binds the current review-record digest as well as product/evidence.
Any post-seal decision or memo edit fails `--verify-seal`. Freeze is not
announced until the exact evidence/review/seal state is committed and
`--verify-final` confirms every artifact file is tracked and clean.

## Conventional future CI

Use separate ordinary jobs for supported Julia `Pkg.test`, Aqua/ambiguity and
optional JET, Runic, docs/doctests, compatibility/downgrade checks, downstream
CorePotts/PottsToolkit integration, BenchmarkTools/AirspeedVelocity-style
benchmarks, backend-specific hardware, CompatHelper, TagBot and release
automation. CPU plus real Metal is the only current qualification. CUDA/ROCm
remain portability intent until real hardware jobs pass.

## Current bundle determination

Historical 1,000-pair bundles remain valid only for their exact recorded
product/workload/environment identities and for the content-addressed
sample-sizing analysis. The final normal 1,000-pair Freeze qualifies product
`ee395bd2f70d210fe98a0fb748e6530824c50671` with evidence digest
`49002d9542b64c4c03388ab9bbe30632dfe20a64eac6c2e4bbcb89c50a486641`.
Qualification-tool-only hardening at `3c406285` revalidated the preserved raw
evidence without rerunning product workloads. The five-role committee and
chair passed, seal commit `a65622a2` passes `--verify-final`, and LW-R2 is
frozen.

LW-5 may now use focused per-operation Development/Check cycles followed by
one integration Freeze.
