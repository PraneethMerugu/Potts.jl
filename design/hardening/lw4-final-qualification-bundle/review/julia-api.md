# LW-R2 Julia API and package-boundary review

Reviewer role: fresh Julia multiple-dispatch/package-API reviewer
Review date: 2026-08-12 (America/New_York)
Disposition: **PASS**
Severity count: **P0 = 0, P1 = 0, P2 = 0**

## Bound identities

| Identity | Reviewed value |
|---|---|
| Product commit | `ee395bd2f70d210fe98a0fb748e6530824c50671` |
| Product tree | `b5ad1e71d73251fa6f932c8d275be8d1910f65fd` |
| Evidence digest | `49002d9542b64c4c03388ab9bbe30632dfe20a64eac6c2e4bbcb89c50a486641` |
| Workload digest | `c7bd404d26f42db0a887094aa125f377e043fc196e54a8ca95fd8e1b1a1dfe69` |
| Qualification-tool SHA-256 | `8a99ff0e698a635396899596d07f04b9667ca8b393701c540b0f6037f560f4ee` |
| Frozen environment | Julia 1.12.6; KernelAbstractions 0.9.42; Apple M1/aarch64; normal 1,000-pair profile |

`HEAD`, `HEAD^{tree}`, the artifact identity, and the supplied product identities agree. I
independently reconstructed the artifact digest from every non-review evidence file and obtained
the exact value above. I also ran the qualification driver's `--validate` mode against the bundle;
it exited successfully and reconstructed the same digest and product identity. There are no
tracked changes relative to the candidate; the qualification bundle is the expected untracked
freeze artifact.

## Methods and boundaries inspected

- Public surface and lifecycle: `LocalWorksets.jl`; the token-gated constructors and public
  `LocalWork`, `WorkPlan`, `PreparedWork`, `WorkEvent`, and `LocalWorkValidationError` definitions
  in `model.jl`; `plan`, `prepare`, `run!`, `Base.wait`, and `inspect`.
- Central admission and exact dispatch: `_central_admission`,
  `_centrally_admitted_lowering_call`, `_centrally_qualified_lowering_evidence`,
  `_central_make_provider_lane`, `_centrally_admitted_provider_call`,
  `_centrally_qualified_atomic_capability`, `_centrally_qualified_value_capability`, and
  `_owned_kernel_factory`.
- Preparation and inference: the package-owned `owned`/`trusted` method selection in `prepare`,
  `_operation_call_signature`, `_operation_result_type`, `_operation_callback_facts`,
  `_validate_operation_result_form`, `_validate_independent_result_type`, and
  `_validate_emission_result_type`.
- World-age and lifetime: `_cache_execution_lowering!`, both world-counter revalidation blocks in
  `run!`, pre-lease validation order, `_lease_index`, `_poison_lane!`, `_wait_lane!`,
  `_release_through!`, and the last-admitted-world `Base.invoke_in_world` calls in `Base.wait`.
- Device-static execution: `_direct_independent_kernel!`, `_combined_apply_kernel!`,
  `_combined_publish_kernel!`, and their generated `_publish_independent!`,
  `_apply_combined_item!`, and `_publish_deterministic_destination!` helpers. Accepted operations
  are concrete isbits callables; result types must be one concrete `NamedTuple`; fixed port names,
  arities, emission/candidate forms, rank/value types, and combination law are resolved before a
  launch. The generated helpers dispatch on concrete declaration/result tuple types and contain no
  host reflection or runtime registry lookup.
- CorePotts adapter boundary: `_prepare_localworksets_trusted_adapter`,
  `_validate_localworksets_trusted_adapter!`, `_run_localworksets_trusted!`,
  `_wait_localworksets_trusted!`, the checkerboard candidate preparation/claim call, and settlement.
  New claim submission validates both broad public entrypoints and invokes the stored broad
  `LocalWorksets.run!` method in the admitted world; settlement invokes the stored broad
  `Base.wait(::WorkEvent)` in the last admitted world, preserving mandatory drain after piracy.
- Cohesion/extraction: the shared concrete-result validator now has one definition used by direct
  and buffered/heterogeneous paths; output-family kernels remain separated from provider code;
  the generic lifecycle substrate contains no CorePotts or PottsToolkit dependency. Every
  non-comment production source unit remains below the enforced 1,000-line review bound.

## Tests and evidence inspected or reproduced

- Fresh focused execution of `support.jl` plus `test_generic.jl` reproduced the repaired
  `invalid external operation results have structured prelaunch errors` testset: **46/46 pass**.
  This covers non-concrete union returns for direct independent, buffered combined, and
  heterogeneous independent/combined work; missing `item::Int32` methods for direct and buffered
  work; byte-preserving prelaunch rejection; and structured unsupported-operation and wrong-identity
  combination diagnostics.
- The same focused process continued through the heterogeneous correctness witnesses: **33/33**
  and the once-per-item invocation witness: **4/4** before the bounded focused invocation ended.
- Frozen standalone evidence records package quality **11/11**, exact public API **31/31**, concise
  authoring **26/26**, the repaired structured-error test **46/46**, direct/buffered/heterogeneous
  functional and integrity suites, and all hostile admission/world-age tests passing. In
  particular, exact central-admission and cached-execution replacement reject prelaunch; external
  capability/evidence methods cannot authorize; preexisting provider-wait piracy rejects; and
  already submitted tails still drain after wait/release/lease-index or more-specific method
  replacement.
- Frozen CorePotts evidence includes the fresh-process `run`, `wait`, and more-specific adapter
  attacks and the exact trusted-adapter vertical tests. The complete CorePotts command exited 0.
- Frozen real-Metal evidence executed the concrete Level-1 callable, heterogeneous generic
  witnesses, ordered stages, specialized/conjunctive mechanisms, provider-failure paths, and the
  checkerboard integration with scalar indexing disabled. It records 20 selected-device compiler
  cache entries on first compilation, stable same-schema specialization (`361 -> 361`), and exit 0.
- The complete frozen ledger has successful standalone, CorePotts, root, CPU-witness,
  CPU-performance, and real-Metal commands. The driver reconstructed all result and summary
  invariants successfully.

## Findings

### P0

None.

### P1

None. The prior structured-error blocker is closed across direct, buffered, and heterogeneous
result inference. `Union{}` now produces a stable `LocalWorkValidationError` with
`stage = :prepare`, `contract = :operation_result_form`,
`expected = :concrete_named_tuple`, the actual inferred type, and an `item::Int32` authoring hint.
Non-concrete unions reject with the same structured contract before storage mutation or launch.
Unsupported combination operation and identity reject at planning with exact `port`, `expected`,
and `actual` fields.

### P2

None. The public type/lifecycle surface is narrow and documented, high-value validation errors have
stable structured fields, and the direct/buffered validation consolidation improves extraction
cohesion without introducing another authority or execution family.

## Ballot

**PASS.** The exact candidate and evidence have no Julia API/package-boundary P0, P1, or P2
finding. Central admission remains package-owned and fail-closed; external methods may provide
concrete operation behavior but cannot authorize capabilities, replace lowerings/providers, or
intercept CorePotts submission/settlement. Warm execution uses cached exact signatures, changed
worlds revalidate before lease acquisition, and already admitted asynchronous work remains
drainable in its admitted world. Concrete inference and the generated type-directed kernels are
consistent with the qualified CPU and real-Metal compilation evidence. This ballot authorizes no
architecture or naming change and makes no CUDA/ROCm claim.
