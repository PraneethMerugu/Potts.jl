# LM-1 compiler remediation evidence

Date: 2026-08-22

Disposition: **RED**. The compiler/Julia review does not approve LM-1 against
the frozen LM-0 compiler envelope.

## Direct compiler-boundary edits

- Structural relation validation is now one no-inline, unspecialized,
  iterative cold pass. It no longer recursively grows prior-binding and
  prior-proof tuple types.
- Global `_FieldSlot`, `_RelationSlot`, and `_CollectionSlot` values now carry
  checked positive `Int32` ordinals. Only prepared stage-local field slots and
  parameter projections retain type-indexed ordinals.
- `_PreparedStageProgram` retains validation contexts in compiler-bounded
  groups and no longer owns a flattened all-stage status tuple.
- `PreparedWork` no longer specializes on the complete cold `WorkPlan` type;
  executable runtime, workspace, lane, callables, and submission layout remain
  concrete.
- Submission freshness no longer recovers that erased plan through a warm
  abstract-field dispatch. Preparation seals only static CPU relation leaves
  into a width-erased `_PreparedFreshnessAuthority`; its reusable four-word
  fingerprint scratch validates with an inferred `Nothing` return and zero
  allocations. Dynamic relations remain queued receipt-gated.
- The dead `_prepared_stage_groups` generator was deleted.

The focused value-slot and sealed-proof testset passed 58/58. Production load
and `git diff --check` were green at this evidence boundary.

## Corrected compiler witness

`benchmark/lm0/compiler_case.jl` now cycles the five required law families:
Unique, Reduce, Resolve, Collect, and OrderedFold. Its
`physical_launch_count` is derived from the prepared physical program and its
actual executor algorithms; it is no longer an alias for logical stage count.

The corrected four-stage fresh CPU observation used Julia 1.12.6,
KernelAbstractions CPU, `--compiled-modules=existing`, `--compile=yes`, and
`--optimize=2`:

| boundary | elapsed (s) | compilation (s) |
|---|---:|---:|
| construction | 0.56794 | 0.56669 |
| binding | 0.17924 | 0.17912 |
| planning | 17.10342 | 17.08406 |
| preparation | 32.76441 | 32.75431 |
| first completed execution | 0.31133 | 0.31093 |

Total recorded host compilation was **50.89510 seconds**. The prepared
four-stage program contained **43 physical KernelAbstractions launches**. One
subsequent warm `run!` plus `wait` allocated 17,936 bytes in the harness.

This remains far above the frozen four-stage host-compilation ceiling of
approximately 15.05 seconds. A 32-stage run was intentionally interrupted
after more than 150 seconds without completing planning; its LLVM stack was
inside `_stage_draft_from_projection`. No 32-stage passing observation is
claimed.

## Remaining engineering conclusion

The private group representation is principled, but grouping and cold type
erasure alone cannot close this gate. A second, instrumented four-stage pass
localized planning compilation as follows: bound validation 1.55 seconds,
stage planning 0.29, four group-input constructions 1.59/1.36/0.40/0.61,
group lowering 6.48, program-workspace construction 2.28, and program evidence
0.71. Within group lowering, effect analysis was only 0.31 seconds for the
first stage and 0.001--0.011 for later stages; construction of the four typed
workspace entries cost 0.93/0.72/1.12/2.02 seconds. The evidence does not
support blaming repeated effect analysis as the primary scaling defect.

The same pass localized preparation compilation as follows: automatic
workspace materialization 21.53 seconds, validation 1.16, typed workspace-array
extraction 0.62, structural checks 0.10, binding checks 0.20, parameter layout
0.06, runtime preparation 4.80, callback facts 2.19, and exact backend
qualification 4.96. Automatic workspace construction was therefore changed
from recursively specialized overloads to one no-inline, unspecialized cold
interpreter over the authoritative template. It preserves empty typed
containers, leaf names, and the exact tree; an initially investigated
leaf-only reconstruction was rejected because leaves cannot represent required
empty containers. The isolated four-stage materialization observation fell
from 21.53 to **11.62 seconds**, with 29.4 MB allocated in the latter run.

Planning nevertheless remained approximately 17.56 seconds in the fresh
four-stage process, so even the materialization improvement cannot close the
frozen gate. No 32-stage run was made during the second pass. Preparation still
compiles a large multi-kernel physical program: in this witness each
Candidate-family stage accounts for roughly twelve launches and the Collect
stage for seven. Further remediation must shrink typed workspace-entry
construction and the physical compiler surface while preserving the one Stage
lifecycle, exact conflict semantics, exact workspace tree, and the same
KernelAbstractions CPU/GPU path. The frozen envelope must not be refit to
approve the current result.
