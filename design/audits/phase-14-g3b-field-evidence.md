# Phase 14.1 G3-B Atomic Field Evidence

Status: sequential CPU primitive accepted; portable backend execution remains open

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

Thirteen assertions in that field set directly cover the new primitive:

- the two staging arrays are distinct from each other and the authoritative array;
- five substeps produce exact Medium concentration 1 and leave the cell site unchanged;
- diagnostics publish the five-step transient result;
- a nonfinite reaction fails without changing values or time;
- a preflight stability failure changes no values; and
- a type-stable warmed 256×256, five-substep CPU invocation allocates exactly zero bytes.

The Phase 14 G3-B, G3-A, Phase 14.0, Phase 13 API-inventory, and repository-structure checkers also
pass after this slice.

## Explicitly open

G3-B still requires:

1. a backend-native field kernel and backend-resident validation/publication status;
2. CPU/Metal/ROCm adaptation and device-tree tests for the complete execution view;
3. the registered CC3D 4.2.5 field microtrace oracle;
4. tolerance-based impulse, periodic-edge, and reset-order comparisons against that oracle;
5. exchange/calibration and its typed cross-domain transaction; and
6. completed-MCS restart evidence in the assembled Wang plan.

No backend numerical claim may cite this CPU record as a substitute.
