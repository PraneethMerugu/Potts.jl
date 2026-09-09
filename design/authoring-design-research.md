# Authoring design research and decisions

Status: Design rationale, not an implementation or qualification report.
Reviewed 2026-09-08 against official documentation and the sibling source baseline
recorded in the [PR plan](authoring-and-model-ecosystem-plan.md).

The [ideal API vision](../spec/ideal_api_vision.md) states the desired contracts;
the plan assigns their implementation. This note records why those requirements
are practical and where familiar syntax can conceal a real scientific problem.
Upstream `stable` documentation changes: implementation PRs must verify the
public interfaces against the actual supported dependency environment. These
sources do not establish support in today's Potts packages.

## 1. Concise scope does not require a second model framework

Julia's manual recommends keeping macro-generated code small and putting most
functionality in ordinary helpers; it warns that macro scope is easy to get
wrong. [Julia metaprogramming](https://docs.julialang.org/en/v1/manual/metaprogramming/)

JuMP's larger-model tutorial demonstrates ordinary functions and dispatch for
building reusable models, and recommends adding function barriers where
benchmarks justify them. This is a useful design precedent, not a proposal to
depend on JuMP or import its model registry.
[JuMP model design patterns](https://jump.dev/JuMP.jl/stable/tutorials/getting_started/design_patterns_for_larger_models/)

**Our decision:** source-capturing scoped convenience may remove repeated
domain/anchor/name/enrollment work, but lowers immediately to existing Potts
declarations. Keep programmatic construction first-class. No ambient builder,
permanent second graph, runtime authoring interpreter or duplicate executor.

Current foundation:
[statement capture](../../PottsEcosystem/Potts.jl/src/statements/statement_set.jl)
already produces `StatementSet` with source provenance. Its present per-entry
capture is not yet the proposed complete scoped-authoring facility.

**Test:** a helper in another module, nested scopes, a factory loop, two
independent instances, construction in concurrent Julia tasks, and equivalent
constructor/scoped behavior. Check source errors and scientific results, not a
frozen macro expansion. Choose syntax with these consumers in P07/P11.

## 2. Symbol scope is a real ownership concern

MTK documents local, parent and global symbolic scope. Naively passing a parent
variable into a child can namespace it as though the child owned it. Scope
adjustments apply to individual variables, and public utilities support mapping
them through expressions. Its `@named` handling provides useful convenience for
symbolic component arguments.
[MTK symbolic scope](https://docs.sciml.ai/ModelingToolkit/stable/API/model_building/#Scoping-of-variables)

**Our decision:** scope distinguishes owned declarations from imported
references. A shared field/parameter stays shared; independent component state
stays independent. Source qualification is the sole authority. Do not expose
repeated `ParentScope` transformations in ordinary Potts tutorials or deduplicate
scientific state by matching strings/default values.

**Important difference:** current Potts `extend` rejects duplicate declaration
IDs and conflicting initial conditions, whereas MTK documents extending-system
precedence for duplicate defaults. Potts replacement must be explicit, with
dangling-reference and writer checks, rather than assuming identical APIs imply
identical override behavior.
[Potts systems](../../PottsEcosystem/Potts.jl/src/systems.jl),
[MTK composition utilities](https://docs.sciml.ai/ModelingToolkit/stable/API/model_building/#System-composition-utilities)

**Test:** one declared parameter used by a Potts energy and two native systems;
one override affects all uses. Two separately owned same-spelled parameters
remain distinct. A typo does not become a parameter. Parameter discovery also
visits defaults, initializers, event payloads and native bindings.

## 3. Most mathematical helpers should not need registration

Symbolics distinguishes tracing ordinary functions into existing symbolic
operations from registering an opaque primitive. Registration limits symbolic
transformations; array primitives additionally need shape information.
[Symbolics tracing and registration](https://docs.sciml.ai/Symbolics/stable/manual/functions/)

**Our decision:** support ordinary composed mathematics first. Use the existing
LocalMath/Potts public operation boundary for a genuinely opaque or contextual
operation, not a second function-registration system. Numerically sensitive
algorithms may need opacity; derivatives, unit rules, incremental laws and GPU
support are separate obligations where the consumer requires them.

Construction-time Julia helpers are not the same as retained device callables.
A mutable array, RNG, state descriptor or live integrator captured invisibly by
a kernel function cannot bypass dependency analysis. Immutable numeric captures
have documented snapshot behavior. Current relevant restrictions are described
in [LocalMath troubleshooting](../../PottsEcosystem/LocalMath.jl/docs/src/learn/localmath-troubleshooting.md).

**Test:** traced versus concrete math, structured inputs, typed empty reductions,
rejected mutable captures with useful errors, and actual supported device use.

## 4. Native outputs are not necessarily settable unknowns

MTK's IO documentation describes selected inputs/outputs for numerical interface
generation; marking a variable as input/output alone does not construct a
coupling interface. Native initialization has its own system of equations and
constraints.
[MTK IO](https://docs.sciml.ai/ModelingToolkit/stable/basics/InputOutput/),
[MTK initialization](https://docs.sciml.ai/ModelingToolkit/stable/tutorials/initialization/)

**Our inference and decision:** if an observed output is `y = x^2`, a published
value of `y` does not uniquely identify the sign of `x`. Therefore native
reinitialization cannot generally assign backwards from arbitrary mapped
outputs. Infer routine initialization for a proven unknown mapping; otherwise
use a declared native initialization system or reject the unsupported mapping.

Potts already owns selected native IO and compilation in its
[MTK extension](../../PottsEcosystem/Potts.jl/ext/PottsModelingToolkitExt.jl).
Extend that authority to admitted expression/structured inputs and component
references; do not cache guessed native indexes before simplification or wrap
the equations in a Potts surrogate.

**Test:** an actual unknown output, an eliminated algebraic output, an
under-specified inverse initialization, division and native failure rollback.
The long example maps actual `r`, `z`, `d` unknowns; its convenience is not an
arbitrary observed-output inversion guarantee.

## 5. Reuse symbolic indexing across consumers

SymbolicIndexingInterface separates author-facing symbolic access from the
problem/solution structure that resolves that access.
[SymbolicIndexingInterface](https://docs.sciml.ai/SymbolicIndexingInterface/stable/)

**Our decision:** strengthen the existing
[Potts symbolic indexing](../../PottsEcosystem/Potts.jl/src/runtime/symbolic_indexing.jl)
for quantity references, native binding and retained observations. Do not add an
independent string-name lookup layer for plotting. Ambiguous short names fail.
Rebuild accessors when source structure changes; do not persist incidental
native or cell slot indices as scientific identity.

**Test:** duplicate local names in separate components, direct reference access,
missing saved quantities, structural replacement, and generation-safe cell
results after retirement and slot reuse.

## 6. Units need normalization, not only metadata

MTK's current validation documentation requires equal-valued units in relevant
sums/equations, not only dimensionally consistent scales. It also describes
restrictions on unitful literals inside registered functions and certain unit
forms. These are implementation constraints, not grounds to advertise arbitrary
automatic conversion.
[MTK validation and units](https://docs.sciml.ai/ModelingToolkit/stable/basics/Validation/)

**Our decision:** the author chooses physical/reference scales; validate and
normalize admitted quantities/ports consistently using existing symbolic/unit
facilities. Start with scalar and homogeneous-unit fixed-shape values. Numeric
time per MCS must agree with native time units. Keep affine and heterogeneous-unit
cases explicitly unsupported until their conversions are demonstrated.

**Test:** amount per site versus concentration, spacing/volume conversion,
milliseconds versus seconds across a native boundary, a scaled-unit mismatch,
and an explicitly nondimensional version with matching scientific results.

## 7. Held measurements are historical state

This is a deduction from the model's declared time semantics, not a claim that
an upstream library already implements Potts sampling or restart.

A quantity sampled at MCS 5 and held until MCS 10 retains its MCS-5 value at MCS
7. Reconstructing it from MCS-7 geometry on restore changes the model. A live
cache, in contrast, is reconstructible from the current authoritative state.

**Our decision:** persist held values and cadence phase. Specify whether a
lifecycle refresh preserves a global clock or resets a cell-local clock. The
tissue example uses immediate daughter refresh without moving the global ticks.
Do not use solution save times as runtime history or pretend each proposal has
a fresh hypothetical sample.

**Test:** off-tick checkpoint after a source mutation, off-tick division, and
late failure after a due refresh. Check both the value and next refresh behavior.

## 8. Local coloring does not prove independent linked energies

This is a source-informed scientific deduction. Current admitted checkerboard
execution claims the two copy owners; qualified tracker reads have corresponding
narrow ownership limits. The generalized linked-energy API needs more than that
existing admission contract.
[Checkerboard claims](../../PottsEcosystem/CorePotts.jl/src/execution/checkerboard_program_declaration.jl),
[checkerboard requirements](../../PottsEcosystem/CorePotts.jl/src/execution/checkerboard_requirements.jl)

For a one-dimensional illustrative spring, let `H = k/2 * (x_b - x_a - l)^2`.
Two individually proposed endpoint changes `a`, `b` have a joint energy change
differing from the sum of their separate snapshot changes by `-k*a*b`.
Disjoint local copy owners therefore do not prove independent acceptance.

**Our decision:** P10 includes read/write conflict closure alongside affected
energy anchors. Prove adequate arbitration or reject the combination. Do not
silently choose a synchronous approximation or infer whole-model GPU support
from backend availability. This is extra work for the proposed generalized API,
not a finding that today's narrower admitted path is incorrect.

**Test:** simultaneous moves at opposite endpoints, shared mutable aggregate
reads, and a sequential scientific oracle on tiny geometry.

## 9. Optional packages and reproducibility serve different purposes

Julia package extensions support code loaded when specified dependencies are
available; weak dependencies need not be mandatory dependencies of basic use.
[Pkg extensions](https://pkgdocs.julialang.org/v1/creating-packages/#Conditional-loading-of-code-in-packages-(Extensions))

**Our decision:** basic PottsModels tutorials remain CPU-first and light. Native,
plotting and device families use actual optional integrations. The ordinary dev
environment uses explicit sibling development dependencies and broad compatible
versions. Exact replay is a separate, explicitly pinned environment claim.
The plan details existing CI reuse and ownership-based fan-out; no new capability
registry or custom qualification platform is needed.

## Choices to settle with implementation consumers

The requirements above are firm design targets, but these details remain open:

- The smallest scoped syntax over current source capture, demonstrated by a
  small model and component extraction; do not choose by line count alone.
- The default floating realization interface and explicit override precedence,
  preserving integer/count semantics and fixed schema checks.
- Which native initialization mappings/public upstream interfaces work across
  the supported dependency range, including observed outputs.
- Which linked-energy conflict bounds/arbitration are practical on each actual
  backend, measured without silently weakening the scientific algorithm.
- Reference-scale normalization and supported structured unit cases.

Each is assigned to ordinary PR work with concrete tests, not a new committee,
approval gate, prototype runtime, or excuse to defer all ergonomics to the end.
