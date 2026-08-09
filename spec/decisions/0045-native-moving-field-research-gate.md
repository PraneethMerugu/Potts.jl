# 0045: Insert a committee-reviewed native moving-field research gate

Status: Accepted

Date: 2026-08-09

## Context

G5H and R2H-C cleared an honest but deliberately narrow MethodOfLines profile: one output-only
fixed field on sequential CPU. Merks therefore retained `DiscreteFieldEuler`, because the accepted
adapter could not receive moving CPM occupancy without changing the modeled mechanism.

Subsequent analysis identified a plausible, materially better boundary: MethodOfLines could
discretize the PDE once, ModelingToolkit could compile a semi-discrete native system once, and
PottsToolkit could project staged occupancy into a typed numerical field input at each completed-MCS
boundary. A cached parameter update and persistent SciML integrator should not require symbolic
rediscretization or Julia recompilation when cells move.

That conclusion is not yet qualification. Important questions remain about the public upstream
API, input representation after discretization, persistent-integrator semantics, transactional
publication, exact replay, initialization, solver discontinuities, compilation cost, allocation
scaling, and GPU feasibility. Opening implementation from an architectural conversation would
repeat the uncertainty that G5H was created to remove.

## Decision

1. Insert the authoritative `G5H-R` native moving-field research gate after the cleared R2H-C
   checkpoint and before any G6 owner send-off.
2. Adopt the
   [Native Moving-Field Research and Amendment Gate](../symbolic-potts-v1-native-moving-field-research.md)
   as the authority for its questions, evidence, committee, amendment, and exit rules.
3. G5H-R is research-first. It may create isolated probes, benchmarks, and review records, but it
   may not change production behavior, public API, stable documentation claims, or passed
   capability rows before committee review.
4. A four-role committee independently reviews the complete packet. No role may be omitted or
   represented by an author of the research packet.
5. Only after the committee publishes its verdict may the gate prepare a bounded amendment to the
   G5H contract, capability matrix, preservation map, review state, and implementation order.
6. The committee checks that the proposed amendment faithfully implements its findings. The
   project owner then accepts, narrows, defers, or rejects that amendment.
7. An accepted amendment identifies the earliest reopened implementation gate and every invalidated
   downstream review. It does not silently overwrite historical passed evidence.
8. G6 remains closed until G5H-R exits, all work required by an accepted amendment passes, the
   required downstream reviews clear again, and the owner explicitly sends the project into G6.

## Consequences

- Existing G5H and R2H-C records remain correct for their exact commits.
- R2H-C clearance is no longer sufficient by itself to open G6.
- The native moving-field approach is a research candidate, not an accepted implementation
  requirement or support claim.
- Merks remains qualified under its current recorded implementation until an accepted amendment and
  replacement evidence say otherwise.
- CPU and GPU conclusions are separated. A successful CPU design does not imply MethodOfLines GPU
  support.
- A negative or deferred committee verdict is a valid result when it is supported by the required
  evidence and records the retained G5H disposition.

## Alternatives considered

### Implement the proposed MethodOfLines input immediately

Rejected. It would change native IO, runtime continuation, field capability, Merks authorship, and
possibly checkpoint semantics without first resolving upstream and performance uncertainty.

### Leave the cleared G5H record untouched and move to G6

Rejected. G6 is intended to stabilize a complete integration spine, not freeze a custom field
kernel if a substantially more cohesive native path is practical.

### Rewrite the existing G5H and R2H-C evidence in place

Rejected. Qualification is exact-state evidence. Later research may supersede a disposition, but
it cannot make the historical review claim something it did not review.

## Required conformance evidence

- The research packet answers every mandatory question in the new gate with primary-source and
  executable evidence.
- Every committee role files an independent disposition and the synthesis preserves dissent.
- No production or support-claim change precedes the committee verdict.
- Any amendment contains a clause-level G5H impact map, preservation impact map, capability delta,
  exact reopened-gate list, implementation matrix, and review rerun list.
- The living control record keeps G6 closed until the complete accepted route clears.
