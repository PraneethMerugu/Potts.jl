# Phase 14 Wang Execution-Order Audit

Status: accepted source and exact-runtime order; Wang implementation may use this order as its
CPU-reference authority

Date: 2026-07-25

Machine-readable authority:
[phase-14-wang-order-oracle-v1.toml](phase-14-wang-order-oracle-v1.toml)

Executable foreign-runtime evidence:
[CC3D 4.2.5 order evidence](../evidence/phase-14/wang-order/index.toml)

## Result

The previously unresolved scheduler placement is closed. In CompuCell3D 4.2.5, an ordinary Wang
MCS executes in this order:

1. Potts Metropolis;
2. XML steppables in declaration order: `DiffusionSolverFE`, then `BlobInitializer`;
3. `migration_racdir_fppSteppable` at frequency 1;
4. `OdeSteppable` at frequency 1;
5. `FocalPointPlasticityParams` when `mcs % 10 == 0`;
6. `OdeUpdateParams` at frequency 1; and
7. restart, lattice/screenshot output, script steering, and simulator steering.

None of the four Wang Python steppables sets `runBeforeMCS`, so no Wang Python process precedes
Potts. The order is supported independently by the exact 4.2.5 source and a noncommuting live
oracle on the official 4.2.5 macOS runtime.

## Provenance closure

The audit used:

- Wang paper DOI `10.1016/j.bpj.2025.04.010`; local reference PDF SHA-256
  `69fad81266dd41e1ba1e69fba3a7bed88efbac9dec2818e055cb4fd15beaa600`;
- Wang Git commit `60ebcf013aafefdff39ebe566114ee79f2a6e54d`;
- Zenodo `10.5281/zenodo.14928214`, archive SHA-256
  `1aa5c426a24075091761c2fc80873b1d7582b32bc038d761e71630c867c3e984`;
- CompuCell3D source tag commit `4ca1f2919a5da53111d2027d2e00b626aba1cd28`; and
- the official 4.2.5 macOS runtime image, SHA-256
  `a9a9d09653625663bfb5d2bff1a16e1e02bb8b193f028587136d4eab396fd076`.

The Git and extracted Zenodo source trees are byte-identical after excluding Git metadata. The
paper, upstream source, archive, and runtime remain external temporary references; only clean-room
fixture code and the small generated trace are committed.

## Static scheduler proof

The 4.2.5 command-line main loop runs `runBeforeMCS` Python steppables, calls `sim.step`, then runs
ordinary Python steppables. `Simulator::step` runs Potts Metropolis and then the C++ class registry.
The class registry is populated by iterating the XML steppable vector, so `DiffusionSolverFE`
precedes `BlobInitializer`. The Python registry iterates normal steppables in registration order and
applies `mcs % frequency == 0`.

`BlobInitializer` creates the initial lattice during startup; its position in each later C++ registry
step is behaviorally a no-op. It is retained in the order record so the XML declaration order is
not silently collapsed.

For the CPU field solver, `scaleSecretion` defaults to true. Each scaled field substep performs
diffusion and then its registered secretion/constant-concentration operations. Wang's Python
secretome uptake therefore occurs after the complete field solve and its medium concentration
reset.

## Live foreign-runtime proof

The clean-room fixture appends noncommuting digits to a shared Python sentinel:
`runBeforeMCS → first normal → second normal → frequency-10 normal`. It also makes pre-MCS Python
write `3` to a field whose XML solver imposes constant concentration `7`.

The exact runtime returned `1234` at MCS 0 and 10, `123` at every other MCS, and field value `7`
in normal Python on all 11 MCS. Thus:

- pre-MCS Python executes before the compiled Potts/XML block;
- normal Python executes after the XML field solver;
- normal Python registration order is stable; and
- frequency 10 fires at MCS 0 and 10.

The live fixture does not attempt to instrument the interior of `Simulator::step`; Potts-before-XML
is proven directly from the pinned C++ source.

## Wang read/write and boundary consequences

| Stage | Reads | Writes | Earliest consumer |
| --- | --- | --- | --- |
| Potts | prior force, focal links/parameters, ownership | ownership, geometry, neighbors, link lifecycle | same-MCS field and Python |
| field solve | post-Potts types and prior field | completed secretome field | same-MCS migration/uptake |
| migration/history/uptake | post-Potts COM, history, field | history, self polarity, uptake, `s`/multiplier | same-MCS ODE; next-MCS Potts for polarity-dependent force |
| ODE | same-MCS `s`, prior ODE state | `rac`, `a` | same-MCS force update |
| focal parameters, every 10 MCS | MCS, links | cell `fpp`, existing-link parameters | same-MCS force; next-MCS Potts |
| polarity/force/output | neighbor snapshot, `fpp`, `rac`, COM | aligned polarity, `lambdaVec`, records | next-MCS Potts |

At MCS 120, Potts still uses focal strength 0. The frequency-10 focal process writes 20 only after
that Potts step, so MCS 121 is the first Potts step to use 20.

At MCS 210, Potts still uses 20. The migration process performs calibration uptake and writes the
multiplier but does not write `s`; the ODE therefore advances with `s = 0`. The focal process then
writes the scanned strength, and the force process sees that new strength immediately. MCS 211 is
the first Potts step using the scanned focal strength and the force written at MCS 210. At MCS 211,
uptake writes `s` before the ODE, so that ODE step sees the same-MCS signal.

Neighbor polarity mixing is synchronous at the read boundary: all neighbor means are collected
before any aligned polarity is overwritten. The source's `lambda_fpp` lookup occurs after the
collection loop and therefore uses the last iterated cell; this is equivalent only because the
paper-v0 focal process assigns one global strength to every cell.

## Paper/source discrepancy

Paper Equation 11 defines displacement as `x(t) - x(t-5)`. The source first appends the current
`x(t)` and then indexes `[-5]`, which selects `x(t-4)`. The exact paper-v0 reproduction path will
preserve the source's four-interval displacement. The paper-intent five-interval version is a named
sensitivity variant; it must not silently replace the source behavior.

This discrepancy is now explicit rather than being normalized away during implementation.

## Accepted implementation constraint

The Wang CPU reference must encode this order in one inspectable `PlanSpec`, with the MCS 120,
210, and 211 visibility boundaries tested directly. GPU implementations must execute the same
semantic plan with backend-resident state; kernel fusion is permitted only when it preserves these
read/write snapshots and next-MCS visibility rules.
