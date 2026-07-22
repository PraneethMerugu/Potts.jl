# Decision 0028: Phase 13 Entry, Evidence, and API-Freeze Policy

Status: Accepted; project-owner interview decisions 1--15 complete

Date: 2026-07-22

## Context

Phase 13 combines algorithmic characterization with the paper API freeze. The transition-kernel
contract defines the required technical machinery, but evidence alone cannot choose paper scope,
acceptable public guarantees, API stability, or post-freeze compatibility policy. Those choices
must be fixed before qualification results are examined so that scope and thresholds do not move in
response to inconvenient results.

## Decision

### Scope and algorithm policy

1. The initial Phase 13 gate fully qualifies `SequentialCPM` and `CheckerboardSweepCPM`.
   `LotteryCPM` and a retained `TiledCheckerboardCPM` remain later protocol consumers unless a
   paper-core claim requires their full qualification before the freeze.
2. A measured checkerboard difference from sequential execution is not automatically a defect.
   Checkerboard may be retained with a precise, bounded, evidence-supported guarantee label.
3. Phase 13 changes production checkerboard code only for an invariant failure, an implementation
   error, or failure of a required paper claim. Detectable algorithmic differences are otherwise
   characterized rather than silently removed.
4. Adhesion and volume form the first fully qualified transition-kernel domain. Surface,
   connectivity, and auxiliary mechanics are admitted separately when tractable and receive no
   implied qualification before admission.
5. Phase 13 follows the Phase 12.5 promote, experimental, or reject disposition for
   `TiledCheckerboardCPM`. Full Phase 13 qualification is required only if that disposition and the
   paper scope make the algorithm paper-core.

### Evidence and backend policy

6. Statistical tolerances are preregistered from scientific effect sizes and power calculations
   before qualification results are examined. They are not inferred from observed backend
   differences.
7. A stable cross-backend claim requires applicable real-hardware evidence on CPU, Metal, and ROCm.
   Unsupported domains receive an explicit limited-support statement rather than qualification by
   compilation or extrapolation.
8. Realistic-scale corroboration uses a bounded battery tied to paper claims, including energy,
   morphology, sorting, migration, autocorrelation, mixing, and effective sample size where
   applicable.
9. Unexpected sequential--checkerboard differences are retained and reported as scientific
   results, including maximum-discrepancy states and a mechanistic analysis.
10. A statistical failure retains a forensic artifact and is investigated under the preregistered
    stopping rules. Changing a threshold or sampling plan requires a new explicitly versioned
    study; sampling does not continue merely until a test passes.

### API freeze and release policy

11. A stable API must be documented, tested, supported by current conformance evidence, and
    required by the paper or the core extension contract. Existing export status alone does not
    establish stability.
12. Legacy and provisional APIs are removed before the freeze unless an explicit release decision
    preserves one. Phase 13 does not add compatibility shims for pre-freeze behavior.
13. Experimental APIs carry no compatibility guarantee and remain outside stable paper claims.
14. After Phase 13, changes to frozen RNG, IR, checkpoint, fingerprint, result-schema, or algorithm
    semantic versions require an explicit versioned release decision and recorded evidence
    invalidation.
15. Final owner approval reviews one evidence packet containing the API inventory, guarantee
    matrix, backend results, unresolved limitations, removals, and frozen version identities. Green
    CI alone is not approval of the paper API freeze.

## Consequences

- Phase 13 has a bounded initial qualification target and does not expand automatically to every
  implemented algorithm or component.
- Checkerboard is judged against its declared scientific guarantee rather than presumed sequential
  equivalence.
- Backend and statistical claims are fixed before results and cannot be rescued by silent threshold
  changes.
- The stable API is smaller than the exported implementation surface when evidence is incomplete.
- Phase 12.5 can determine the tiled engine's disposition without forcing it into the initial Phase
  13 matrix unless it becomes paper-core.
- The paper freeze is an explicit evidence review, not merely a passing test run.

## Alternatives Considered

- Fully qualify every retained algorithm and component in the first Phase 13 pass. Rejected because
  it makes the paper freeze depend on non-core protocol consumers and combinatorial fixture growth.
- Require checkerboard to reproduce the sequential transition law. Rejected because checkerboard is
  a distinct stochastic scheduler whose scientifically useful guarantees must be measured rather
  than assumed.
- Choose tolerances after observing qualification data. Rejected because it creates an outcome-
  dependent release gate.
- Preserve all exported or legacy APIs through compatibility wrappers. Rejected because breaking
  changes remain allowed until the paper freeze and unqualified surface area weakens that freeze.
- Treat green CI as final approval. Rejected because CI cannot choose the public guarantee,
  limitation, removal, or compatibility policy.

## Required Conformance Evidence

- Independent sequential and checkerboard transition-kernel records for the admitted domain.
- Preregistered statistical plans and realistic-scale corroboration tied to paper claims.
- Real-hardware CPU, Metal, and ROCm records for every advertised stable cross-backend claim.
- Versioned forensic artifacts for failed statistical qualifications.
- A final API and guarantee evidence packet approved by the project owner.
