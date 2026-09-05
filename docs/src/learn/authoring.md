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

A `LocalMath.BoundedFold` can consume the same quantity over a declared finite
spatial relation:

```@example bounded_tracker_authoring
using Potts, LocalMath

kind = CellKind(:cell; extinction=RetireAtZero())
medium = MediumKind(:medium)
proposal = ProposalContext(:copy)

neighbor_mean = LocalMath.bounded_fold(
    identity, +, 0.0, (sum, count) -> sum / count;
    domain=LocalMath.Where(>=(0)),
    oninvalid=LocalMath.RejectInvalid(),
    onempty=LocalMath.FillEmpty(0.0),
    order=LocalMath.CanonicalLeftFold(),
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
finite spatial input, and a LocalMath bounded fold makes its ordering, invalid
value, and empty-neighborhood laws explicit.

```@example custom_hamiltonian
using Potts
using LocalMath
using Symbolics

@variables signal_value

cell = CellKind(:cell; extinction=RetireAtZero())
medium = MediumKind(:medium)
signal = FieldState(signal_value; name=:signal, initial=1.0)
site = SiteBinding(:site)

neighbor_mean = LocalMath.bounded_fold(
    identity,
    +,
    0.0,
    (sum, count) -> sum / count;
    domain=LocalMath.Where(isfinite),
    oninvalid=LocalMath.RejectInvalid(),
    onempty=LocalMath.RejectEmpty(),
    order=LocalMath.CanonicalLeftFold(),
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
                signal, :contact; at=anchor_value(site)
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

The bounded declaration is eliminated during compilation. No Symbolics tree or
authoring object reaches the runtime kernels.

Here `:contact` names the bounded relation declared by the enclosing `Lattice`,
and `anchor_value(site)` identifies the site at which the Hamiltonian term is
evaluated. The compiler checks that the field, relation, anchor, and term domain
are compatible before constructing the runtime law. `CanonicalLeftFold()` uses
the relation's canonical endpoint order; `RejectInvalid()` and `RejectEmpty()`
make evaluation reject an invalid value or empty neighborhood rather than
silently choosing a numerical fallback.
