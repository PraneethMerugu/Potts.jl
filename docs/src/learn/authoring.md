# [Author and compose](@id author-and-compose)

A model is a `PottsSystem` containing typed statements. States, parameters,
spatial relations, schedules, and observations remain symbolic until runtime.
`complete` closes declarations and reports source-located errors;
`mtkcompile` performs structural scheduling and is idempotent.

```@example authoring
using Potts
using Symbolics
using ModelingToolkitBase: @parameters

@parameters target = 4.0 strength = 1.0 temperature = 2.0
cell = CellKind(:cell; extinction=RetireAtZero())
medium = MediumKind(:medium)

source = PottsSystem(
    name=:minimal,
    statements=(@statements begin
        Lattice((4, 4); boundary=Periodic())
        cell
        medium
        Volume(cell; target, strength)
        Protocol(Sweep(; temperature); name=:main)
        Observation(:occupied, occupancy(cell, :lattice))
    end),
    parameters=[target, strength, temperature],
)
completed = complete(source)
scheduled = mtkcompile(completed)

(
    iscomplete(completed),
    is_scheduled(scheduled),
    length(inspect(scheduled, Statements())),
    only(inspect(scheduled, Observations())).name,
)
```

Use `@named` when a parent expression should supply the component name. Use
`compose` for hierarchy, `extend` for explicit inherited declarations, and
`flatten` only when a downstream operation genuinely needs a flat namespace.
Namespacing is structural identity, not display metadata.

For a factory that already returns a `StatementSet`, pass that set positionally:
`PottsSystem(declarations; name=:model)`. This collects variables from owned
state declarations and parameters carrying MTK parameter metadata from statement
payloads, initial conditions, equations, events and parameter defaults. It then
constructs the same ordinary `PottsSystem` as the keyword-only constructor.
Supply `unknowns` or `parameters` to retain additional unused declarations;
explicit entries come first. Imported aliases are not newly owned parameters,
and an assignment target does not implicitly declare state. Child components
and native systems retain their own inventories.

The keyword-only `PottsSystem(; statements=declarations, ...)` form uses the
explicit `unknowns` and `parameters` inventories. Neither form inspects arbitrary
Julia local variables: unreferenced parameter bindings must still be supplied
explicitly. This convenience does not introduce an ambient model builder.

To enroll declarations made inside the block, use the explicit constructor form:

```@example lexical-enrollment
using Potts, ModelingToolkitBase
source = @statements PottsSystem(; name=:reservoir) begin
    @parameters rate=0.25 unused_parameter=2.0
    @variables amount
    ModelState(amount; initial=8.0)
    Synchronous(:deplete, Assign(amount, amount * (1 - rate)))
end
length(parameters(source)) # retains unused_parameter as well as rate
```

Top-level `@parameters` and `@variables` calls, including their qualified
ModelingToolkitBase/Symbolics forms, evaluate normally and contribute their whole
symbolic results. A symbolic declaration does not allocate physical state: that
still requires `ModelState`, `CellState`, `SiteState`, or another state declaration.
The block runs before constructor keywords, so keywords can refer to its bindings;
each declaration/default and keyword expression is evaluated once. Explicit
inventories come first, followed by captured declarations. Automatically captured
import aliases and independent variables are excluded from owned inventories.

Nested `begin` blocks, `if`/`elseif` branches, and ordinary Julia `for` and
`while` loops enroll the declarations they actually execute, in execution order.
Conditions and iterators run normally, including `break` and `continue`; an
unselected branch or empty loop contributes nothing. Constructor-form symbolic
declarations inside those bodies also join the ordinary inventories. Use finite
factory loops: these are Julia construction-time operations, not simulation
schedulers. Loop bindings retain normal Julia scope.

For example, one finite factory loop can declare a pair of reservoirs without
maintaining a second symbolic inventory:

```@example declaration-loops
using Potts, Symbolics
source = @statements PottsSystem(; name=:reservoir_pair) begin
    @variables stored released
    for variable in (stored, released)
        ModelState(variable; initial=0.0)
    end
end
@assert length(statements(source)) == 2
nothing # hide
```

Every other entry explicitly enrolls a statement or `StatementSet`.
An assignment such as `state = ModelState(amount)` both binds and enrolls it;
using `state` inside a later expression is a reference, but writing `state` again
as a top-level entry attempts a second enrollment and is rejected. Equal statement
values are never silently deduplicated. Ordinary factory helpers can return a
`StatementSet` to splice; the macro does not inspect function definitions,
discover declarations hidden in helper bodies, or treat arbitrary numeric
assignments as declarations. Plain `@statements begin ...
end` continues to return only a `StatementSet`.

`examples/compartment_exchange.jl` is a complete factory using this
explicit-constructor `@statements` form, with no separate state or parameter tuple. Its
two simultaneous assignments conserve the total reservoir amount:

```@example assembled-exchange
using Potts
include(joinpath(pkgdir(Potts), "examples", "compartment_exchange.jl"))
solution = solve(CompartmentExchangeExample.exchange_problem(), SequentialCPM(); scalar_type=Float32)
(last(solution)[:stored], last(solution)[:released])
```

Symbolic arrays remain whole symbolic values during component qualification;
ordinary Julia containers still have their symbolic elements traversed.

## Simultaneous assignments

Pass multiple effects to `Synchronous` to read one boundary-entry snapshot:

```julia
@variables left right
ModelState(left; initial=2.0)
ModelState(right; initial=7.0)
Synchronous(:exchange, Assign(left, right), Assign(right, left))
```

Include these declarations in the model's `StatementSet`. The exchange swaps
the two values; the second assignment does not read the first assignment's
new value. Each target must have one synchronous writer, including within a
single process. All assignments in this process must share an iteration domain:
model assignments execute once, site assignments execute per site, and cell
assignments execute once per eligible finite cell. Use
separate processes for different domains. This does not make source order an
implicit sequential update policy.

Cell assignments name their finite-kind domain explicitly:

```julia
@variables store
cell = CellKind(:cell; extinction=RetireAtZero())
CellState(store; initial=1.0, retirement=RetireTo(0.0))
Synchronous(:accumulate, Assign(store, store + 1); domain=cells(cell))
```

Cell size does not multiply the update. Inactive slots, medium, and cells of
other kinds are not selected. Cell processes can read cell state, model state,
and parameters. Each model operand uses its model-owned value rather than a cell
index; model and cell updates in the same boundary read the same entry snapshot.
Site-state reads require an explicit spatial binding and are not supported in a
cell process. Effects within one process must still share a target domain.

Lifecycle state policies such as `RetireTo` and `ResetTo` also accept immutable
fixed-array and named-product literals. They must match the target state's
logical shape, field names, and reference dimensions. Floating leaves use the
selected execution precision; declared Boolean and integer leaves retain their
types. Mutable arrays and nonfinite literal values are rejected before execution.

## Retained samples and feedback

`HistoryState(memory; of=signal, depth=3, cadence=Every(2))` retains samples of
the exact declared `signal` owner. The source supplies the sample's logical
type, shape, dimensions, and model/cell/site domain. Retention adds a dense
storage axis, not fields of one large tuple or static array. Cell storage
capacity remains distinct from the number of active cell identities.

`lag(memory, 0)` reads the newest retained sample; `lag(memory, 1)` reads the
previous sample. Indices must be literal nonnegative integers less than the
declared depth; Boolean indices are rejected. There is no interpolation and a
lagged read does not read the source's current live value.

With `EveryMCS()` or `Every(n)`, initialization does not implicitly capture a
sample. The declared prehistory remains until the first due positive completed
MCS. Ordinary simultaneous assignments read boundary-entry samples; sampling
then captures their updated source values at a due boundary. `initial=nothing`
or numeric zero fills prehistory with the logical zero of the source type and
dimensions. Explicit sample values must match that type and reference units.

`AtMCS(0)` explicitly captures once after fresh native and callback
initialization, before `save_start`. Only the newest slot is replaced; older
supplied prehistory remains intact. It does not execute ordinary updates at
zero. Restoring a checkpoint, including a checkpoint at zero, does not capture
again, even when the checkpoint's live source differs from its held history.
This does not persist callback identity or state: integrators with outer
callbacks still cannot create checkpoints, and restore retains the existing
composed-runtime compatibility requirements.

Typed symbolic history variables preserve structured samples. For a vector,
declare the symbolic shape before constructing indexed feedback:

```julia
@variables position[1:2] position_history[1:2] response[1:2]
ModelState(position; initial=SVector(1.0, 2.0))
HistoryState(position_history; of=position, depth=3)
ModelState(response; initial=SVector(0.0, 0.0))
Synchronous(:respond,
    Assign(response, SVector(lag(position_history, 0)[2],
                             -lag(position_history, 0)[1])))
```

For a named product, whole-value assignment and selected-field arithmetic share
one sampled owner:

```julia
@variables payload::NamedTuple{(:amount, :enabled), Tuple{Float64, Bool}}
@variables memory::NamedTuple{(:amount, :enabled), Tuple{Float64, Bool}}
@variables copied::NamedTuple{(:amount, :enabled), Tuple{Float64, Bool}}
@variables total
ModelState(payload; initial=(amount=6.0u"m", enabled=true))
history = HistoryState(memory; of=payload, depth=257, cadence=Every(2))
ModelState(copied; initial=(amount=0.0u"m", enabled=false))
ModelState(total; initial=0.0u"m")
Synchronous(:respond,
    Assign(copied, lag(memory, 0)),
    Assign(total, lag(history.amount, 0) + lag(history.amount, 1)))
```

These snippets use `StaticArrays`, `Symbolics`, and, for quantities,
`DynamicQuantities`. Include the declarations in the model's `StatementSet`.
The product-field spelling is `lag(history.amount, n)`, where `history` is the
declaration, not `lag(memory, n).amount`. The whole-product result remains one
symbolic value. Component namespacing preserves the exact `of` owner and its
units; for example, completing the enclosing model with
`ReferenceUnits(length=2.0u"m")` represents the sampled `6.0u"m"` amount as `3.0`.

## Explicit imports and structural replacement

An ordinary component constructor can consume another component's declared scalar
parameter or symbolic state without declaring a second owner. Bind its local
symbol with `imports=(local_input => ComponentReference(path, declaration),)`.
Paths are relative to the enclosing model root; `()` selects the root. The alias
must not also occur in the component's `parameters`, `unknowns`, or state
declarations. Inputs and outputs still describe symbolic IO roles, not ownership.

A statement reference must match the declaration at that owner, including its
scientific data; another state with the same name and a different initial value
does not bind. Authored file/line information is not scientific identity.
Parameter references use their symbolic identity at the explicitly selected owner.

```@example component_replacement
using Potts
include(joinpath(dirname(dirname(dirname(@__DIR__))), "examples", "component_replacement.jl"))
shared = ComponentReplacementExample.shared_input_model()
changed = ComponentReplacementExample.replaced_input_model()
(
    length(inspect(mtkcompile(shared.source), StateSchema()).states),
    length(inspect(mtkcompile(changed.replaced), StateSchema()).states),
)
```

The example's `accumulator` factory returns ordinary source and its owned state
declaration. Two instances share one root-owned forcing parameter. Its replacement
example changes one accumulator and reconnects a reader explicitly:

```julia
updated = replace_component(source, (:left,) => replacement.source;
    reconnect=(old_output => ComponentReference((:left,), replacement.state),))
```

For explicit physical reference scales, pass `reference_units=ReferenceUnits(...)`
to `replace_component`; both the original and rebuilt component contracts are
validated with that choice. The returned value is still editable source, not a
completed system retaining compiler options. Pass the same reference option when
subsequently calling `complete` on it. The default remains declared-reference
inference.

Every surviving import of an output from the removed subtree needs a reconnection,
even when the replacement uses the same names. Unrelated components and external
input owners remain present. Missing owners, incompatible declarations, duplicate
synchronous writers, unused reconnections, and implicit cross-component connections
are rejected. The result is new, validated, incomplete source; neither the original
source nor an existing simulation is mutated. Use numerical `remake` for parameter
changes, not structural replacement.

Native ports use the same source imports. Supply a symbolic `ModelState` or
`CellState` declaration as the port's local alias, but do not include that alias in
the component's owned statements or unknowns. Its variable binds to the actual
state owner; its local initial value does not initialize or copy the shared state.
The endpoint kind must match the owner's declaration kind. Native inputs cannot
import a parameter in place of their required state endpoint.

```@example native_component_replacement
using Potts
include(joinpath(dirname(dirname(dirname(@__DIR__))), "examples", "native_component_replacement.jl"))
native_example = NativeComponentReplacementExample.replaced_input_model()
inspect(mtkcompile(native_example.replaced), ExternalIO())
```

Here two ODE components share one held Potts state, and a third ODE reads one
component's published output. Replacement removes that component's owned ODE and
output declaration, preserves the shared input, and explicitly reconnects the
reader. Original MTK systems and native symbols retain their identity; only Potts
port bindings are rebuilt. The existing native initialization, solver profiles,
sampled inputs, cadence, and atomic publication rules are unchanged. Structural
replacement starts new source, not a continuation or transfer of existing native
solver state. Replace the containing `PottsSystem` subtree, not a bare
`NativeComponent` declaration.

Completion preserves context: a child obtained from `get_systems(complete(parent))`
retains the enclosing root's qualified identities, including its own state namespace.
Completing the original child source independently uses that child's own root instead.
`inspect(child, ExternalIO())` shows native endpoints and their actual owners even
when those owners are external to the child. Such a child cannot be scheduled alone:
compile the containing model with all endpoint owners. A closed child remains
executable in its retained namespace.
Completed `parameters`, `unknowns`, `inputs`, `outputs`, `equations`, `observed`,
and `initial_conditions` queries use those same qualified symbols. Their parent
queries do not add another namespace. Low-level MTK `get_*` accessors remain local
source-field queries.

This source-binding surface currently supports scalar symbolic parameters and states.
Structured references and scoped declaration syntax require the structured-authoring
extension. General native equation substitution is separate from port reconnection.
Generic symbolic substitution of a source with imports is also rejected until its
binding updates have explicit semantics; use the supported replacement operation.
Backend support is determined by the resulting complete model.

Keep declarations in `@statements` to retain their authored file and line through
composition. Validation errors show the qualified statement, failing expression,
and available remedies. Programmatically built statements without source metadata
still report their semantic identity; Potts does not invent a source location.

The stable statement families are:

- domains, cell/media kinds, relations, and stored site/cell/medium/model/field/history state;
- Hamiltonian terms, drives, constraints, modifiers, synchronous and accepted-copy effects;
- lifecycle and relationship processes with explicit policies;
- observations and protocols; and
- native component declarations with typed inputs and outputs.

Inspection (`Statements`, `Variables`, `Effects`, `Schedule`, `Capabilities`,
`StateSchema`, `Observations`, `ReplayContract`, and `LifecyclePlans`) reads the
same completed authority used by lowering. It does not reconstruct a second
model description.

## Tracker-backed values and relation gathers

Derived cell quantities remain ordinary symbolic values. Scalar terms read
them directly:

```julia
cell = CellBinding(:cell)
volume_penalty = HamiltonianTerm(
    :volume_penalty;
    domain=cells(kind),
    anchor=cell,
    expression=strength * (cell_volume(cell) - target)^2,
)
```

An ordinary Julia function can fold the same quantity over a declared finite
spatial relation:

```@example bounded_tracker_authoring
using Potts, LocalMath

kind = CellKind(:cell; extinction=RetireAtZero())
medium = MediumKind(:medium)
proposal = ProposalContext(:copy)

neighbor_mean(values) = LocalMath.fold(values;
    map=identity,
    combine=+,
    init=0.0,
    finish=(sum, count) -> sum / count,
    domain = >=(0),
    invalid=:reject,
    empty=0.0,
    order=:canonical,
)

source = PottsSystem(
    name=:tracker_authoring,
    statements=StatementSet((
        Lattice((4, 4); relations=(
            contact=VonNeumann(), proposal=VonNeumann())),
        kind,
        medium,
        ProposalDrive(
            :neighbor_volume,
            neighbor_mean(gather(
                cell_volume, :contact; at=proposal.target_site)),
        ),
        Protocol(Sweep(); name=:main),
    )),
)

is_scheduled(mtkcompile(source))
```

`gather` follows canonical relation-lane order. Missing boundary lanes
and medium endpoints do not participate, while two lanes reaching the same
finite owner contribute twice. It does not imply a distinct-neighbor-cell
reduction. The Potts compiler discovers and maintains tracker storage; authors
never bind tracker arrays or expose them to LocalMath. Freely mutable per-cell
quantities are `CellState` values rather than derived trackers.
Extension operations must explicitly declare that they are a direct scalar
projection with
`Potts.is_direct_scalar_tracker_projection(::typeof(operation)) = true`;
structured tracker transformations are not silently treated as scalar storage.

Tracker-backed bounded folds are proposal-snapshot inputs, so use them in a
`ProposalDrive`, `ProposalConstraint`, or `ProposalModifier`. A site-domain
Hamiltonian that references a derived owner tracker throughout a neighborhood
does not have a compiler-proven bounded affected-anchor set and is rejected.
Scalar cell-domain Hamiltonians such as the volume penalty above retain exact
before/after tracker overlays.

## Custom bounded Hamiltonian terms

A model-wide state can supply a shared energy coefficient without allocating a
copy at every site:

```julia
@variables weight
weight_state = ModelState(weight; initial=2.0)
site = SiteBinding(:energy_site)
term = HamiltonianTerm(:occupied_energy;
    domain=sites(:lattice), anchor=site,
    expression=weight * occupancy(cell, site))
```

Include `weight_state` and `term` in the system's statements and `weight` in its
unknowns. The coefficient is one model-owned value; `occupancy` remains local to
the energy anchor. For this term, adding an occupied site changes energy by
`weight`. Ordinary tests exercise positive and negative coefficients through
actual extension acceptance on both CPU algorithms in two dimensions. This
does not imply that every structured coefficient, contact law, or GPU
combination is supported.

`HamiltonianTerm` remains the custom scientific interface. Ordinary Julia and
Symbolics expressions describe scalar mathematics; `gather` declares a
finite spatial input, and `LocalMath.fold` makes its ordering, invalid-value,
and empty-neighborhood laws explicit.

```@example custom_hamiltonian
using Potts
using LocalMath
using Symbolics

@variables signal_value

cell = CellKind(:cell; extinction=RetireAtZero())
medium = MediumKind(:medium)
signal = FieldState(signal_value; name=:signal, initial=1.0)
site = SiteBinding(:site)

neighbor_mean(values) = LocalMath.fold(values;
    map=identity,
    combine=+,
    init=0.0,
    finish=(sum, count) -> sum / count,
    domain=isfinite,
    invalid=:reject,
    empty=:reject,
    order=:canonical,
)

system = PottsSystem(
    name=:custom_bounded_term,
    statements=StatementSet((
        Lattice((8, 8); relations=(
            proposal=VonNeumann(),
            contact=VonNeumann(),
        )),
        cell,
        medium,
        signal,
        HamiltonianTerm(
            :neighbor_signal;
            domain=sites(:lattice),
            anchor=site,
            expression=neighbor_mean(gather(
                signal, :contact; at=site
            )),
        ),
        Protocol(Sweep(); name=:main),
    )),
    unknowns=[signal_value],
)

scheduled = mtkcompile(system)
is_scheduled(scheduled)
```

The ownership boundary is deliberate:

```text
Potts Hamiltonian expression and source order
→ Potts resource and footprint analysis
→ CorePotts proposal descriptors and scientific semantics
→ LocalMath bounded spatial law and KernelAbstractions execution
```

The symbolic `_RelationGather` and friendly-reduction tag are eliminated during
compilation, as is the surrounding Symbolics syntax. Their checked concrete
`LocalMath.BoundedFold` remains in the Core static evaluator as the executable
compiler law; no symbolic authoring object reaches the runtime kernels.

Here `:contact` names the bounded relation declared by the enclosing `Lattice`,
and `site` identifies the Hamiltonian anchor. The compiler checks that the
field, relation, anchor, and term domain are compatible before constructing the
runtime law. `order=:canonical` uses the relation's endpoint order, while
`invalid=:reject` and `empty=:reject` make invalid values or empty neighborhoods
reject the containing transaction.

Familiar Julia reductions work directly on a gather. Load `Statistics` for
`mean`:

```julia
using Statistics

neighbor_total(values) = sum(values)
neighbor_low(values) = minimum(values)
neighbor_high(values) = maximum(values)
neighbor_average(values) = Statistics.mean(values)
neighbor_geometric_mean(values) = LocalMath.geometric_mean(values)
```

Relations retain canonical lane order. Repeated endpoints therefore
participate repeatedly, while absent boundary lanes do not participate.
`sum` of an empty gather returns its correctly typed additive identity;
`Statistics.mean` returns its correctly typed `NaN`; and `minimum` and
`maximum` reject an empty gather. `LocalMath.geometric_mean` is available for
concrete floating-point values and rejects nonpositive present values and empty
input. Use `LocalMath.fold` when a custom map, combination, result function, or
invalid/empty policy is scientifically required.

## Fixed-size state values

Named products retain one symbolic state owner. Keep the state declaration to
write ordinary field expressions, including nested fields and fixed vectors:

```julia
using StaticArrays, Symbolics
@variables memory::NamedTuple{(:amount, :polarity, :flags),
    Tuple{Float64, SVector{2,Float64}, NamedTuple{(:enabled,),Tuple{Bool}}}}
state = ModelState(memory; initial=(amount=2.0,
    polarity=SVector(1.0, 0.0), flags=(enabled=true,)))
amount_expression = state.amount + 1
rotated = SVector(-state.polarity[2], state.polarity[1])
enabled = state.flags.enabled
```

Put `state` in the model's statements and use these expressions in ordinary
assignments or constraints. Field access creates expressions over `memory`;
it does not declare separate field states. Import the whole symbolic state
through `ComponentReference` before projecting a local declaration's fields.
Names such as `core` and `name` are available as scientific product fields.
Symbolic renaming and substitution preserve the complete declared product type.
Changing field order, a nested field type, or a fixed-array shape requires
rebuilding the declaration and its field references; incompatible structural
substitution is rejected rather than retaining stale type or shape information.
Stored field units remain distinct, and array fields retain their declared shape.
This expression surface does not add arbitrary field-expression indexing of saved
solutions; read the saved whole product or declare a supported observation.

Declare the logical shape symbolically and supply a fixed-size initial value:

```julia
using StaticArrays
using Symbolics

@variables position[1:2]
position_state = SiteState(position; initial=SVector(1.0, 2.0))
```

On a two-dimensional lattice, this declaration stores one two-component vector
at each site, not two unrelated scalar states or another lattice axis.
`ModelState(position; initial=SVector(1.0, 2.0))` instead retains one vector for
the whole model. A symbolic matrix similarly uses an `SMatrix` initial value.
Floating-point components follow the `scalar_type` selected at `init` or
`solve`; their logical shape is unchanged. Omitted array initial values are zero
values with the declared shape.

Explicit symbolic integer and Boolean types retain their meaning rather than
following floating-point precision selection: for example, declare a counter
with `@variables counter::Int32` and a switch with `@variables enabled::Bool`.
Supplied values must convert to the declared type; a fractional value cannot
silently become an integer counter.

For `PottsInitialState(values=...)`, a model value has the logical shape itself;
a site value is a lattice-shaped array whose elements have that logical shape.
Wrong logical shapes and nonfinite components are rejected. Storage support
does not by itself admit every array operation, process scope, or backend:
those combinations also require an executable expression and an admitted
execution profile.

Fixed-vector expressions can construct an `SVector` from scalar expressions and
read a declared vector component with a literal, in-bounds index. For example,
`Synchronous(:rotate, Assign(position, SVector(-position[2], position[1])))`
declares a quarter-turn from the boundary-entry value. The assignment must
preserve the target's logical shape, and constructed components must have
compatible units. Runtime-selected indices are rejected during analysis; this
surface does not imply general tensor algebra or arbitrary Julia array calls.

Dimensional fixed arrays use one compatible dimension across their components.
For example, `SVector(2.0u"m", 4.0u"m")` with an explicit two-metre reference
length is stored numerically as `SVector(1.0, 2.0)`. Supplied initial values must
carry compatible units on every component; an unlabelled numerical vector does
not silently acquire the declaration's units. Reference conversion is the same
one used for scalar state values.

Every dimensional scalar expression is represented as physical value divided
by the selected reference scale for its result dimension. Multiplication,
division, integer powers, and square roots convert between those scales; the
references need not be coherent products of the length and time references.
An intermediate dimension without an explicit reference uses SI scale one.
Addition, comparisons, and `min`/`max` use the common scale of their compatible
operands. Dimensionless references must have scale one: they cannot redefine
plain numeric literals or indices.

Array initializers participate in the same reference inference as scalar
initializers. All inferred anchors for a dimension must have the same finite,
nonzero magnitude. If components suggest different scales, provide
`ReferenceUnits(...)` explicitly; the compiler does not select an arbitrary
component as the reference.

State dimensions also follow `PottsSystem(initial_conditions=...)` when the
declaration leaves its initial value unspecified. For named products, each field
retains its own dimension, including nested fields. A parent's initial condition
for a qualified child state takes precedence over the child's system default;
a conflicting explicit declaration initial is rejected. Supply `ReferenceUnits`
when system-only dimensional initial conditions do not have declared reference
anchors. Scheduling inspection and runtime conversion use the same selected
initial value as expression unit analysis.

## Named-product initialization

A concrete `NamedTuple` declaration keeps related values under one state owner:

```julia
@variables memory::NamedTuple{(:amount, :enabled, :direction), Tuple{Float64, Bool, SVector{2, Float64}}}
memory_state = ModelState(memory; initial=(
    amount=2.0, enabled=true, direction=SVector(1.0, 0.0),
))
```

At `scalar_type=Float32`, this value becomes
`(amount=2.0f0, enabled=true, direction=SVector(1.0f0, 0.0f0))`.
Integer and Boolean fields retain their declared types. `SiteState` stores one
such product per lattice site; a supplied site initializer is a lattice-shaped
array of products. Field names and order must match the declaration, nested
products retain their structure, and array fields must have fixed size.
Omitted initializers recursively produce zero values, including fixed arrays
of products. Dynamic arrays and nonfinite numerical leaves are rejected.

Dimensional product fields are converted independently, using the same reference
inference and explicit `ReferenceUnits` choices as scalar states. Nested
quantity leaves participate in reference inference; inconsistent inferred scales
need an explicit reference. A supplied replacement must preserve field structure,
fixed-array shape, and each field's dimensions.

These storage and initialization contracts are exercised for model and site
state on both CPU algorithms, including checkpoint restoration. Field-expression
execution is tested separately from storage; neither storage nor CPU execution
by itself establishes cell-process or accelerator support.
