# Phase 14.1 G3-B Closure Specification Audit

Status: accepted corrections incorporated into G3-B entry contract revision 2

Date: 2026-07-25

## Purpose

This audit cross-checks the Wang G3-B entry packet against the accepted one-clock, process,
atomicity, persistence, GPU-native, and generic-authoring contracts before implementing the
periodic secretome field and uptake/calibration exchange.

The existing Phase 14 structural checkers passed before this audit. They proved registry coverage
and selected source boundaries, but did not compare internal numerical commits with stable
checkpoint boundaries, source MCS labels with normalized target MCS, or declared cross-domain
writes with the concrete process transaction protocol.

## Resolved findings

### Source MCS zero

CompuCell3D executes a real Potts/field/Python iteration labelled MCS 0. Potts.jl defines MCS 0 as
the finalized initial condition. Hiding the foreign iteration in initialization would make one
Potts attempt budget disappear from public time and RNG accounting.

Resolution: source MCS `k` maps to normalized target MCS `k+1`. Source `0:499` maps to target
`1:500`. The source label is exactly derived observation/provenance metadata, not a second clock.
Only source `start()` hooks execute before finalized Potts.jl MCS 0.

### Field substep atomicity and restart

The original entry contract called every field substep an atomic commit and persisted a completed
substep boundary. The semantic kernel permits numerical publication only at the process commit and
stable checkpoint capture only after completed-MCS observation.

Resolution: all five field substeps are internal staging operations over one immutable post-Potts
ownership snapshot. One process commit publishes the validated result. No internal substep or
post-field phase is a stable checkpoint.

Strict failure atomicity requires one authoritative field plus two staging grids. Two total grids
would force the authoritative field to be overwritten by the second substep before the fifth
substep had validated.

### Field shape and constraint semantics

The source records a 256×256×1 lattice while the numerical law is two-dimensional. The
`ConstantConcentration` operation had also been described as forcing even though CC3D applies an
exact overwrite after each diffusion substep.

Resolution: runtime field storage is a logical 256×256 matrix and the singleton source z extent
remains provenance. The numerical law uses exactly four x/y neighbors. Medium concentration is a
generic post-substep reservoir constraint, not an additive forcing term.

### Exchange scheduling

The original plan invoked one unscheduled exchange while the process internally selected reset,
calibrate, or publish behavior from MCS. That would create a process-local scheduler outside the
one root plan.

Resolution: the root plan supplies one immutable exchange mode:

| Target MCS | Source MCS | Mode |
| ---: | ---: | --- |
| 1–121 | 0–120 | inactive |
| 122–210 | 121–209 | reset |
| 211 | 210 | calibrate |
| 212–500 | 211–499 | publish |

The exact public constructor spelling remains Provisional, but canonical lowering and inspection
must contain this complete mode table.

### Calibration ownership

The foreign source duplicates one identical calibration multiplier into every cell dictionary.
Treating those copies as independent cell state creates unnecessary lifecycle and reduction
semantics.

Resolution: the normalized model owns one global multiplier value and initialized status.
Per-cell source-shaped copies are derived observation data if required for comparison.

### Cross-domain publication

Uptake changes a field and produces per-cell and global outputs in one scientific operation. The
provisional runtime process protocol could mutate coupled field state or specially handled
`CellDynamics` properties, but could not publish both generically.

Resolution: field exchange requires a typed cross-domain write set and one logical publication
epoch. Candidate field, signal values, multiplier/status, reductions, and invariants validate
before publication. A failed exchange exposes no partial state to later processes, observations,
or checkpoints.

### Reduction and failure policy

The original phrase “deterministic reductions” did not select an accumulation order, and
`4 / maximum(raw uptake)` had no zero-maximum rule.

Resolution: the source-faithful CPU oracle uses ascending active slots and ascending linear sites.
The portable Wang profile uses a width-256 per-cell fixed reduction tree and a fixed global maximum
tree. Floating atomics are forbidden. Zero or nonfinite calibration maximum is a structured domain
failure that commits nothing.

### Numerical registration

The original `exact-and-tolerance` fixture labels did not state numerical bounds.

Resolution: revision 2 preregisters local field and uptake tolerances plus a mass-scaled balance
bound. Exact schedules, identities, periodic indices, Medium overwrite values, statuses, and
publication epochs remain exact. A later tolerance change requires a new evidence revision.

## G3-B closure gate

G3-B cannot close until:

1. every registered Wang state and process has a generic canonical declaration and sequential CPU
   implementation;
2. the source-faithful conformance rows pass;
3. portable device-readiness proves adaptable descriptor-free state, preallocated workspaces,
   typed cross-domain writes, and backend status propagation;
4. field and exchange warm CPU paths allocate zero bytes;
5. field and exchange failure atomicity passes;
6. source/target MCS mapping and source 120/210/211 boundaries pass directly;
7. completed-MCS restart passes and internal-substep/mid-phase capture rejects;
8. the Potts boundary/attempt, RoadRunner, and CC3D numerical-field runtime oracles close;
9. G3-A, Phase 13 fingerprints, API inventory, checkpoints, behavior, and evidence remain
   unchanged; and
10. the evidence record contains the registered numerical profile before paper-scale result
    inspection.

Metal and ROCm numerical execution remains G3-C, but G3-C may not alter the logical state,
workspace sufficiency, plan modes, process snapshots, or publication boundaries established here.

## Implementation status and warning

The sequential CPU transient-field primitive has now been corrected against revision 2: it owns
two preallocated staging grids, applies ordered post-substep constraints, rejects unstable or
nonfinite work before publication, and allocates zero bytes after warm-up. Its evidence is recorded
in [phase-14-g3b-field-evidence.md](phase-14-g3b-field-evidence.md).

The sequential CPU exchange transaction has also been replaced against revision 2. Its mode-bound
path declares field/cell/global writes, uses preallocated candidates, publishes one logical epoch,
and records the calibration state required for restart. Evidence is recorded in
[phase-14-g3b-exchange-evidence.md](phase-14-g3b-exchange-evidence.md). The legacy three-argument
forcing overload remains compatibility-only prototype behavior.

Field and exchange remain CPU-only numerical evidence until their fixed-tree reductions,
validation status, and conditional publication execute backend-natively and pass the registered
device gates.
