# ProcessBigraphs Phase 15.C Closure Audit

Status: qualified immutable-topology serial internal alpha

Date: 2026-07-27

ProcessBigraphs version: `0.4.0`

## Outcome

Phase 15.C closes the bounded serial runtime defined by Decision 0038 and the
64-choice owner interview. The implementation provides exact fixed and adaptive
scheduling, explicit iterative regions, four multirate input policies, typed
continuations and observers, semantic Philox randomness, atomic eight-stage
failure behavior, and canonical settled-boundary checkpoint/restart.

This is an internal alpha, not a public release or complete Process-Bigraph
parity claim. Dynamic topology, alternate executors, device execution,
scientific adapters, Potts cutover, and whole-cell qualification remain outside
the closed scope.

## Attested provenance

Implementation pull request
[#24](https://github.com/PraneethMerugu/Potts.jl/pull/24) qualified branch head
`d4f227b6122448c50420dfedd235fe4ebf0e81e8` in Required CI run
[`30242174768`](https://github.com/PraneethMerugu/Potts.jl/actions/runs/30242174768).
GitHub tested the PR merge checkout
`0a094a802dd84c4ba75cecf02778f4cf1681c8ef`, whose tree was
`02a9ab231e34b274c28b0c6ee3a2c988cc66c24b`.

The implementation was squash-merged as
`cc8b18a18cb890b97170da094110727b8dbf1a7c`. Its tree is also
`02a9ab231e34b274c28b0c6ee3a2c988cc66c24b`, proving that the merge changed
history shape but not qualified contents.

The candidate manifest SHA-256 is
`e6f7cc449408963e6d5a98ea325a3c64cea972a7d9ceee0338758f79f834d305`;
the guardrail report SHA-256 is
`e9eefabd1a705019e7acae3fe23af626dc2cd00d2226c482d62d19e6e3e8ce87`.
The complete machine-readable record is the
[Phase 15.C evidence manifest](../evidence/process-bigraph-phase15c-evidence-v1.toml).

## Qualification balance

- 440 Phase 15.C assertions, 309 historical assertions, and nine Aqua checks;
- 22 exact independent-oracle differential rows and six oracle-unit assertions;
- ten mutation assertions killing all five registered mutation targets;
- all eight registered failure-publication stages;
- six authoring routes, eight fixtures, and all 33 settled restart cuts; and
- four passing source/performance guardrails, with measurements recorded but no
  fastest-runtime claim.

The 15 target rows and seven supporting oracle rows advance from
`oracle_passing` to `qualified`. The four previously implemented structural
rows retain their direct evidence rather than being relabelled. All 22 explicit
exclusions remain unqualified.

## Closure boundary

This attestation changes only package identity, registries, specifications,
documentation, evidence metadata, and the historical integrity checkers'
lifecycle-aware version expectation. It introduces no runtime, test, oracle,
fixture, workflow, or dependency change. `internal_alpha = true` and package
version `0.4.0` therefore attest the already-qualified implementation tree;
`public_release = false` remains mandatory.
