# LM-1 final review

Date: 2026-08-22

Disposition: **APPROVE**.

The final committee reviewed the production source and retained evidence after
the stage-local compiler, LM-1B physical ABI, tuple-local preparation, and
relationship-authority corrections. All four required perspectives approve.

## Compiler and Julia design

Approved after the gate was strengthened to require:

- three fresh processes at 1, 4, 8, 13, and 32 stages;
- the frozen host-compilation and fresh-process affine bounds;
- seven warm samples with zero compilation and recompilation;
- exact 21-launch four-stage execution;
- exact current CorePotts logical, physical, bank, callback, and phase-order
  identities; and
- the explicit LM-1 amendment that supersedes only the deleted structural
  flagship identity while retaining LM-0's numeric ceilings.

The final one-stage maximum is 2.473 seconds and the final four-stage maximum
is 14.654 seconds. The reviewer found no reason for another compiler IR,
cache, executor, or runtime redesign.

## GPU and performance engineering

Approved after public device FixedRelations gained explicit generation,
status, and validated-generation authority. The retained real-Metal evidence
is 55/55 assertions: 38 StageProgram assertions, 15 focused Resolve assertions,
and two corrected cross-domain witnesses. CPU and GPU use one packed-storage
KernelAbstractions path; no raw vendor kernel or host relationship conversion
enters warm execution.

## Scientific modeling

Approved with deterministic Reduce/Resolve/Collect behavior, exact tie and
rank failures, relationship requalification, persistent projection, empty
behavior, diagnostics, and no-write failure atomicity preserved. CorePotts
retains the lifecycle transaction meaning; LocalMath owns only the following
Collect publication.

## Simplification and maintainability

Approved after:

- Collect reset dropped the full physical plans from its ABI;
- the duplicate Collect validation field was deleted;
- physical launch accounting was centralized in one cold evidence helper;
- exact phase-family order replaced repeated preparation-type labels; and
- stale whole-program compiler-group assertions and documentation were
  replaced by the stage-local authority.

The resulting system has one production stage-local spine and one KA backend
path. No migration selector, compatibility executor, prototype runtime, or
second physical IR remains.

## Machine authority

`julia --startup-file=no scripts/check_localmath_lm1_gate.jl` validates the
row-level source cutover, exact exports and kernels, packed relationship-state
boundary, compiler manifests and bounds, warm compilation, current flagship
identity, and retained real-GPU packet. The approved ledger disposition is
`implemented_review_approved`.
