# Current capability and limitation matrix

<!-- Derived from lib/ProcessBigraphs/parity-registry.toml. -->

- Implementation state: `internal_beta`
- Current package version: `0.5.1`
- Baseline qualified internal-beta version: `0.5.0`
- Internal beta: `true`
- Public release: `false`

ProcessBigraphs owns when and why computation occurs. Selected solvers and CPM kernels own how authorized heavy computation occurs.

## Backend envelopes

| Envelope | Adapter | CPU | Metal | ROCm | CUDA | Precision |
|---|---|---:|---:|---:|---:|---|
| `native-cartesian-field` | `CorePottsNativeFieldEngine` | qualified | qualified | qualified | not_applicable | Float32, Float64 |
| `sciml-cartesian-field` | `SciMLFieldAdapter` | qualified | unsupported | unsupported | not_applicable | Float64, declared Float32 |
| `independent-custom-field` | `IndependentCustomFieldAdapter` | qualified | unsupported | unsupported | not_applicable | Float64 |
| `merks-source-faithful-assembly` | `ProcessBigraphsCorePotts` | qualified | unsupported | unsupported | not_applicable | Float64 |
| `cnv-source-faithful-assembly` | `ProcessBigraphsCorePotts` | qualified | unsupported | unsupported | not_applicable | Float64 |

## API families

| Family | Contract | Status | Admission rule |
|---|---|---:|---|
| `engine` | managed-engine protocol | qualified | Admit the smallest declaration-authoring surface after cross-adapter qualification; concrete runtime machinery remains internal. |
| `field` | field publication | qualified | Export only the logical descriptor and operation contracts; realizations remain opaque. |
| `structure` | structural transactions | qualified | Export typed structural requests/results only; raw AlgebraicRewriting rules remain internal. |
| `sciml` | solver adapters | qualified | Expose only qualified declaration construction with an explicit real algorithm and canonical options through the SciML extension. |
| `corepotts` | package boundary | qualified | CorePotts owns adapter-facing methods; ProcessBigraphs must not import CorePotts. |
| `authoring` | semantic authoring | qualified | Ordinary authors use the complete compose do-block and typed-handle builder API; macros are optional transparent sugar and raw lowering IR is not required. |

The internal-beta allowlist contains 72 exported names and 12 qualified-name expert types or codecs.

## Runnable model scope

| Model | Status | Required bounded target | Excluded analysis |
|---|---:|---|---|
| `merks-2006-vasculogenesis` | qualified | 500×500 | Figure_5_full_ensemble, publication_morphometry_pipeline, quantitative_reproduction |
| `shirinifard-2012-cnv` | qualified | 40×40×35 | full_year_CI, ten_replica_reproduction, full_morphology_classifier, quantitative_reproduction |

## Open qualification rows

None.

## Explicitly excluded API claims

- universal solver compatibility
- universal solver GPU support
- raw unrestricted rewrite API
- per-cell or per-voxel orchestration ACSet
- Dagger or distributed executor
- public stable 1.x API
- mandatory full @compose macro language
- graphical authoring
- arbitrary closure serialization

## Explicit scope exclusions

- `public-release`
- `complete-pinned-parity`
- `dagger-or-distributed-qualification`
- `multi-gpu`
- `cuda-qualification`
- `universal-solver-gpu-support`
- `moving-mesh-fem-amr`
- `merge-engulf-burst-general-rewrite`
- `implicit-spo-cascade`
- `arbitrary-mid-event-restart`
- `full-merks-publication-analysis`
- `full-cnv-publication-analysis`
- `full-source-ensemble-reproduction`
- `mandatory-source-faithful-assembled-model-gpu`
- `broad-ode-dae-biochemical-fba-sbml-ecosystem`
- `algebraicdynamics`
- `whole-cell-qualification`
- `mandatory-full-compose-macro-language`
- `graphical-authoring`
- `arbitrary-closure-serialization`
- `universal-implicit-cosimulation-engine`
