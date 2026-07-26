# Phase 14.1 G3-B Atomic Field Evidence

Status: pinned CC3D field semantics plus sequential CPU and portable KernelAbstractions reference
accepted; Metal/ROCm execution remains G3-C

Date: 2026-07-25

## Scope

This record covers only the reusable transient-field primitive required by the Wang secretome
slice. It is not G3-B closure and it is not Metal or ROCm qualification.

The implementation now provides:

- one authoritative field array and two same-shape, construction-time staging arrays;
- an `Adapt` path for the authoritative array, forcing array, and both staging arrays;
- allocation-free warm sequential CPU execution;
- fixed-substep forward Euler reaction--diffusion;
- explicit diffusion-stability rejection before staging begins;
- two-dimensional periodic four-neighbor arithmetic with fixed x-pair then y-pair grouping;
- ordered generic `post_substep` constraints;
- exact `ConstantConcentration(:medium, 1.0f0)` application after every internal substep;
- one immutable ownership snapshot for the whole invocation; and
- process failure atomicity: invalid staged values never overwrite authoritative field values,
  field time, or published diagnostics.

The portable profile now additionally provides:

- one backend-native kernel per internal substep;
- the same fixed periodic arithmetic and exact post-substep Medium reset;
- backend-resident status and canonical failing index;
- a conditional field commit and authoritative backend publication epoch;
- no host scalar access or transfer during unobserved execution; and
- one explicit stable-boundary synchronization that publishes host semantic time/diagnostics or
  raises the recorded failure.

The two staging arrays remain execution workspace and are excluded from checkpoints. Generic
accumulated forcing remains authoritative only for models that declare it; the Wang profile uses
no such forcing.

## Executed evidence

The focused Phase 14 test run passed:

- 740 scientific Hamiltonian assertions;
- 125 normalized-kernel assertions;
- 8 fixed-domain/obstacle assertions;
- 10 fixed-exterior assertions; and
- all Phase 14 dynamic-state test sets, including 35 assertions in the continuous-system/field
  set.

The original thirteen assertions cover the sequential primitive. The later portable gate adds
direct CPU-versus-KernelAbstractions equality, eight-launch accounting, zero transfer accounting,
deferred semantic-time publication, and nonfinite staged failure with unchanged authoritative
values and epoch.

- the two staging arrays are distinct from each other and the authoritative array;
- five substeps produce exact Medium concentration 1 and leave the cell site unchanged;
- diagnostics publish the five-step transient result;
- a nonfinite reaction fails without changing values or time;
- a preflight stability failure changes no values; and
- a type-stable warmed 256×256, five-substep CPU invocation allocates exactly zero bytes.

The Phase 14 G3-B, G3-A, Phase 14.0, Phase 13 API-inventory, and repository-structure checkers also
pass after this slice.

The source-derived splitting, five-substep scale, periodic field/no-flux Potts distinction, and
reset-after-every-substep timing are frozen in `phase-14-g3b-field-source-study.md`. Real Metal and
ROCm execution remains G3-C; no backend numerical claim may cite this CPU record as a substitute.
