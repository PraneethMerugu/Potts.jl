# Phase 14.1 G3-B Relationship Substrate Evidence

Status: bounded SoA storage, portable transactions, retuning, and lifecycle cleanup accepted;
accepted-copy topology/energy integration and foreign-runtime oracle remain open

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

Checkpoint payloads persist only active canonical endpoint/generation/payload data, count, and
publication epoch. Candidate/request/status arrays remain workspace.

## Executed evidence

The focused relationship set passes 51/51 assertions. It covers:

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

The surrounding focused Phase 14 command also passes all scientific-Hamiltonian, normalized-kernel,
fixed-domain, Wortel, checkpoint, plan, field/exchange, intracellular, and event/multirate sets.
The G3-B entry and Phase 14.0 architecture checkers pass against contract revision 4.

## Source correction

Implementation exposed an ambiguity in the earlier phrase “source FocalPointPlasticity
eligibility.” The
[focal-topology source audit](phase-14-g3b-focal-topology-source-audit.md) now freezes the exact
CompuCell3D 4.2.5 NeighborOrder-3 selection, RNG, activation, accepted-copy creation, initial
payload, and removal semantics. The machine-readable contract was advanced to revision 4.

## Explicitly open

G3-B relationship closure still requires:

1. proposal-time topology selection and `-50` activation-energy short circuit in the Potts
   evaluation path;
2. acceptance-only link creation in the same Potts transaction;
3. source-faithful at-most-one overlength removal per affected endpoint and extinction cleanup;
4. semantic-Philox portable neighbor permutation;
5. controlled accepted/rejected/no-op, degree-four, removal-order, and restart fixtures;
6. zero-allocation sequential whole-attempt/MCS evidence; and
7. the pinned CC3D Potts/FPP live-runtime trace.

KernelAbstractions CPU execution proves the portable storage and transaction ABI only. Real Metal
and ROCm qualification remains G3-C.
