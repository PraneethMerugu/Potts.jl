# ProcessBigraphs Phase 16.D Structural Transaction Audit

Date: 2026-07-27

Status: qualified

## Claim

ProcessBigraphs now owns immutable, atomic structural epochs for the canonical ProcessBigraph
ACSet. Typed add, explicit-closure remove, binary divide, move, and binding rewire requests execute
through `AlgebraicRewriting.jl` DPO rules. Raw rules, unrestricted rewrites, and implicit SPO
cascade remain outside the stable API.

This qualification does not claim that every biological or CorePotts lifecycle operation is an
orchestration-ACSet row. CorePotts domain topology remains an optimized leaf representation and
will emit these typed requests through the Phase 16.E adapter.

## Authority and atomicity

Requests carry a source epoch, stable semantic identities plus generations, dependencies, and an
optional stable priority. ProcessBigraphs validates identities and exact owned closure, selects
conflicts independently of arrival order, allocates deterministic identities, applies each
selected operation to an unpublished reference candidate, and differentially checks the genuine
DPO result before publication.

Equal-priority overlapping requests abort. A higher-priority request can reject a lower-priority
overlap, and the disposition remains observable in the staged result. Capacity, schema, cycle,
dangling-reference, stale-epoch, and integrity failures leave the source epoch unchanged.

Numeric state is opaque to this layer but participates in the same authorization boundary:
`publish_structural_transaction` accepts the new epoch only after its numeric validator succeeds.
There is no partially visible match, rewrite, topology, lineage, or numeric candidate.

## Identity, lineage, and restart

Semantic row identity is independent of ACSet row order. Retired identities remain recorded and
cannot be silently reused. Division retains the parent identity and allocates one daughter with an
explicit initialization/reconstruction policy and lineage record. Movement and rewiring preserve
identity.

Every settled structural epoch has a checksummed, integrity-validated exact checkpoint and restore
path. This is the structural component of the later Phase 16.E logical checkpoint; it is not a
claim that clocks, engine continuations, observers, or legacy formats are already migrated.

## Qualification

The focused suite passes 173 assertions:

- all five stable operations and per-operation DPO/reference differential;
- six permutations of a three-request independent batch;
- 81 bounded conflict/priority cases and a minimal counterexample shrinker;
- identity, generation, lineage, capacity, cycle, schema, and exact-owned-closure failures;
- failure injection at selection, reference, rewrite, validation, numeric validation, and
  publication;
- exact restart at every constructed settled epoch and continuation equivalence after restore.

The complete package suite passes 1,019 assertions: PB0 309, Phase 15.C 440, Phase 16 261, and
Aqua 9. The first attributed-ACSet DPO specialization is a measured cold cost; subsequent bounded
groups are warm. No steady-state performance claim is attached to orchestration rewrites.

Phase 16.C remains independently open for trusted exact-head Metal and ROCm artifacts. This audit
does not compensate for that hardware gate.
