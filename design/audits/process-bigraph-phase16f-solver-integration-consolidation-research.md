# ProcessBigraphs Phase 16.F Solver-Integration Consolidation Research

Status: Accepted repair basis; implementation and qualification open

Date: 2026-07-27

Prototype commit: `7217f9b67db3bc0e798bab192e81ad3a8923b912`

Prototype tree: `ea4ee239dc596c30fc44c3d396a18ad6e19c1ea5`

## Purpose

This research round consolidates the owner interviews, current SciML and CommonSolve interfaces,
Julia package-extension semantics, and the useful architectural lessons from Mermaid.jl into a
bounded repair target for Phase 16.F. It does not reopen qualified Phase 16.A/B/D/E work or
substitute for the still-open exact-head Metal and ROCm evidence in Phase 16.C.

The governing result is:

> Use a Mermaid-sized real-solver integration inside a ProcessBigraph-grade transactional
> envelope.

ProcessBigraphs continues to own when and why computation occurs. A selected solver continues to
own how its authorized numerical operation occurs.

## Sources reviewed

Primary and project sources were reviewed on 2026-07-27:

- CommonSolve interface: <https://docs.sciml.ai/CommonSolve/>
- SciMLBase algorithms: <https://docs.sciml.ai/SciMLBase/stable/interfaces/Algorithms/>
- SciMLBase problems and `remake`: <https://docs.sciml.ai/SciMLBase/stable/interfaces/Problems/>
- SciMLBase solutions and return codes:
  <https://docs.sciml.ai/SciMLBase/stable/interfaces/Solutions/>
- DifferentialEquations integrator interface:
  <https://docs.sciml.ai/DiffEqDocs/stable/basics/integrator/>
- OrdinaryDiffEq usage: <https://docs.sciml.ai/OrdinaryDiffEq/stable/usage/>
- Julia package extensions: <https://docs.julialang.org/en/v1/manual/code-loading/>
- Mermaid.jl repository: <https://github.com/eebio/Mermaid.jl>
- Mermaid.jl JuliaCon 2026 abstract: <https://pretalx.com/juliacon-2026/talk/EJVNCK/>
- Locally resolved Mermaid.jl revision
  `d4c89d0ea09af8d96bcdc42ef6bd5dd967fc7a0d`, especially `Project.toml`,
  `ext/DiffEqExt.jl`, `src/solvers.jl`, `src/connections.jl`, and the interface documentation.

The repository sources are the normative authority. External projects are research inputs, not
dependencies or semantic authorities.

## Findings

### SciML and CommonSolve

CommonSolve supplies the shared `init`, `solve!`, `step!`, and `solve` vocabulary and requires
packages to dispatch on a type they own. SciML solver packages already own the methods that solve
SciML problems with their algorithms. Therefore, ProcessBigraphs MUST NOT add its own
`solve(::SciMLBase.ODEProblem, ...)` method merely to simulate solver integration.

The qualified SciML adapter must accept a real algorithm object and canonical solver options.
For an interval operation it may initialize a solver-owned integrator and call the solver's
supported exact-target operation, including `step!(integrator, dt, true)` where that interface is
applicable. It must use standard SciML failure interfaces such as
`SciMLBase.successful_retcode` and integrator error checking.

`SciMLBase.remake` is the standard way to reconstruct a problem with new initial state, parameters,
or span. It is preferable to mutating a published problem or depending on solver cache layout.

### Mermaid.jl

Mermaid's useful pattern is small and direct: its differential-equation component stores a real
problem, a real injected algorithm, and solver options; its extension initializes the solver and
advances the solver-owned integrator. Core Mermaid stays comparatively light while
DifferentialEquations support is extension-provided.

ProcessBigraphs should adopt that narrow integration shape, but not Mermaid's orchestration
semantics. Phase 16 retains exact logical time, immutable snapshot visibility, staged candidates,
atomic publication/abort, typed continuation, explicit replay class, and order-independent
reconciliation. It does not adopt floating scheduler time, live cross-component mutation,
order-dependent connectors, implicit cache persistence, string selectors, runtime expression
evaluation, or nontransactional stepping.

Mermaid.jl is neither a Phase 16 dependency nor a scheduler underneath ProcessBigraphs. Future
interoperability may be considered only as a separately qualified adapter.

## Prototype audit

Commit `7217f9b67db3bc0e798bab192e81ad3a8923b912` is useful executable exploration, not Phase 16.F
qualification evidence. It currently:

- defines a home-grown `P16FixedEuler` algorithm and
  `solve(::SciMLBase.ODEProblem, ::P16FixedEuler)` method;
- returns a nonstandard `P16SciMLSolution` with a symbol return code;
- hard-codes the algorithm and rejects all solver options;
- implements the independent custom numerical adapter inside ProcessBigraphs core;
- compares two effectively identical Euler loops;
- claims exact replay for floating numerical paths; and
- exports a broad unqualified Phase 16 surface.

These are implementation defects in 16.F, not defects in the already-qualified transactional
protocol.

## Accepted consolidation decisions

1. ProcessBigraphs MUST NOT own a numerical `solve` method for SciML problem types.
2. A qualified SciML declaration MUST contain an explicit real solver algorithm. Automatic
   algorithm selection is experimental and outside the qualified Phase 16 envelope.
3. Solver options MUST use a bounded typed or canonical representation, be validated before
   staging, and contribute to the declaration fingerprint.
4. ProcessBigraphs core MUST retain no hard SciML or OrdinaryDiffEq dependency. SciMLBase and
   CommonSolve remain weak extension triggers; a concrete solver package is a test/application
   dependency, not a core dependency.
5. Exact ProcessBigraph target time MUST be enforced through a solver-supported exact-target
   operation. Overshoot, interpolation as publication, and silent rounding are forbidden.
6. Solver completion MUST be interpreted through standard SciML return/error interfaces and
   normalized into ProcessBigraph diagnostics or typed failure.
7. Adapter semantic version, problem envelope, algorithm identity, canonical options, package
   resolution, exact-target policy, continuation policy, and replay class MUST enter
   fingerprint/provenance evidence.
8. The initial generic Phase 16 SciML continuation policy is
   `reconstruct_each_invocation`: remake or construct a fresh problem and integrator from the
   last published canonical state. Its default replay class is numerical.
9. Retained integrator continuation MAY be added only for a separately declared adapter envelope
   with a qualified clone/codec, invalidation policy, restart proof, and replay classification.
   Generic `deepcopy` or Julia serialization of an integrator is not a continuation contract.
10. All numerical work occurs against isolated candidate state. A solver MUST NOT mutate the
    published logical state or a published integrator before authorization.
11. The custom adapter is an external-style conformance fixture outside ProcessBigraphs core. It
    MUST NOT import SciML or share a numerical stepping helper with the SciML realization.
12. Cross-adapter evidence MUST use analytic or manufactured solutions, refinement/convergence,
    boundary and conservation cases, and failure/restart cases. Equality between two copies of
    the same Euler loop is not an independent scientific oracle.
13. The docs MUST state the accuracy limits of the globally visible CPM/field split and the
    solver-specific numerical error inside each invisible interval.
14. Phase 16.F may admit only the smallest authoring surface needed to construct declarations.
    Concrete instances, candidates, solution wrappers, caches, and conformance fixtures remain
    internal. The prototype's broad exports are not admitted API.

## 16.F repair and qualification order

The original 16.F ledger rows remain stable; no extra bureaucracy or new phase is introduced.
They are completed in this mandatory order:

1. **16.F0 consolidation:** remove the prototype solver piracy and solution type, inject a real
   algorithm/options declaration, adopt standard success handling, move the custom fixture out of
   core, restore the admitted export boundary, and keep A–E tests unchanged.
2. **P16-F01:** qualify the CPU SciML envelope with a concrete solver package and transaction,
   failure, restart, declaration-fingerprint, and exact-target evidence.
3. **P16-F02:** qualify the external-style independent custom adapter against the open protocol.
4. **P16-F03:** qualify analytic/manufactured and convergence evidence across native, SciML, and
   custom realizations with declared tolerances and negative capability tests.

Phase 16.G and 16.H MUST NOT begin until 16.F0 passes and P16-F01 through P16-F03 are qualified.
Phase 16.C hardware closure remains independently open and is still required by Phase 16.I.

## Disposition

The specification and control plane should now describe the existing 16.F code as an unqualified
prototype and make the repair above the immediate implementation target. The prototype commit is
retained for traceability; it is not evidence and must not be used to advance ledger status.
