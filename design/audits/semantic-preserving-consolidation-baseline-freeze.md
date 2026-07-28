# Semantic-Preserving Consolidation Baseline Freeze

Status: Qualified; baseline frozen, production consolidation not started

Date: 2026-07-28

Authority: Decision 0041 and the accepted
[`semantic-preserving-consolidation-contract.md`](../../spec/semantic-preserving-consolidation-contract.md)

Machine-readable attestation:
[`baseline-freeze-v1.toml`](../evidence/consolidation-baseline/baseline-freeze-v1.toml)

## Outcome

The `baseline_freeze` gate is complete.

All six baseline requirements, `CON-B01` through `CON-B06`, are qualified. The exact qualified
runtime remains commit `d2f4d40e78fb68ee20da483d9784b55d25bf6147`, tree
`c33dc3909ef043e0c9df9cc44d1ab63fe2a99475`. No production source, existing test, workflow,
dependency input, numerical method, API, model, or qualified claim changed while producing this
freeze.

The next contract gate is `naming_and_archive`. This qualification does not qualify any
consolidation implementation and does not authorize functionality changes.

## Scope identity

The baseline collector resolves evidence from Git objects at the qualified commit rather than
trusting the mutable working tree. It also refuses to run when the runtime-scoped working tree
differs from that commit.

The frozen inventory contains:

| Item | Count |
|---|---:|
| Tracked repository files | 902 |
| Production and extension Julia source files | 137 |
| Project and Manifest inputs | 26 |
| Project files | 16 |
| Manifest files | 10 |
| Direct, weak, and extension dependency edges | 129 |
| Active source include edges | 126 |
| Unparsed active include sites | 0 |

Every include target is resolved relative to its owning source file and checked against the
qualified Git tree. Every source and environment input has an individual SHA-256.

The package direction remains:

```text
ProcessBigraphs <- CorePotts <- PottsToolkit
```

`MakiePotts` remains an optional frontend over `CorePotts` and `PottsToolkit`. ProcessBigraphs has
not acquired a CorePotts, solver-algorithm, GPU, or visualization dependency.

### Environment warning disposition

Julia 1.12.6 reports that workspace project compatibility metadata changed after the root Manifest
was last resolved. The freeze does not hide this by running `Pkg.resolve`: all tests were run with
`allow_reresolve=false`, and every frozen Project and Manifest input retained its exact qualified
hash.

This warning is therefore baseline state, not an unrecorded resolution. Any later environment
reconciliation must be an explicit, reviewed input change and must prove that the resolved package
set and behavior remain within the contract.

## Requirement audit

### CON-B01 — exact source, environment, dependency, and include identity

Status: `qualified`

The [identity inventory](../evidence/consolidation-baseline/identity-v1.toml) records the exact
commit, tree, parent, merge base, CI authority, all source hashes, all Project and Manifest hashes,
package metadata, dependency edges, and include edges.

Evidence strength:

- source and environment content is read from the qualified Git commit;
- runtime-scoped working-tree equality is checked before generation;
- all 126 active source includes are statically resolved;
- no include expression is left unparsed;
- all 16 final CI jobs passed at the qualified commit in run `30399756947`; and
- the local executable audit used Julia 1.12.6 without dependency re-resolution.

### CON-B02 — API inventory

Status: `qualified`

The [API inventory](../evidence/consolidation-baseline/api-v1.toml) freezes exports, observable
qualified-only declarations, normalized source declarations including defaults, interface hashes,
error types, stable diagnostic codes, consumer paths, and milestone-coded exports.

| Package | Exports | Observable qualified-only names | Error types | Diagnostic codes |
|---|---:|---:|---:|---:|
| ProcessBigraphs | 262 | 16 | 2 | 553 |
| CorePotts | 767 | 192 | 22 | 27 |
| PottsToolkit | 245 | 0 | 2 | 0 |
| MakiePotts | 74 | 0 | 3 | 0 |

The 192 CorePotts qualified-only names are not promoted by this audit. They are an observable
sibling-consumer inventory that must be classified as supported, compatibility-only, or internal
coupling before a consumer can be migrated. Omitting them would make consolidation less safe.

Two CorePotts milestone-coded exports remain:

- `Phase14ContractVersions`; and
- `phase14_contract_versions`.

They are baseline compatibility obligations for the naming gate, not permission to delete or
rename them silently.

The Phase 13 classifications and the ProcessBigraphs 0.5.0 internal-beta API policy remain the
stability authorities. The freeze adds an exact current inventory; it does not broaden stability.

### CON-B03 — behavioral coverage matrix

Status: `qualified`

The [coverage matrix](../evidence/consolidation-baseline/coverage-v1.toml) contains every one of the
159 tracked test Julia files:

- 151 are reachable from an ordinary package runner, the independent-oracle runner, or a direct CI
  entry;
- 8 are explicitly retained auxiliary analysis or audit files;
- 122 contain primary behavioral tests;
- all files retain an exact SHA-256 and evidence-consumer list; and
- each row records testset requirements, domain, happy path, negative path, failure stage, restart
  cut, backend, replay class, oracle role, model claim, and evidence consumers.

The conservative matrix identifies:

| Coverage signal | Files |
|---|---:|
| Negative or rejection behavior | 82 |
| Failure, rollback, atomicity, discard, or corruption behavior | 108 |
| Restart, restore, resume, or checkpoint behavior | 32 |
| Independent or reference-oracle behavior | 62 |
| Distinct contract domains | 14 |
| Model-specific rows | 12 |

The matrix does not infer that a keyword alone proves a claim. Its authority is the exact file,
testset, hash, execution state, and evidence linkage recorded together. Later deletion or merging
must reconcile every row, not merely preserve assertion totals.

### CON-B04 — identity, serialization, trace, and model fixtures

Status: `qualified`

The executable
[`identity-fixtures-v1.toml`](../evidence/consolidation-baseline/identity-fixtures-v1.toml) freezes:

- semantic model fingerprint;
- canonical IR and structural fingerprint;
- execution-plan and model fingerprint;
- problem and runtime fingerprint;
- final snapshot and event-trace fingerprint;
- semantic-model archive bytes and SHA-256;
- current logical checkpoint bytes, SHA-256, fingerprint, and roundtrip equality; and
- deterministic final model state.

The fixture is independently reproducible with Julia 1.12.6 by
[`capture_consolidation_identity_fixtures.jl`](../../scripts/capture_consolidation_identity_fixtures.jl).

It adopts, without rewriting:

- the eight-fixture serial runtime, 33-cut restart, and failure-stage matrix;
- the fixed 4,609-byte V2 checkpoint fixture;
- managed-engine V3 checkpoint, restore, corruption, and legacy-conversion tests;
- bounded Merks native/SciML/custom-adapter observations; and
- bounded CNV full-domain one-MCS outputs.

The adopted Merks and CNV artifacts remain bounded runnable assemblies, not full publication
analyses.

### CON-B05 — performance, allocation, load, and test-time baseline

Status: `qualified`

The [performance baseline](../evidence/consolidation-baseline/performance-v1.toml) combines retained
qualified budgets with new observational host measurements.

Existing authorities remain green:

- authoring construction, validation, lowering, compilation, initialization, and 128-event warm
  execution pass every frozen budget;
- the high-level and direct-IR plans are identical;
- the qualified warm execution time ratio is `1.0034816214967597`;
- the warm allocation ratio is exactly `1.0`;
- the 256-event serial runtime sustains `4600.259630746863` events/second with
  `121496.46875` bytes/event, below its frozen allocation-growth limit;
- engine and native field publication allocate zero host bytes; and
- trusted Metal and ROCm evidence records zero warm device allocations and no hidden host fallback.

Fresh local precompile, with an isolated compiled cache and existing exact package sources:

| Scope | Real time | Result |
|---|---:|---|
| ProcessBigraphs/CorePotts/PottsToolkit root family | 201.62 s | Passed |
| Additional MakiePotts visualization stack | 191.48 s | Passed |

Warm package loads on the same Apple M1 host:

| Package | Real time |
|---|---:|
| ProcessBigraphs | 1.84 s |
| CorePotts | 2.15 s |
| PottsToolkit | 2.85 s |
| MakiePotts | 6.00 s |

The isolated Makie precompile could not download an optional texture atlas because the measurement
environment had no network access. Makie's supported local atlas fallback completed, and the
precompile passed. This condition is recorded in the performance artifact.

Local Julia 1.12.6 test results:

| Domain | Assertions | Real time | Result |
|---|---:|---:|---|
| PottsToolkit | 731 | 252.56 s | Passed |
| ProcessBigraphs | 1,221 | 482.51 s | Passed |
| CorePotts | 3,863 | 500.66 s | Passed |
| MakiePotts | 505 | 288.29 s | Passed |
| Cross-package CPU integration | 4,793 | 150.63 s | Passed |
| Independent specification-oracle units | 16 | 1.80 s | Passed |
| Total | 11,129 | 1,676.45 s | Passed |

These local timings are comparison observations, not new budgets or fastest-runtime claims.

### CON-B06 — exact-source hardware impact

Status: `qualified`

The [hardware impact map](../evidence/consolidation-baseline/hardware-impact-v1.toml) defines three
claim closures:

| Claim | Frozen impact paths |
|---|---:|
| CPU package family | 171 |
| Native Cartesian field on Metal | 100 |
| Native Cartesian field on ROCm | 100 |

The Metal and ROCm maps deliberately include the complete CorePotts source, the transitive
ProcessBigraphs runtime source, the applicable backend extension, benchmark harness and
environment, and GPU workflow. This is stricter than watching only the directly hashed
`native_fields.jl`.

Adding, deleting, moving, or changing any mapped path invalidates the applicable claim and requires
trusted exact-head requalification. CUDA remains outside the accepted claim boundary.

## Duplicate-code baseline

The [duplicate classification](../evidence/consolidation-baseline/duplication-v1.toml) scans 362
Julia files with exact 16-line windows after removing blank lines, comments, and whitespace-only
differences.

It records 51 exact clone windows:

| Classification | Windows | Required disposition |
|---|---:|---|
| Accidental production candidate | 3 | Reconcile under production deduplication |
| Quality-tooling duplication | 10 | Reconcile under the test/quality gate |
| Test fixture or contract duplication | 4 | Reconcile without weakening independence |
| Independent custom adapter | 3 | Retain decisive independence |
| Independent oracle | 3 | Retain decisive independence |
| Test oracle literal | 6 | Retain or replace only with equally independent evidence |
| Public facade re-export | 22 | Preserve facade/API semantics |

Seventeen windows require consolidation review. Exact clone detection is supplemented by ten named
semantic responsibility clusters covering fingerprints, canonical bytes, validation, engine
transactions, fields, checkpoints, authoring origins, dispatch, fixtures, and quality helpers.

This classification is a baseline map, not an instruction to share decisive oracle or backend
logic.

## Reproduction

Static artifacts:

```text
julia --project=. --startup-file=no scripts/freeze_consolidation_baseline.jl
```

Executable identity fixture:

```text
julia --project=lib/ProcessBigraphs --startup-file=no \
  scripts/capture_consolidation_identity_fixtures.jl --check
```

The static collector verifies artifact byte equality and rejects runtime-scoped drift from the
qualified commit. The identity fixture recomputes all fingerprints and canonical bytes.

## Gate decision

`CON-B01` through `CON-B06` are qualified. The consolidation ledger advances from
`accepted_not_started` to `baseline_frozen`.

The next allowed work is the `naming_and_archive` gate:

1. define the canonical domain vocabulary;
2. build the complete old-to-new naming map;
3. define compatibility aliases for observable milestone-coded names;
4. index immutable historical evidence and protocol identities; and
5. rename living tests and quality organization before scientific implementation moves.

No future-roadmap implementation and no scientific consolidation is authorized by this audit.
