# Symbolic Potts V1 lifecycle language — G5-L0 rereview request

Status: fresh-context read-only specification review requested  
Scope: repaired lifecycle-language contract only; no production implementation  
Gate: G5-L0 before G5-L1 and before R2 handoff

## Required inputs

Read these files completely:

1. `design/audits/symbolic-potts-v1-lifecycle-language-owner-interview.md`, including
   LCI-R5-01 through LCI-R5-07;
2. `design/audits/symbolic-potts-v1-lifecycle-language-consolidation-candidate.md`;
3. `design/audits/symbolic-potts-v1-lifecycle-language-independent-review.md`;
4. `spec/symbolic-potts-v1-compiler-construction.md`, especially CCV1-001, CCV1-003,
   CCV1-006--013, CCV1-017--024, and CCV1-027;
5. `spec/state-model.md`;
6. `spec/lifecycle.md`;
7. `spec/randomness-and-reproducibility.md`;
8. decisions 0004, 0006, and 0019; and
9. the current working-tree diff.

Treat every statement in the candidate, amendment, and prior review as a hypothesis until verified
against accepted owner decisions and higher authority. Do not edit files or implement code.

## Required disposition of the first review

Re-evaluate every prior finding independently:

- P0-01: `RetireAtZero` versus `ForbidExtinction` and the impossible zero-volume state;
- P1-01: removal of the unaccepted `sites(lattice)` event domain;
- P1-02: completeness of the pure lifecycle-policy ABI;
- P1-03: registry/callable freeze versus mutable Julia method tables and executable identity;
- P1-04: explicit owner authority for every `on_inadmissible` value;
- P2-01: responsibility ownership without a mandatory exact file tree;
- P2-02: complete public failure-to-host/device-status mapping; and
- P2-03: canonical tuple representation for relationship overrides.

A prior finding is cleared only when all amended authorities are mutually consistent, not merely
because the candidate contains new prose.

## Architecture questions

1. Is there exactly one production route from every admitted symbolic lifecycle expression or pure
   policy to a concrete callable evaluator?
2. Is the structural mutation algebra literally closed while pure extension remains real and
   equally qualified?
3. Can a novel external trigger, placement, partition, and state transform use the same lowering,
   CPU/GPU, inference, scheduling, diagnostic, adaptation, and checkpoint machinery without a
   CorePotts executor edit?
4. Are qualified identities authoritative before analysis, and are all footprints, bounds,
   conflicts, tracker needs, and capabilities compiler-proven rather than trusted labels?
5. Is the per-model frozen operation closure minimal and immune to live-registry redirection while
   making no false claim about future Julia method definitions?
6. Are identity/generation, same-MCS non-reuse, conflict, capacity, RNG, checkpoint, and staged
   publication laws complete and mutually consistent?
7. Is every failure category deterministically sourced, represented, and translated without a
   second scientific authority on the host?
8. Do compiler-stage and runtime ownership boundaries prevent mechanism hardcoding, a monolithic
   executor, duplicate evaluators, and model-identity specialization without freezing incidental
   filenames or private types?
9. Is the specification bounded enough for G5-L1--G5-L5, with no hidden G6 or proof-model work?
10. Are the required tests rigorous but DRY, with expensive backend/compiler qualification kept out
    of the everyday loop?

## Required output

Write the review to
`design/audits/symbolic-potts-v1-lifecycle-language-g5-l0-rereview.md` with:

- one verdict: `Clear`, `Clear with nonblocking findings`, or `Blocked`;
- a table disposing every prior P0/P1/P2 finding;
- any new findings classified P0--P3;
- for each blocker, the governing clause, smallest location, concrete counterexample or static
  proof, violated invariant, and earliest repair checkpoint;
- a literal accepted V1 event-domain/effect/policy inventory audit;
- a one-path evaluator audit and CorePotts mechanism-neutrality audit;
- an implementation-readiness statement for G5-L1 only; and
- an explicit statement that clearance does not authorize R2, G6, or proof-model migration.

Do not expand V1, weaken a requirement, design production code, or create a new evidence system.
If no P0/P1 remains, clear G5-L0. P2/P3 findings may be nonblocking only when they are genuinely
localized and do not leave the implementation contract ambiguous.
