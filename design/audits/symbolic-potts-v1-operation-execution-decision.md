# Symbolic Potts V1 Operation Execution Decision

Date opened: 2026-07-30

Status: option C selected; pending independent R1 confirmation

## Decision question

Should the device evaluator continue to execute ordinary mathematics through CorePotts-owned
operation-tag methods, or should host operation schemas remain separate from execution while
ordinary operations lower to concrete Julia callables?

The concern is architectural, not merely syntactic. A typed operation tree is justified by
inference, grouping, GPU, inspection, and external-extension requirements. That does not by itself
justify CorePotts redefining the execution meaning of `+`, `-`, `*`, `/`, `^`, `max`, `min`,
`abs`, `exp`, `log`, `sqrt`, and `ifelse`.

## Candidates R1 must compare

### A — CorePotts operation tags

Retain concrete `BuiltinOperation{:identity}` values and CorePotts
`apply_operation(tag, arguments, context)` methods for ordinary mathematics.

### B — Concrete Julia callables

Keep `OperationTransfer` as host analysis and serialization authority, but lower ordinary
mathematics to concrete singleton callables such as `+`, `*`, `sqrt`, and `ifelse`. Use concrete
callable structs only for genuine CPM primitives such as state/context/workspace access, semantic
RNG, neighborhood queries, and relationship operations.

### C — Restrained hybrid

Lower ordinary scalar Julia mathematics to concrete callables; retain explicit CorePotts callable
objects for CPM/resource operations and one bounded ordered-fold primitive where flattened
associative Symbolics calls require a declared floating-point order.

## Mandatory comparison criteria

R1 must not clear this decision from taste alone. Every viable candidate must prove:

- one concrete, inference-stable device representation with no runtime opcode switch, abstract
  dispatch, registry lookup, closure, or Symbolics value;
- identical ordered numerical semantics under the declared floating-point policy;
- bounded fanout/depth and fixed-`G` specialization behavior at `N=1,32,1,024`;
- open downstream operations without editing a CorePotts switch, enum, or union;
- host schemas remain the authority for semantic identity, versioning, arity, units, purity,
  totality, locality, capabilities, diagnostics, fingerprints, and serialization;
- CPU and functional Metal compilation of the exact evaluator, descriptor buffer, context, state,
  workspace, and group-launch arguments;
- complete inspection and qualified diagnostics;
- no material regression in inference, generated host/device code, first launch, warmed execution,
  or maintainability; and
- ordinary Julia mathematical meaning is not duplicated unless a measured compiler/device
  constraint makes that duplication necessary.

`Symbolics.build_function` and runtime-generated functions remain deferred host-codegen candidates
unless they independently pass the same device, inference, inspection, external-operation, and
generated-code gates.

## Checkpoint rule

The corrected CCV1-008 experiment must include the strongest callable-based candidate. The selected
option and rejected alternatives must be recorded before R1. The decision is now resolved, but the
G2 checkpoint remains blocked until independent R1 confirms the evidence and implementation.

## Resolution

Option C, the restrained hybrid, is selected.

- ordinary scalar mathematics lowers to Julia's named singleton functions;
- variadic `+`, `-`, `*`, `/`, `max`, and `min` lower through a concrete `OrderedFold` where a
  tuple-preserving left fold is required; only associative `+` and `*` may be split into bounded
  evaluator nodes, without reassociation;
- contextual and resource-sensitive CPM operations are concrete callable structs;
- `OperationTransfer` remains the host authority for identity, versioning, arity, units, purity,
  totality, locality, capabilities, diagnostics, fingerprints, and serialization; and
- neither CorePotts nor downstream packages extend a central arithmetic switch.

The operation hook is therefore named `operation_callable`. The executable expression stores the
callable itself. Named singleton functions are admitted at the CorePotts boundary; closures remain
rejected.

## Evidence

The corrected [`scripts/qualify_static_evaluator.jl`](../../scripts/qualify_static_evaluator.jl)
constructs one shared host semantic IR and lowers it independently to the tag baseline and callable
hybrid. Both receive identical concrete occurrence records, context, parameter buffers, genuine
`CorePotts.RNGAddress` values, Philox words, and ordered expected results.

For the selected bounded n-ary representation at 64 shallow semantic nodes:

| Execution | Host LLVM | Metal LLVM | Metal first launch | Metal warm |
|---|---:|---:|---:|---:|
| CorePotts arithmetic tags | 16,118 B | 121,142 B | 244 ms | 0.245 ms |
| concrete callable hybrid | 16,143 B | 127,711 B | 223 ms | 0.251 ms |

At `G=8`, aggregate Metal LLVM was 697,712 B for tags and 713,352 B for callables. Both paths
inferred `Float32`, had no `Any` slots, preserved exact ordered stochastic semantics, compiled on
CPU and Metal, and reused one specialization unchanged at `N=1,32,1,024`. The callable code-size
difference is small and did not produce a material launch or warm-runtime regression.

Option A is rejected because it duplicates Julia arithmetic semantics without a measured compiler
need. A callable static-SSA option is rejected because a wide 64-node expression produced
1,442,086 B of host LLVM, allocated on the warm CPU path, and failed Metal compilation. The
bounded n-ary callable does not share those failures. `Symbolics.build_function` remains deferred
under the same qualification gates.
