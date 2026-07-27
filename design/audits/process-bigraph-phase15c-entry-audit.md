# ProcessBigraphs Phase 15.C Pre-Implementation Entry Audit

Status: Passed pre-implementation design audit; runtime implementation not started

Date: 2026-07-26

## Verdict

Phase 15.C is sufficiently specified to begin 15.C1 after this packet merges and its entry checker
passes on `main`. All 64 owner choices are resolved, the semantic boundary is internally
consistent, the feature and evidence scope is machine-readable, the implementation order is
closed, and no owner or architectural question remains open.

This verdict is deliberately narrower than an implementation or qualification verdict.
`ProcessBigraphs.jl` remains version `0.3.0`; `internal_alpha = false`; no Phase 15.C production
scheduler, semantic RNG, observer/continuation completion, independent oracle, qualification
matrix, candidate artifact, or final attestation is claimed.

## Authority and method

The audit checked the following authorities together:

- the completed [owner interview](process-bigraph-phase15c-serial-alpha-owner-interview.md);
- [Decision 0038](../../spec/decisions/0038-process-bigraph-serial-alpha.md);
- the normative [runtime semantics](../../spec/process-bigraph-runtime-semantics.md);
- the [C0--C7 implementation plan](process-bigraph-phase15c-serial-alpha-plan.md);
- the [machine-readable entry contract](../../spec/process-bigraph-phase15c-entry-v1.toml);
- the root and package-local parity registries;
- the Phase 14.PB0, Phase 15.A, and Phase 15.B decisions, evidence, and checkers;
- the repository architecture, roadmap, package documentation, and required CI workflow; and
- the current package source, tests, version, dependencies, and maturity flags.

The review used exact set comparison rather than prose inference for feature scope. It checked
cross-document links, status language, version and maturity claims, oracle ownership, exclusion
boundaries, stage ordering, and the absence of premature Phase 15.C evidence.

## Owner-decision coverage

Every interview answer is A and every answer has a normative destination:

| Round | Choices | Frozen concern | Normative destinations |
| --- | ---: | --- | --- |
| 15.C0 | 1--8 | closure claim, allowlist, exclusions, maturity, two-PR provenance | Decision scope; entry `scope`, `closure`, and `evidence`; C0/C7 plan |
| 15.C1 | 9--16 | serial executor, same-time visibility, adaptive deadlines, horizons, reaction, iteration | Decision scheduler; entry `scheduler`; C1 plan |
| 15.C2 | 17--24 | semantic RNG address, exact draws, replay classes, observer isolation | Decision RNG; entry `rng`; C2 plan |
| 15.C3 | 25--32 | declarative observation, atomic records, typed continuation, fingerprints | Decision observation/continuation; entry `observation` and `continuation`; C3 plan |
| 15.C4 | 33--40 | fail-stop transactions, diagnostics, canonical checkpoint, compatible restore | Decision failure/checkpoint; entry `failure` and `checkpoint`; C4 plan |
| 15.C5 | 41--48 | independent Julia oracle, allowed sharing, source citations, mutation sensitivity | Decision oracle; entry `oracle`; C5 plan |
| 15.C6 | 49--56 | qualification methods, fixtures, invariances, restart cuts, performance guards | Decision qualification; entry `fixtures` and `qualification`; C6 plan |
| 15.C7 | 57--64 | aggregate gate, candidate artifact, attestation, registry promotion, `0.4.0` boundary | Decision closure; entry `evidence`, `closure`, and `maintenance`; C7 plan |

No answer is deferred, conditional, or silently replaced by an implementation preference.

## Scope and registry audit

The entry contract contains four exact, duplicate-free, pairwise-disjoint sets:

- 15 Phase 15.C target features;
- seven supporting features requalified by the Phase 15.C oracle;
- four Phase 15.A/B structural features whose direct evidence is retained; and
- 22 explicit later-work exclusions.

Every target, supporting, and retained identifier exists exactly once in the root parity registry.
All target and supporting rows name `oracle-independent-specification`. That oracle names exactly
the union of the 15 target and seven supporting rows, is `not_started`, and remains a test-only
independent-Julia oracle.

The audit found and corrected a potentially misleading evidence relationship. Some Phase 15.C
features also name broader future oracles: semantic lineage RNG participates in dynamic-lineage
and executor-equivalence work; the serial executor participates in executor equivalence; and
multirate input semantics participates in the whole-cell ladder. Passing the scoped Phase 15.C
oracle therefore cannot mean those broader oracles pass. The entry contract and registry now state
that the Phase 15.C oracle qualifies only the immutable-topology serial-alpha slice. Dynamic
lineage, alternate-executor equivalence, application/hardware adapters, and whole-cell oracles
remain independently `not_started`.

The four retained structural rows preserve their direct Phase 15.A/B evidence. The entry packet
does not relabel that historical evidence as oracle evidence and does not require reimplementation
of canonical ACSet structure or open composition.

## Semantic consistency audit

The decision, runtime specification, plan, and entry contract agree on these boundaries:

- `SerialExecutor` is policy and `SerialRuntime` is mutable execution state.
- One exact minimum deadline selects all same-time processes.
- Every due process reads one common immutable pre-commit snapshot.
- Process results, reconciliation, reactive work, iteration, continuation, required observation,
  and checkpoint capture form one unpublished candidate.
- There is no intermediate process or step publication; one validated settled boundary is
  published atomically.
- Adaptive deadlines are proposed transactional results and must be exact and strictly future.
- Partial intervals are supplied only under declared support; otherwise preflight fails.
- Reactive cycles are illegal unless represented as named, deterministic, bounded or convergent
  iterative regions.
- Semantic randomness is counter-addressed and independent of call, request, task, or declaration
  order; failed unpublished events consume no identity.
- Required in-memory observation records are atomic with an event, while external emitters make no
  atomic-side-effect claim.
- Alpha-qualified continuations are typed, versioned, validated, fingerprinted, and explicitly
  migrated when supported.
- Failure is deterministic fail-stop with no implicit retry and no partially advanced runtime
  position.
- Checkpoints are canonical logical envelopes rather than Julia object serialization and qualify
  exact compatible serial restore only.

The static/dynamic boundary is also unambiguous. Phase 15.C runs one immutable compiled structural
epoch. Structural add/remove/divide/move/rewire, process retirement/reconfiguration, and general
rewrite transactions remain Phase 16. Alternate executors, device execution, scientific adapters,
Potts cutover, whole-cell qualification, interchange, and public release remain later gates.

## Oracle-independence audit

The planned oracle is located under `lib/ProcessBigraphs/test/specification_oracle` and is not a
production dependency. It may share only neutral machine-readable fixture inputs and neutral
result schemas. It may not import or call production scheduling, reconciliation, update-law, RNG,
continuation, observation, checkpoint, fingerprint, or runtime implementations.

Each oracle rule must cite a pinned upstream source location or Decision 0038. Required CI includes
a static dependency-boundary scan and mutation-sensitivity fixtures for scheduler selection,
same-time visibility, update law, RNG, failure atomicity, and checkpoint/restart. Vivarium,
Process-Bigraph Python, and Bigraph-Schema Python remain source-audit authorities and are never
installed or executed by tests, CI, examples, attestations, or release tooling.

## Current-code and maturity audit

The current package correctly remains at the previous gate:

- package version: `0.3.0`;
- package-local maturity: `phase_15b_open_composition`;
- `internal_alpha = false`;
- public release: false;
- direct dependencies: exactly `ACSets`, `Catlab`, and `SHA`;
- the PB0 event loop remains a bounded microfixture runner, not the qualified serial executor; and
- the Phase 15.C oracle directory and final evidence record do not yet exist.

The package contains legitimate PB0 partial implementations of time, deltas, reconciliation,
runtime, and in-memory checkpointing. Those are inputs to C1--C4, not proof that the corresponding
Phase 15.C registry rows are implemented or independently qualified. No runtime source or test was
changed by this entry packet.

## Entry and closure gates

The pre-implementation packet passes only when:

1. the owner interview, Decision 0038, plan, entry contract, this audit, and entry checker exist;
2. registries, indexes, roadmap, architecture, package docs, and CI describe the same scope;
3. the entry checker, platform checker, PB0 checker, Phase 15.A checker, and Phase 15.B checker pass;
4. every edited TOML parses, package tests pass independently on Julia 1.12.6, and whitespace and
   local links are valid;
5. aggregate required CI passes; and
6. the packet is merged and rechecked from merged `main`.

Only then may 15.C1 begin. C1 through C6 are strict predecessors. C7 requires an implementation PR
and a separate closure-attestation PR. Only that attestation may record the implementation merge,
promote the exact registry evidence, set `internal_alpha = true`, and advance the internal package
identity to `0.4.0`. It still may not publish the package.

## Readiness conclusion

The design is ready, bounded, and testable. The remaining Phase 15.C work is implementation and
qualification rather than unresolved architecture. The entry checker makes this conclusion
fail-closed and prevents future prose drift, scope inflation, premature maturity claims, or
accidental conflation of the scoped serial-alpha oracle with later parity gates.
