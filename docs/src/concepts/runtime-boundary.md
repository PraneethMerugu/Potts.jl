# [Runtime and Phase 16 boundary](@id runtime-boundary)

ProcessBigraphs and the current CorePotts execution engine are separate authorities during the
runtime transition.

## Stable documentation boundary

This manual documents behavior available through the current PottsToolkit, CorePotts, and
MakiePotts interfaces. ProcessBigraphs Phase 15 is an internal alpha foundation with fixed-structure
serial execution, canonical hierarchy, open composition, observation, continuation, and
checkpoint contracts documented inside its package.

That internal capability is not presented here as:

- a public runtime release;
- complete upstream parity;
- a replacement for CorePotts;
- evidence that an uncut Potts path uses ProcessBigraphs.

## Phase 16 work

Phase 16 develops checked structural add, remove, divide, move, and rewire transactions; dynamic
hierarchy; structural restart; and bounded Potts adapter slices. Each slice must preserve its state,
order, observation, RNG, continuation, and failure behavior through old/new differential execution
before authority can cut over.

Until that gate passes, documentation uses the current CorePotts spelling. After a slice passes,
the user-facing PottsToolkit spelling should remain stable where possible, while implementation and
capability pages record the new runtime authority and its checkpoint compatibility.

## Merge rule for this manual

Phase 16 documentation should enter this structure in three places:

1. **Learn/Examples** only for admitted user workflows;
2. **Concepts and Guarantees** for hierarchy, ports, structural barriers, lifecycle, failure, and
   checkpoint semantics;
3. **API** only for names that have passed the applicable stability gate.

Every page must state its support level and avoid describing a roadmap intention as implemented
behavior. Package-local ProcessBigraphs docs remain the authority for internal adapter and runtime
extension details during incubation.
