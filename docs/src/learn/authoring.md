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

Every surviving import of an output from the removed subtree needs a reconnection,
even when the replacement uses the same names. Unrelated components and external
input owners remain present. Missing owners, incompatible declarations, duplicate
synchronous writers, unused reconnections, and implicit cross-component connections
are rejected. The result is new, validated, incomplete source; neither the original
source nor an existing simulation is mutated. Use numerical `remake` for parameter
changes, not structural replacement.

This source-binding surface currently supports scalar symbolic parameters and states.
Structured references and scoped declaration syntax require the structured-authoring
extension. Imports within a component containing native declarations and replacement
of a subtree containing native declarations remain unsupported: native port/substitution
reconnection is follow-up work, not a completed component-replacement guarantee.
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
