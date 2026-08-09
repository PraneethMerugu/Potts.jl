# Symbolic Potts V1 Native Moving-Field Research and Amendment Gate

Date: 2026-08-09

Status: Accepted

Phase: `G5H-R`, after cleared G5H/R2H-C and before G6

## Authority and purpose

This gate is accepted by
[Decision 0045](decisions/0045-native-moving-field-research-gate.md). It is the sole authority for
researching whether staged, moving CPM occupancy should become a typed native input to a
MethodOfLines-discretized ModelingToolkit field component and, only after committee review, for
amending G5H to reflect the supported conclusion.

The gate begins from uncertainty. It does not assume that an MTK parameter array, scalarized
parameter block, registered forcing function, callback, mutable closure, or persistent integrator
is acceptable. It must compare the viable representations through public upstream APIs and exact
measurements.

The gate may add isolated research code under `design/`, `benchmark/`, or a dedicated test fixture.
It must not modify production source, exports, stable documentation claims, passed capability rows,
or the Merks implementation until the committee has reviewed the complete research packet and an
amendment has been accepted.

## Candidate boundary under investigation

The candidate, not-yet-accepted lifecycle is:

```text
PDESystem + fixed lattice/grid contract
    -> MethodOfLines symbolic discretization once
    -> ModelingToolkit structural compilation once
    -> numerical problem and cached input-index plan once
    -> persistent SciML integrator

each coupled boundary:
    staged post-MCS ownership
    -> typed occupancy projection into an owned, preallocated buffer
    -> cached native parameter/input update
    -> derivative-discontinuity bookkeeping
    -> advance the native field to the next physical boundary
    -> atomic CPM + field publication
```

The central hypothesis is that cell movement changes numerical input values rather than symbolic
structure. The research must falsify as well as support that hypothesis.

## Mandatory research questions

The packet must resolve all of the following.

### RQ1 — Public upstream representation

- Which public MethodOfLines and ModelingToolkit APIs can represent a fixed-grid spatial input
  whose values change at coupled time boundaries?
- Is the sound representation an array parameter, scalarized parameter block, retained algebraic
  field, registered function with an owned buffer, post-discretization transformation, or another
  public mechanism?
- Does the representation survive `symbolic_discretize`, `mtkcompile`, standard problem
  construction, symbolic indexing, remake, serialization boundaries, and package-extension load
  order without private-field dependence?
- Which exact upstream versions were tested, and does package compat need to narrow?

### RQ2 — Compile and initialization lifecycle

- Precisely which operations occur at component construction, structural scheduling, problem
  materialization, first `init`, and each completed-MCS continuation?
- Can the input setter/index plan and generated numerical function be cached while only values
  change?
- Can one persistent integrator advance across successive physical intervals without rebuilding an
  `ODEProblem` or rerunning solver initialization?
- Which structural changes really require a new artifact: grid shape, boundary equations, scalar
  type, backend, system topology, or component schema?

The evidence must instrument call counts. A timing observation alone cannot prove that symbolic
work is absent from the steady-state path.

### RQ3 — Coupling and numerical semantics

- Which occupancy snapshot is visible to secretion under `CPMThenComponents`?
- Is occupancy held piecewise constant over one physical component interval, and how are cadence,
  subcycling, adaptive internal timesteps, and solver stops defined?
- What bookkeeping is required when the input discontinuously changes?
- How do boundary conditions, cell-kind selection, secretion strength, lattice-to-PDE coordinates,
  multiple cells, empty occupancy, and cell overlap impossibility map into the field input?
- Does the replacement preserve the intended Merks mechanism rather than only its current output
  assertions?

### RQ4 — Ownership, atomicity, and replay

- Does MTK/MOL own the PDE, discretization, internal equations, and internal connections while
  PottsToolkit owns only typed projection, scheduling, and publication?
- Can candidate field advancement fail without mutating the last settled public CPM, component,
  parameter, observation, or checkpoint state?
- Is the occupancy field derived from staged canonical CPM ownership, or does it become a second
  checkpoint authority?
- What exact state, parameters, solver state, input identity, and upstream identity are required for
  deterministic continuation?
- How do remake, checkpoint/restore, replica/repeat identity, callbacks, termination, and component
  failure behave?

Mutable globals, process-wide registries, and unowned closure state are inadmissible unless the
committee accepts a demonstrated thread-safe, replay-safe ownership protocol.

### RQ5 — Performance and scaling

Measure separately:

- one-time MOL discretization;
- structural compilation and first Julia compilation;
- problem and integrator initialization;
- occupancy projection;
- parameter/input update;
- one native field interval;
- checkpoint and restore; and
- steady-state allocations.

Compare at least the current `DiscreteFieldEuler`, the current output-only MOL path, and every
serious native-input candidate on multiple lattice sizes. Report compile latency and runtime
throughput separately. The accepted route must not create one new symbolic compilation or solver
initialization per MCS.

### RQ6 — CPU, accelerator, and ensemble boundaries

- Qualify the serial CPU feasibility independently on the target Mac.
- Determine whether generated MOL code, input storage, parameter updates, solver choice, and field
  publication can execute on Metal without host fallback or hidden transfers.
- Record GPU as supported, experimental, deferred, or unsupported from real-device evidence; CPU
  success cannot promote it.
- Prove that independent SciML trajectories own distinct input buffers and integrators under serial,
  threaded, and distributed ensemble execution.
- Determine whether Dagger changes only coarse orchestration or materially affects this component
  boundary.

### RQ7 — Scope and consolidation impact

- What is the smallest public API and internal implementation that supports the accepted semantics?
- Which existing generic native runtime mechanisms should be reused, replaced, or specialized?
- Would a persistent-integrator improvement apply to all native ODE components or only fixed-grid
  fields, and what evidence would each choice reopen?
- Which custom field code becomes removable, and which bounded discrete-field capability remains
  independently useful?
- Which G5H clauses, capability rows, preservation rows, tests, docs, examples, and review
  clearances would change?

## Required alternatives

The packet must compare, rather than merely mention:

1. the current `DiscreteFieldEuler` implementation;
2. a compile-once semidiscrete parameter block updated at MCS boundaries;
3. a compile-once owned array/buffer parameter or public equivalent;
4. a time-varying forcing function or callback representation, if upstream permits it; and
5. retaining the current output-only MethodOfLines boundary.

An alternative may be rejected early only with a public-API proof, a minimal executable failure, or
a direct violation of an accepted ownership/replay invariant.

## Research evidence packet

Before committee review, freeze one exact candidate containing:

- a primary-source research report with links to upstream documentation, source, issues, or papers;
- minimal executable probes for each viable representation;
- an instrumented compile/initialize/update trace;
- CPU measurements on the target Mac and an allocation profile;
- real-Metal evidence or an explicit evidence-backed deferral;
- moving-source scientific witnesses, including source translation and disappearance;
- staged-order, failure-atomicity, checkpoint/restart, and ensemble-isolation probes;
- a public/private upstream API audit;
- a package compat and load-order disposition;
- a risk register with unresolved upstream dependencies;
- a clause-level candidate impact map for G5H; and
- a smallest-coherent implementation estimate, including production, tests, documentation, and
  removal work.

Every result names the exact repository commit, Julia version, package resolution, hardware,
command, and artifact location. Generated logs are evidence, not specification prose.

## Committee review

### Required roles

Four independent reviewers cover non-interchangeable concerns:

1. **MTK/MOL ecosystem reviewer** — public API correctness, symbolic ownership, discretization,
   compilation, initialization, and upstream compatibility.
2. **Runtime and replay reviewer** — split order, persistent-integrator lifecycle, atomicity,
   checkpointing, failure, callbacks, and ensemble isolation.
3. **Performance and backend reviewer** — instrumentation, compilation frequency, allocations,
   scaling, Metal/device honesty, transfers, and no-fallback evidence.
4. **Scientific authoring reviewer** — Merks mechanism fidelity, grid and boundary meaning,
   model readability, generality beyond Merks, and removal of unnecessary custom components.

The research author and implementation author are non-voting witnesses. All four roles must file an
independent report from a fresh context before reading the committee synthesis. One person cannot
fill multiple voting roles for the same review.

### Review questions and verdict

Each reviewer must state:

- whether every question in their role is resolved;
- P0--P3 findings under the existing G5H severity definitions;
- which candidate representation, if any, is acceptable;
- exact limitations and rejected claims;
- the earliest G5H gate that would reopen; and
- required implementation and rereview evidence.

The committee then publishes one of four verdicts:

- `ACCEPT_BOUNDED` — one exact native-input design is ready for a bounded G5H amendment;
- `ACCEPT_ALTERNATIVE` — another researched design is ready for amendment;
- `DEFER` — the design is promising but an identified upstream or evidence prerequisite is absent;
- `RETAIN_CURRENT` — the current G5H field disposition remains the sound boundary.

Committee review completes only with all four reports, a disposition for every P0--P2 finding, and
one synthesis that records agreement and dissent. `ACCEPT_BOUNDED` or `ACCEPT_ALTERNATIVE` requires
zero unresolved P0/P1 findings. Voting does not convert missing evidence into support; the owner
resolves any remaining policy choice explicitly.

## Post-review G5H amendment

No amendment is drafted as accepted authority before the committee verdict. Afterward:

1. `DEFER` records the exact prerequisite and keeps G6 closed until the owner either closes the
   research gate with the current boundary or commissions the missing evidence.
2. `RETAIN_CURRENT` produces a no-change disposition and an owner decision on whether G6 may again
   approach send-off.
3. An acceptance verdict produces one bounded amendment containing:
   - exact replacement text for affected G5H clauses;
   - an earliest-gate and downstream-review reopening map;
   - capability rows that become stale, remain valid, or require new evidence;
   - PR13, PR14, PR15, PR27, and any other preservation-row changes;
   - the minimal public API delta and removal inventory;
   - an ordered implementation and qualification matrix;
   - CPU and GPU promotion criteria stated separately; and
   - the new G6 entry condition.
4. The committee performs a fidelity check: the amendment must not claim more than the reviewed
   evidence or omit a recorded limitation or dissent.
5. The owner accepts, narrows, defers, or rejects the amendment. Only an accepted amendment becomes
   implementation authority.

Historical G5H and R2H-C records are never edited to imply they reviewed the new design. The living
control record marks affected gates `reopened` and links both the old exact evidence and the new
authority.

## Exit and failure routing

G5H-R exits only when one of these terminal records exists:

- accepted no-change disposition after `RETAIN_CURRENT`;
- accepted bounded amendment plus an exact reopened-gate implementation sequence; or
- accepted deferral that names its prerequisite and explicitly decides whether work returns to the
  current G6 boundary.

Research failure returns to the earliest incomplete research question. Committee P0/P1 findings
return to the research packet. Amendment-fidelity findings return only to the amendment draft.
Production implementation, Merks migration, capability promotion, or deletion discovered before an
accepted amendment is out of order and must be reverted or quarantined as a non-authorizing probe.

An accepted implementation amendment must finish every reopened gate and review before G6. G5H-R
itself never authorizes G6.
