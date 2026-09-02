# Symbolic Potts V1 Static Evaluator Selection

Date: 2026-07-30

Status: bounded ordered n-ary callable tree selected; pending independent R1 confirmation

## Decision

V1 uses a typed operation tree with a maximum fanout of eight for associative addition and
multiplication. Ordinary mathematics is represented by concrete Julia callables. Contextual CPM
operations are concrete callable structs. Values that vary by occurrence remain descriptor fields,
and occurrences sharing evaluator structure occupy one homogeneous group buffer.

Evaluation preserves ordered left-fold semantics. A source operation larger than the fanout bound
becomes an ordered chain of bounded nodes; it is never algebraically reassociated.

The executable contains no opcode switch, registry lookup, closure, Symbolics value, device
allocation, or abstract evaluator dispatch. Downstream operations extend the versioned host
`OperationTransfer` protocol and provide a concrete isbits callable.

## Corrected experiment

[`scripts/qualify_static_evaluator.jl`](../../scripts/qualify_static_evaluator.jl) builds one
host-only semantic IR and lowers it into:

1. a recursive typed tree;
2. a bounded ordered n-ary typed tree; and
3. a compile-time-unrolled static SSA tuple.

It also independently compares CorePotts-owned arithmetic tags with the selected concrete-callable
execution boundary. Every candidate receives the same:

- concrete operation semantics;
- `QualificationOccurrence` records;
- parameter and evaluation context;
- genuine `CorePotts.RNGAddress` values spanning all semantic dimensions;
- exact Philox words and stochastic values; and
- canonical ordered interpreter result.

Node count varies over 16, 32, and 64. Depth varies independently at a fixed 64 nodes. Real
homogeneous descriptor buffers vary over `N=1,32,1,024`, and actual heterogeneous launch tuples
vary over `G=1,4,8`. Measurements include construction, host compilation, inference, `Any` slots,
warm allocation, typed statements, host/device LLVM, first and warm launch, Metal pipeline
properties available through reflection, and fixed-specialization hashes.

## Representative results

At 64 shallow semantic nodes on Metal:

| Representation | Execution | Representation nodes | Depth | Host LLVM | Metal LLVM | First launch | Warm |
|---|---|---:|---:|---:|---:|---:|---:|
| recursive tree | tags | 120 | 58 | 20,388 B | 472,642 B | 295 ms | 0.248 ms |
| bounded n-ary | tags | 72 | 11 | 16,118 B | 121,142 B | 244 ms | 0.245 ms |
| bounded n-ary | callables | 72 | 11 | 16,143 B | 127,711 B | 223 ms | 0.251 ms |

The bounded callable evaluator inferred `Float32`, contained no `Any` slots, allocated zero bytes
in its ordinary warm host evaluation, and returned the exact canonical stochastic result on CPU
and Metal. One specialization was reused unchanged at `N=1,32,1,024`.

At 32 semantic nodes and `G=1,4,8`, actual callable bounded-nary aggregate Metal LLVM grew from
89,053 B to 356,686 B to 713,352 B, matching the deliberately fixed-`G` design. Increasing `N`
did not change the evaluator signature.

Metal reflection reported zero static threadgroup memory, a maximum of 1,024 threads, and execution
width 32 for the measured kernels. Register counts were unavailable and are recorded as missing,
not inferred.

## Rejections

The recursive tree is rejected because representation depth and device code grow with expression
length: its 64-node shallow fixture generated 472,642 B of Metal LLVM, almost four times the
bounded n-ary candidate.

Static SSA is rejected as a general V1 evaluator. Its wide 64-node callable fixture generated
1,442,086 B of host LLVM, allocated on the warm CPU path, and failed Metal compilation with an
unsupported dynamic invocation. A deep/narrow SSA fixture can compile, but shape-sensitive
viability is unacceptable for the general evaluator.

CorePotts arithmetic tags are rejected as the operation boundary because the bounded callable
candidate met the same semantic, inference, specialization, and device gates without materially
regressing runtime or code size. Reimplementing Julia's elementary arithmetic therefore has no
measured justification.

The bounded ordered n-ary callable tree is selected because it has the best combination of
portable compilation, bounded structural growth, exact numerical semantics, open extension,
inspection, and maintainability.
