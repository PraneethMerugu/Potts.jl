# Phase 14 G3-B Wang/RoadRunner Coupling Source Study

Status: accepted mathematical and coupling semantics; solver-build trajectory equivalence remains
explicitly unclaimed; no live RoadRunner oracle required

Date: 2026-07-25

## Source identity

The Wang source is commit `60ebcf013aafefdff39ebe566114ee79f2a6e54d`; the wrapper source is
CompuCell3D tag `4.2.5`, commit `4ca1f2919a5da53111d2027d2e00b626aba1cd28`.

| Source | SHA-256 | Relevant symbols or lines |
|---|---|---|
| Wang `fpp_polarity_force_Steppables.py` | `2633fd41c85b5256b2d2975b9bc60b28271bb1f7dd1c9b72e015788ac847cc30` | Antimony 36–50; startup 180–200; repeated coupling 202–217 |
| CC3D `RoadRunnerPy.py` | `57a8135f6d606ef1a1a7f3f7cb771435778a9cde560759014759cc5ccc9108bf` | construction 9–22; `timestep`, 30–43 |
| CC3D `SBMLSolverHelper.py` | `f12bdba99bd7a5734f28c0abe03e57cc1c0a57b3d70df3068d14b2e6e6d81dd5` | cell-type attachment 457–517; cell stepping 846–862; aggregate stepping 1009–1017 |

## Exact coupling law

The Antimony reactions define

`drac/dt = a + s - d*rac`

with `a=1`, initial `s=0`, and `d=0.1`. Wang requests `step_size=2880`. CC3D stores that as
`RoadRunnerPy.stepSize`; each `timestep()` calls `simulate(timeStart, timeStart+stepSize, steps=1)`
and then publishes the new end time as the next start time.

Wang overwrites Antimony's textual `rac=2` with a NumPy uniform draw on `[0,30)`, then invokes one
SBML timestep in `start()` before source MCS 0. For each source MCS greater than 120, the earlier
migration steppable publishes that MCS's signal `s`; `OdeSteppable` writes it into RoadRunner,
advances once by 2880, then publishes `rac` and `a` back to cell attributes. No ODE advance occurs
for source MCS 0:120 after the startup call.

Potts.jl realizes this with the generic closed-form affine law:

`rac(t+Δ) = (a+s)/d + (rac(t)-(a+s)/d)*exp(-d*Δ)`.

For `Δ=2880`, the transient is far below Float32 resolution, so controlled source fixtures reach
10 when `s=0` and 50 when `s=4`. The exact schedule is one startup advance followed by target MCS
122:500 in the preregistered closure workload. Semantic time at target 500 is therefore
`380*2880 = 1_094_400`.

## Exact publication order

The source registration order is migration/exchange, ODE, FPP retune, then neighbor
alignment/force. Therefore the ODE reads the same source-MCS signal publication, while the force
published later in the MCS affects the next Potts phase. Potts.jl represents these as typed plan
edges and candidate/snapshot transactions; there is no model-specific callback.

## Numerical-profile boundary

The CC3D wrapper documents default absolute tolerance `1e-10`, relative tolerance `1e-5`, and
non-stiff selection when no options are supplied. Wang supplies no integrator or option override.
The archived CC3D source does not pin the installed libRoadRunner binary, compiler, CVODE build, or
Antimony translator version. Consequently:

- the affine mathematical law, inputs, timing, and publication boundaries are exact;
- Potts.jl CPU and portable paths are checked against the closed form;
- no bitwise RoadRunner trajectory claim is made; and
- a foreign solver run is not required to qualify this generic affine case.

## Qualification mapping

- `lib/CorePotts/test/test_phase14_dynamic_state.jl` covers semantic RNG initialization, startup,
  closed form, schedule boundaries, atomic failure, restart payload, allocation, and CPU/portable
  equality.
- `integration/conformance/test_phase14_wang_runtime.jl` exercises the same declaration in the
  assembled target-MCS 0:500 plan.

This is deliberately a coupling study, not an embedded RoadRunner integration. More general ODE
systems remain available through the external model adapter architecture.
