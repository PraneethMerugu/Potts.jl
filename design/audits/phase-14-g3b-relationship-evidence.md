# Phase 14.1 G3-B Relationship Substrate Evidence

Status: bounded SoA storage, portable transactions, accepted-copy topology/energy CPU reference,
retuning, lifecycle cleanup, and restart reconstruction accepted; assembled-model and
source-semantic closure remains open

Date: 2026-07-25

## Scope

This record covers the generic generation-aware relationship substrate required by Wang focal
links. It is not complete FocalPointPlasticity equivalence, complete G3-B, or real GPU
qualification.

The implementation replaces the provisional `Vector{RelationshipEdge}` authority with:

- fixed-capacity canonical endpoint/generation SoA arrays;
- packed active edges, backend-resident count, and publication epoch;
- descriptor-free `RelationshipExecutionState`;
- `Adapt` over state, execution view, transaction workspace, and elastic payload columns;
- generic fixed-capacity request SoA for create/remove/retune;
- deterministic request ordering and duplicate/conflict rejection;
- generation/current-endpoint validation;
- conditional three-kernel initialize/apply/commit publication;
- canonical compaction and deterministic degree/capacity failures;
- a generic elastic payload stored as independent strength, target-length, and maximum-length
  columns;
- one cross-domain elastic retune that publishes the cell strength property and every active edge
  payload together; and
- portable stale-generation lifecycle cleanup.

The accepted-copy extension additionally provides:

- a generic staged `begin`/`prepare`/`preflight`/`commit` protocol rather than a focal-specific
  branch in the Potts kernel;
- construction-time identity, scientific-configuration, and authoritative-state alias checks;
- a semantic-Philox neighbor permutation addressed by normalized target MCS and zero-based attempt;
- first-eligible distinct finite-cell selection under a typed pair policy;
- activation-energy short circuit and acceptance-only canonical link creation;
- existing-link new-minus-old spring energy with shared-edge single counting and extinction
  subtraction;
- bounded one-per-endpoint overlength removal and all-incident extinction removal; and
- restart rebuilding of transaction arrays against restored authoritative relationship state.

Checkpoint payloads persist only active canonical endpoint/generation/payload data, count, and
publication epoch. Candidate/request/status arrays remain workspace.

## Executed evidence

The bounded relationship-substrate set passes 51/51 assertions. It covers:

- canonical endpoint order;
- create, retune, remove, and empty state;
- portable create/retune/remove agreement;
- stale-generation rejection with unchanged authoritative arrays and epoch;
- three ordered launches and zero unobserved transfers;
- descriptor-free execution-view adaptation;
- separate elastic strength/target/maximum columns;
- sequential and portable cross-domain retune to strength 50, target 8, maximum 12;
- cross-domain stale-edge failure atomicity; and
- portable lifecycle compaction of a stale edge.

The generic accepted-copy construction/candidate set passes 23/23 assertions. It covers distinct
candidate selection, activation short circuit, acceptance-only initial payload, category and
backend capability preflight, Adapt, normalized MCS/zero-based attempt identity, missing,
mismatched, orphaned, and duplicate component/effect rejection, and authoritative coupled-state
alias validation.

The exact dynamic-contact set passes 45/45 assertions. It covers:

- existing-link new-minus-old spring energy;
- a link joining the losing and gaining endpoints counted exactly once;
- losing-volume-one old-energy subtraction;
- all-incident endpoint-extinction removal;
- at most one canonical overlength removal for each affected endpoint;
- degree saturation before topology RNG evaluation;
- capacity and stale-generation failure with unchanged authoritative relationship state;
- canonical accepted-link insertion and the 0/0/100000 initial payload path;
- checkpoint reconstruction followed by deterministic uninterrupted/restarted agreement; and
- zero-byte warm proposal/energy/preflight execution.

The surrounding focused Phase 14 command also passes all scientific-Hamiltonian, normalized-kernel,
fixed-domain, Wortel, checkpoint, plan, field/exchange, intracellular, and event/multirate sets.
The full CorePotts suite passes 3411/3411 assertions with the dedicated relationship and
revision-6 polarity/force files included. The G3-B entry checker passes against contract revision
6. The G3-B closure checker intentionally remains open.

## Source correction

Implementation exposed an ambiguity in the earlier phrase “source FocalPointPlasticity
eligibility.” The
[focal-topology source audit](phase-14-g3b-focal-topology-source-audit.md) now freezes the exact
CompuCell3D 4.2.5 NeighborOrder-3 selection, RNG, activation, accepted-copy creation, initial
payload, and removal semantics. The machine-readable contract was advanced to revision 4.

## Explicitly open

G3-B relationship closure still requires:

1. controlled accepted/rejected/no-op and NeighborOrder-3 fixtures derived from the pinned CC3D
   source study, followed by the corresponding assembled Wang Potts-phase traces;
2. the complete assembled-model failure/publication matrix;
3. zero-allocation evidence for the complete sequential Potts process and whole non-observing MCS,
   not only the transaction effect;
4. complete-plan launch, transfer, order, and boundary visibility; and
5. the hash-addressed CC3D Potts/FPP source archive, line/symbol analysis, uncertainty register,
   and controlled-fixture report.

No new external CC3D execution is required. The already accepted scheduler-order trace remains
historical order evidence, not a live-runtime dependency for G3-B closure.

KernelAbstractions CPU execution proves the portable storage and transaction ABI only. Real Metal
and ROCm qualification remains G3-C.
