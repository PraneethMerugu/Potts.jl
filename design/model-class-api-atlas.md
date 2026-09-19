# Model-class API atlas

Status: corrected design, 2026-09-10. This replaces the earlier speculative API
atlas. It does not change the PR allocation or claim the chain is implemented.

For the researched scientific variants and accepted delivery allocation, use
the [composition-first model roadmap](composition-first-model-roadmap.md).
It corrects the OpenVT monolayer/migration interpretations and distinguishes the
Fortuna base model from its chemotaxis extension. Illustrative laws below are
not paper transcriptions. This atlas mixes existing foundations and prospective
constructor forms; no complete snippet should be treated as runtime-verified.

The intended API is **ordinary Julia composition of Potts declarations and
native ModelingToolkit systems**, followed by `PottsProblem` and SciML execution.
It is not a new model-specific language, PDE wrapper hierarchy, Boolean-network
framework, or generic optimizer-component framework.

This document covers all fourteen model families. It gives concrete syntax where
the repository or existing end-state design establishes that syntax. Where only
a contract is established, it states the contract without pretending there is
already a constructor for it. Consequently this is not fourteen executable paper
reproductions: neither unverified paper equations nor unresolved interfaces are
filled in with invented code.

## 1. What is established, and what remains a design choice

The [project charter](../spec/project-charter.md) owns architecture.
The [ideal authoring spec](../spec/ideal_api_vision.md) and
[feature plan](authoring-and-model-ecosystem-plan.md) own intended authoring.
The [dependency map](consolidated-pr-dependency-map.md) owns allocation, the
[compiler amendment](compiler-contract-chain-amendment.md) owns its accepted
refinement, and [progress](pr-chain-progress.md) owns implementation status.

| Surface used here | Evidence and status |
|---|---|
| `PottsSystem`, `@statements`, `Volume`, `ContactEnergy`, `HamiltonianTerm`, `ProposalDrive`, `Chemotaxis` | Existing public foundations: [statements](../src/statements/statement_set.jl), [scientific declarations](../src/statements/semantics.jl). New consumer combinations still need their owner PRs. |
| Quantity declarations, scoped references, ordinary aggregates, compound processes, lifecycle | End-state contracts in the ideal spec and [mechanochemical example](examples/mechanochemical_tissue.jl). Its explicit constructors expose meaning; they are not all implemented signatures. |
| `NativeComponent`, `NativeInput`, `NativeOutput`, `NativeSolveProfile` | Existing [native components](../src/native/components.jl) and [ports](../src/native/ports.jl). G07 extends expression/structured bindings, direct references, lifecycle and numerical combinations. |
| `MethodOfLinesComponent` | An actual [optional extension](../ext/PottsMethodOfLinesExt.jl), documented in [fields](../docs/src/learn/fields-and-ensembles.md). It returns a native component; it is not a second PDE engine. |
| Concise lexical scope and declaration enrollment | Required end-state behavior, with exact ergonomic syntax selected through G04 consumers. Do not invent a macro family or freeze the long example's repeated inventories. |
| Native profiles keyed by component reference | Explicit end-state target; current documentation still has path-based examples. Do not mistake current path tuples for the final authoring requirement. |
| Optimization coupling, richer relation arity, selected topology algorithms | Require concrete interface work where not supplied by the chain. No fake calls are shown for unresolved signatures. |

Examples marked **planned constructor form** use spellings already in the
existing end-state design. This is the explicit form against which a concise
scope must be behaviorally equivalent. It is not a proposal to make authors
repeat anchors and declaration inventories indefinitely.

Parameters use `@parameters`; structural arguments stay ordinary Julia arguments.
A named tuple does not automatically turn every entry into a symbolic parameter.
A returned Julia named tuple is only a convenient collection of references.

## 2. The full outer workflow stays small

This is the small sorting construction already established by the
[complete sorting example](examples/cell_sorting.jl), with initial labels passed
in rather than generated in the function. Its parameter-remake behavior is part
of the planned public workflow.

```julia
using Potts
using ModelingToolkit
using SciMLBase

function sorting_problem(labels, kind_labels; mcs=500, seed=42)
    @parameters temperature=2.0 target_volume=40.0
    @parameters volume_strength=2.0 unlike_contact=12.0

    a = CellKind(:a; extinction=ForbidExtinction())
    b = CellKind(:b; extinction=ForbidExtinction())
    medium = MediumKind(:medium)
    lattice = Lattice(size(labels);
        boundary=Periodic(), max_cells=length(kind_labels),
        relations=(proposal=VonNeumann(), contact=VonNeumann()))

    system = PottsSystem(; name=:sorting, statements=(@statements begin
        lattice
        a
        b
        medium
        Volume(a; target=target_volume, strength=volume_strength)
        Volume(b; target=target_volume, strength=volume_strength)
        ContactEnergy(
            [0.0 16.0 16.0; 16.0 4.0 unlike_contact; 16.0 unlike_contact 4.0];
            kinds=(medium, a, b), relation=:contact)
        Protocol(Sweep(; temperature); name=:main)
    end))

    all(k -> k in (:a, :b), kind_labels) ||
        throw(ArgumentError("kind_labels must contain only :a or :b"))
    kinds = [k == :a ? a : b for k in kind_labels]
    initial = PottsInitialState(;
        ownership=LabelledCells(labels; cells=kinds, medium))
    problem = PottsProblem(system, initial, (0, mcs); seed)
    return (; system, problem, unlike_contact)
end

labels = zeros(Int32, 64, 64)
for (id, (x, y)) in enumerate([(x, y) for y in 8:14:50 for x in 8:14:50])
    labels[x:x+5, y:y+5] .= id
end
model = sorting_problem(labels, [isodd(i) ? :a : :b for i in 1:16])
solution = solve(model.problem, SequentialCPM();
    backend=CPUBackend(), scalar_type=Float64, saveat=0:10:500)
changed = remake(model.problem; p=(model.unlike_contact => 20.0,))
```

Larger models keep this construction/initialization/solve boundary. They add real
equations, quantities, interactions and scientific order inside their ordinary
factories. They do not add a new top-level runner or per-model executor.

## 3. Intracellular systems really are ModelingToolkit systems

**Planned constructor form**, using G07 bindings from the existing
[mechanochemical example](examples/mechanochemical_tissue.jl).

The helper below is completely defined ordinary Julia. Its caller supplies one
cell binding, a derived input expression and an already-declared output quantity.
It does not allocate a second Potts input state or clone the supplied output.

```julia
using Potts
using ModelingToolkit

function receptor_dynamics(; kind, cell, concentration, receptor,
                            interval, name=:intracellular)
    @independent_variables t
    @variables r(t) ligand(t)
    @parameters kon=1.0 koff=0.2
    D = Differential(t)

    @named equations = System([
        D(r) ~ kon * ligand * (1 - r) - koff * r,
    ], t)

    component = NativeComponent(equations;
        name,
        family=ODEComponent(),
        scope=PerCell(kind),
        anchor=cell,
        time=FixedPhysicalTime(0.0, interval),
        cadence=EveryMCS(1),
        inputs=(NativeInput(ligand, concentration),),
        outputs=(NativeOutput(r, receptor[cell]),),
        initialization=FromPublishedState(),
        lifecycle=PerCellNativeLifecycle(
            creation=FromPublishedState(),
            division=FromPublishedState(),
            transition=FromPublishedState(),
            retirement=Discard()))
    return (; component, equations, kon, koff)
end
```

For example, within a model factory, with `population`, `lattice` and the
extensive field `free_ligand` already declared:

```julia
c = CellBinding(:cell)
receptor = CellState(:receptor;
    domain=population, value_type=Float64, initial=0.1, bounds=(0.0, 1.0),
    division=CopyToDaughters(), retirement=Discard())

exposure_amount = aggregate(free_ligand;
    name=:exposure_amount, over=sites(lattice), by=owner, groups=population)
site_count = aggregate(1;
    name=:site_count, over=sites(lattice), by=owner, groups=population)

intracellular = receptor_dynamics(;
    kind=epithelial, cell=c,
    concentration=exposure_amount[c] / (voxel_volume * site_count[c]),
    receptor, interval)
```

These snippets declare a receptor law and its complete IO/lifecycle mapping;
they are not a complete tissue by themselves. The enclosing scope enrolls the
field, quantities, state and component once, and its protocol orders that same
component. The complete existing tissue example supplies the other mechanisms.

What G07 is supposed to remove from ordinary authoring:

- Intermediate input arrays solely to carry the derived concentration.
- Repeated component-path tuples and numerical variable indices.
- Manual source-invalidation, refresh, sampling and publication stages.
- Duplicate independently editable initial values for one mapped unknown.

What remains explicit: native equations, population, input/output meaning,
physical duration, cadence, input hold or other coupling law, and biological
partition/reset policy. This constructor uses the established held-input split;
it does not infer an arbitrary simultaneous coupled solve.

MTK retains equations, hierarchy, parameters, observations and initialization.
Its internal solver state and Potts's committed output snapshot have distinct
temporal roles, not two independent scientific definitions. Native output
symbols can be eliminated or reconstructed during MTK compilation; resolve
them through public symbolic interfaces. `FromPublishedState()` only inverts
a proven actual-unknown mapping, never an arbitrary observed expression.

At the end of the chain, numerical selection uses the component reference:

```julia
using OrdinaryDiffEqTsit5: Tsit5

native_profiles = (NativeSolveProfile(
    intracellular.component, Tsit5();
    execution=BatchedNativeExecution(32),
    adaptive=false, dt=interval / 4, exact_replay=false),)

solution = solve(problem, SequentialCPM();
    backend=CPUBackend(), scalar_type=Float64,
    native_profiles, observables=(receptor,), saveat=0:10:1000)
```

Here `problem` is the enclosing model's `PottsProblem`; the profile is not an
additional model component. Batched support, dtype and backend admission still
have to be tested for the complete combination.

## 4. PDEs use the real MethodOfLines path

This construction is adapted directly from the repository's
[MethodOfLines example](../docs/src/learn/fields-and-ensembles.md). It uses the
**existing adapter signature**, not an invented end-state field DSL.

```julia
using Potts
using ModelingToolkit
using MethodOfLines
using DomainSets

@parameters t x y
@variables u(..) field(t)
Dt = Differential(t)
Dxx = Differential(x)^2
Dyy = Differential(y)^2

equations = [
    Dt(u(t, x, y)) ~ 0.1 * (Dxx(u(t, x, y)) + Dyy(u(t, x, y))),
]
conditions = [
    u(0, x, y) ~ 1 + 0.1 * cos(2pi * x) * cos(2pi * y),
    u(t, 0, y) ~ u(t, 1, y),
    u(t, x, 0) ~ u(t, x, 1),
]
domains = [
    t ∈ Interval(0.0, 1.0),
    x ∈ Interval(0.0, 1.0),
    y ∈ Interval(0.0, 1.0),
]
@named pde = PDESystem(
    equations, conditions, domains, [t, x, y], [u(t, x, y)])
discretization = MOLFiniteDifference(
    [x => 4, y => 4], t; grid_align=center_align)

field_state = FieldState(field;
    name=:field, initial=0.0, stencil=:field_stencil)
chemistry = MethodOfLinesComponent(
    pde, discretization, u(t, x, y), field_state;
    spatial=(x, y), name=:chemistry,
    time=FixedPhysicalTime(0.0, 0.125))
```

The surrounding existing example supplies the matching 4×4 periodic lattice
with `:field_stencil`, registration, native operating point and solve profile.
This small diffusion example demonstrates the adapter, not a biological model.
Its periodic initial condition has the analytic solution
`1 + 0.1 * exp(-0.8pi^2 * t) * cos(2pi * x) * cos(2pi * y)`;
that supplies a numerical convergence oracle, not an exact discrete equality.
The PDE's initial condition owns native initialization; the field is its
published view, not a second independently evolving PDE.

The path is:

```text
PDESystem + MOLFiniteDifference
    → MethodOfLines symbolic discretization
    → native MTK system
    → NativeComponent + NativeFieldOutput
    → ordinary SciML integration and Potts publication
```

The end-state improvement is expression/structured IO, convenient references,
multispecies and cross-grid coupling through G07/E07. It is NOT replacement of
MethodOfLines by a Potts-owned PDE language.

Important limits of the present adapter are visible in its source: one selected
field output, no reciprocal input argument, checked coordinates, and the
documented CPU 2D profile. Those are present restrictions, not a prediction that
the final chain remains output-only. Extending cell-dependent sources, multiple
species and different grids requires the planned binding/publication work.
The exact extended adapter keywords are not frozen by the plan; do not invent
them in a model example.

A multispecies model should supply its real coupled PDE system once, discretize
it once, and bind its dependent fields through the native field-output path.
Building a separate independently solved PDE for every species could change
reaction coupling. Conversely, an explicitly chosen split is a scientific
choice, not an implementation shortcut.

The existing `DiscreteFieldEuler()` remains useful for its prescribed lattice
stencil. It is an alternative numerical realization with stated restrictions,
not a general replacement for MethodOfLines.

## 5. Material exchange is the existing planned Transfer contract

**Planned constructor form**, directly from the shared design. An extensive
field and an intracellular store are different physical pools. Measuring the
field over a cell does not create another pool.

```julia
uptake = Transfer(:uptake;
    domain=population, anchor=c,
    from=free_ligand, to=internal_ligand[c],
    over=owned_sites(c),
    rate=uptake_rate * volume[c] *
        environment_concentration[c] / (uptake_half + environment_concentration[c]),
    duration=interval,
    destination_capacity=storage_capacity * volume[c],
    weights=:available_amount,
    shortage=:limit,
    shared_source=:proportional)
```

The named inputs here are declared quantities/parameters in the enclosing model;
the complete declaration and retirement/deposition policies are in the
mechanochemical example. One realized transfer owns subtraction and addition.
Do not independently lower a negative source and positive destination and hope
they conserve mass.

Scientific stage order stays visible, using the existing planned `after`
keyword, not a newly invented protocol signature:

```julia
protocol = Protocol(Sweep(; temperature);
    name=:main,
    after=(chemistry, uptake, intracellular.component, growth,
        LifecycleBatch((retire, divide);
            arbitration=StableLifecyclePriority((retire, divide)))))
```

This fragment assumes the named processes already exist. It specifies sequential
feedback, with retirement winning conflicting lifecycle requests. Other splits
must be deliberately specified; declaration order must not silently choose
between shared native snapshots and sequential feedback.

## 6. The fourteen models, using this vocabulary

Each entry states initialization, model law, scientific order, observations and
the remaining interface or paper-specific work. Equations described in prose
are requirements, not secretly implemented helper functions. Illustrative
formulas below are labeled; they are not asserted paper transcriptions.

### 1. Merks contact-inhibition extension

**Authoring:** ordinary volume/contact declarations; one autocrine
reaction–diffusion PDE through MethodOfLines (or the explicitly selected
prescribed stencil); a chemotactic proposal drive restricted to the intended
cell–medium interface. Initialization is scattered cells or an aggregate plus
the chemical initial field.

The existing built-in spelling for extension-only taxis is:

```julia
Chemotaxis(endothelial, chemo; strength=chi, mode=ExtensionsOnly())
```

That call alone is not a contact-inhibition model. The required interface mask
and whether retractions respond must match the selected experiment. Express the
mask using the ordinary `ProposalDrive` guard and proposal semantics; do not
invent another chemotaxis class or treat `ExtensionsOnly()` as an interface mask.
The source/target response and secretion/decay equations need paper verification.

**Order:** copy sweep using held chemical values, then scheduled PDE evolution.
**Observe:** chemical field, cell geometry and network compactness with explicit
normalization. **Chain:** G05–G07/E07, and E08 only for the selected exact topology
law. Never silently add an acceptance constraint to make the picture look right.

### 2. Growing monolayer

**Authoring:** a target-volume `CellState`, measured contact exposure or crowding,
a `SynchronousProcess`, and a `LifecycleProcess`. No special growth framework.

This is an illustrative law, in **planned constructor form**; `exposed` is a
declared scientific quantity and all coefficients are symbolic parameters:

```julia
growth = SynchronousProcess(:growth;
    domain=population, anchor=c,
    effects=(Assign(target[c], target[c] +
        growth_per_mcs * (exposed[c] >= exposure_threshold)),),
    cadence=EveryMCS(1))

elasticity = HamiltonianTerm(:volume_energy;
    domain=population, anchor=c,
    expression=volume_strength * (volume[c] - target[c])^2)
```

**Initialize:** seed colony, target sizes and spare cell capacity.
**Order:** sweep, growth, admissible division; partition target and material by
their separate policies. **Observe:** count, area/radius and growth curves.
**Chain:** G04/G05/G07/G08. The exposure law is not a claimed OpenVT calibration.

### 3. Single-cell migration with activity memory

**Authoring:** site activity, geometric-mean neighborhood sensing, a
`ProposalDrive`, `AcceptedCopyProcess` activation and synchronous aging.
The shared example already proposes `PottsModels.ActivityDrive`; its formula
must remain visible in its ordinary factory, not become a privileged compiler
operation merely because it has a convenient name.

```julia
activate = AcceptedCopyProcess(:activate;
    when=source_kind(copy) == motile,
    effects=(Assign(activity[copy.target_site], activity_lifetime),))

decay_activity = SynchronousProcess(:decay_activity;
    domain=sites(lattice), anchor=s,
    effects=(Assign(activity[s], max(0.0, activity[s] - 1.0)),),
    cadence=EveryMCS(1))
```

**Initialize:** one cell, cleared site memory. Declare
`ClearOnOwnershipChange()` on the site state; clearing precedes accepted
activation. **Order:** activation on accepted copies, aging at the MCS boundary.
**Observe:** unwrapped centroid trajectories; compute MSD/persistence with stated
sampling. **Chain:** G04–G06/G08. A per-cell ODE is not a replacement for site memory.

### 4. Driven foam rheology

**Authoring:** per-bubble target areas, interface energy and the paper's driven
acceptance law expressed as a `ProposalDrive`, distinct from the conservative
`HamiltonianTerm`. Initialize the bubble tessellation and loading geometry.

**Order:** prescribed strain/loading clock, attempted updates under the selected
proposal distribution, then sampled response. **Observe:** stored energy,
stress defined by the chosen loading law, side counts and contact-history T1s.

**Unresolved:** the exact boundary-copy proposal distribution, attempt
normalization and shear-bias equation. A velocity field by itself does not define
the acceptance bias. E02's auxiliary equilibrium law and E11's swap law do not
prove support for this law. Keep its signature open until the public Core
proposal contract is examined; no made-up foam algorithm constructor.

### 5. ECM-topography angiogenesis

**Authoring:** endothelial mechanics/taxis, ECM label or field state,
cell-dependent PDE source terms, ECM-degradation processes and lifecycle.
Use actual PDE equations and the same planned state/process contracts.

**Initialize:** parent vessel, ECM fibers, soluble field and any fixed regions.
**Order:** declared ECM/chemical updates, phenotype decisions, growth/division,
with the chosen hold/sweep split. **Observe:** vessel coverage, branching and
ECM/chemical evolution.

**Remaining science:** exact fiber mechanics versus degradable material,
tip/stalk rules, recruitment versus division as a population source, and
connectivity policy. They cannot be hidden in a fictional angiogenesis
constructor. **Chain:** G04/G07/E07/E08 as applicable.

### 6. Three-dimensional avascular tumour

**Authoring:** five-species PDE chemistry, 3D CPM geometry, a cell-cycle logical
state and explicit growth/arrest/death/division processes. The intracellular
Boolean network is finite state updated by `SynchronousProcess`; the chain's
structured Boolean state does not require a new network executor.

For a supplied scientific truth table, an ordinary Julia helper can build one
`Assign` per named node. All RHS expressions read the same pre-update state.
Asynchronous logical updates require their own stated ordering; they are not
equivalent to synchronous updates or automatically native root events.

**Initialize:** 3D seed, all field species, every Boolean node and target size.
**Order:** chemistry, exposure, logical update, growth/death, lifecycle under the
declared coupling split. **Observe:** radial profiles, viable/quiescent/necrotic
populations and material balance.

**Remaining:** transcribe all equations/rules and explicit cross-grid maps.
**Chain:** G04/G05/G07/E01/E07. Numerical PDE evolution belongs upstream; source,
sampling and settlement meaning belongs at the coupling boundary.

### 7. Tumour-induced sprouting angiogenesis

**Authoring:** the same mechanics/PDE/state/process/lifecycle primitives as #5,
with the earlier model's actual tumor source and changing stroma.
Branching and anastomosis are emergent behavior plus measured geometric events,
not evidence that a named branch-generation API is needed.

**Initialize:** tumor source, parent vessel, stroma and fields.
**Order:** explicit field/stroma/phenotype/growth stages and the CPM split.
**Observe:** sprout length, branching, connectivity and field depletion.
**Remaining:** complete phenotype/stroma equations and boundary recruitment.
**Chain:** G04/G07/E07/E08. Share the verified mechanisms with #5, not merely
similarly named parameter bundles.

### 8. Flux-balance cellular automaton

**Authoring:** ordinary metabolic definitions and constraints upstream;
Potts quantities for nutrient exposure, biomass and growth; conservative
coupling to extracellular resources. An LP is not an MTK ODE island.

The upstream operation is real:

```julia
using COBREXA
using HiGHS

function solve_metabolism(metabolic_model)
    return flux_balance_analysis(metabolic_model; optimizer=HiGHS.Optimizer)
end
```

This is only a standalone solve, **not** the spatial coupling implementation.
The [upstream FBA example](https://cobrexa.github.io/COBREXA.jl/stable/examples/02a-flux-balance-analysis/)
documents it. The user confirmed COBREXA.jl on 2026-09-10. R51 owns its coupling
and R52 the FBCA model under the accepted composition-first amendment; the
standalone call above does not establish either integration.

**Initialize:** spatial cells, dry masses, nutrient amounts and the supplied
metabolic model. **Order:** sample resource availability; allocate feasible
uptake bounds or solve a genuinely coupled resource problem; solve; validate
status and selected fluxes; settle exchange and biomass together; then divide.
**Observe:** named upstream fluxes, biomass and accounted material.

**Unresolved interface:** generation-safe solver workspace ownership, bound
updates, selected-result publication, failure behavior and lifecycle. Reuse
G07/E07 public settlement/transfer where meaning agrees, but do not invent a
universal constraint component or claim G07 already supports optimization.

Specify flux units, uptake sign, biomass basis, integration rule and residual
optimal ties. The same interval-entry biomass must be used consistently in
exchange and a corresponding explicit growth step. Parsimonious FBA alone
does not establish a unique solution or replay across solvers.

### 9. Differential-adhesion sorting

The complete API is section 2: kinds, volume/contact energies, label
initialization, protocol, problem, solve and remake. No intracellular state or
native dependency is needed.

**Observe:** heterotypic contact and segregation with stated normalization.
**Chain:** existing baseline plus G04–G06/G08 authoring and scientific guarantees.
A Chaste comparison also matches boundary, neighborhood and attempt law.

### 10. Leader–follower tumour invasion, 2026

**Authoring:** leader and follower kinds, ordinary adhesion, leader polarity
state/drive, follower growth and lifecycle. Reuse the same public quantities
rather than wrapping the paper in a tumor-specific runtime.

For a declared polarity quantity, the existing planned drive form is:

```julia
motility = ProposalDrive(:leader_motility,
    -motility_strength * dot(polarity[copy.new_owner], copy.direction);
    when=source_kind(copy) == leader)
```

**Initialize:** labeled leader/follower geometry, polarity and target sizes.
**Order:** sweep, the paper's polarity update, follower growth, division.
**Observe:** invasive/infiltrative measures and clusters/fingers/singles under
the paper's actual definitions; parameter campaigns use SciML ensembles.

**Remaining:** verify the precise 2026 motility and classification laws.
The earlier atlas's rotational diffusion was an illustrative substitution,
not an established fact about this paper. **Chain:** G04–G08 and selected E08
analysis where its actual algorithm suffices.

### 11. Intracellular ODE/Boolean signaling with tumour and vasculature

**Authoring:** genuine MTK equations/native components as in section 3, Boolean
state/processes as in #6, and real PDE chemistry as in section 4. Inputs are
derived field/contact quantities; outputs publish into quantities used by
growth, taxis and lifecycle.

**Initialize:** every native unknown through its legitimate initialization
mapping, logical node, field and cell type. **Order:** specify which native
components sample together and which decisions see freshly published outputs;
then growth and arbitrated death/division. **Observe:** native outputs, Boolean
state, chemical fields and tissue outcomes.

**Remaining:** all network equations and source terms, not just a receptor
placeholder. **Chain:** G07/E07; E05 only for actual localized native events,
E06 only for actual SDE/jump dynamics. A discrete Boolean decision at an MCS
boundary does not need either by itself.

### 12. Anisotropic differential adhesion / convergent extension

**Authoring:** ordinary `HamiltonianTerm` over a declared contact relation, using
derived cell orientation/shape and the paper's anisotropic interface formula.
Use the planned `ContactBinding` and quantity mathematics; do not invent a
second energy API.

**Initialize:** cells and any independently evolving orientation state.
If orientation is determined by current geometry, it is derived instead.
**Order:** CPM plus only genuinely dynamic orientation processes.
**Observe:** tissue shape, alignment and intercalation.

**Remaining:** transcribe the actual formula, contact measure, periodic geometry
and degenerate-axis behavior. The previous atlas's nematic formula was not a
verified transcription. **Chain:** G05/G05C/G06. A copy changing a cell axis can
change energy on remote interfaces of that cell; the full dependency closure,
not just the changed boundary bond, determines its energy delta.

### 13. Segmented myxobacteria

**Authoring:** segment identities, mechanical relationships, geometric
quantities, ordinary `HamiltonianTerm` expressions and active drives.
Established pair-spring authoring already looks like this:

```julia
spring_energy = HamiltonianTerm(:spring_energy;
    domain=edges(links), anchor=e,
    expression=0.5 * e.stiffness *
        (norm(center[endpoint_a(e)] - center[endpoint_b(e)]) - e.rest_length)^2)
```

**Initialize:** ordered segments, their biological rod grouping and periodic
geometry. **Order:** motion under the selected drive; explicit reversal or
relationship processes only if included. **Observe:** rod axes, trajectories
and collective alignment.

**Unresolved:** biological parent grouping is not synonymous with containment.
Ordered three-segment bending needs a representable relation and inverse
dependency closure. E03's pair endpoints alone do not prove it; first test
whether existing bounded traversal/composition expresses it correctly, then add
a real missing owner contract if needed. Do not predeclare an ordered-chain
framework or fake arbitrary-arity support. **Chain:** G05/G06/E03/E04 subject to
that concrete review.

### 14. Nucleus–cytoplasm–lamellipodium migration

**Authoring:** E04 compartment identities/lifecycle, ordinary mechanics and
proposal drives, substrate/field state, native reaction–diffusion where selected,
and explicit stochastic site-conversion effects.

**Initialize:** labeled compartments, biological grouping, substrate and activity
field. **Order:** the paper's accepted-copy and site-conversion rules, field
evolution and any external-cue response. **Observe:** parent trajectory,
compartment morphology and nuclear enclosure.

**Unresolved:** the public site-transfer declaration, creation of a previously
empty lamellipodium, parent-preserving conversion, and field membership on
moving parent boundaries. Existing compound state publication is not proof of
arbitrary ownership-transition support. Exact 3D enclosure is also distinct
from energetic preference for enclosure; imposing it can change the model.

**Chain:** E01/E04/E07 and the selected E08 law where applicable. No invented
compartment-population or ownership-transfer constructor is offered as if these
signatures had already been chosen.

## 7. SBML integration should disappear into native authoring

Use the [documented upstream importer](https://docs.sciml.ai/SBMLToolkit/stable/api/):

```julia
using SBMLToolkit

function read_signaling_model(path)
    SBMLToolkit.checksupport_file(path)
    return readSBML(path, ODESystemImporter())
end
```

Its result takes the place of the authored MTK `equations` in section 3.
Select actual native input/output symbols using upstream public references,
then use the same native bindings, lifecycle and numerical profile. No SBML-only
copy of the equations, state model or solver path.

A reusable optional extension is justified for missing identifier/units/native
binding work, not merely to rename an existing importer. Test importer-to-native
composition against supported dependency ranges. Preserve amounts versus
concentrations, compartment volume, initial assignments and event meaning.
A chemical SBML compartment is not automatically a spatial CPM compartment.

If dynamic cell volume is mapped into a concentration model, account for
dilution and partition actual amounts at division. Reject unsupported SBML
features explicitly. Successful parsing alone does not establish their correct
execution through Potts.

## 8. How we keep the code excellent

### Let the actual owners do their jobs

- Potts owns scientific authoring, symbolic/native composition and lowering.
- CorePotts owns CPM identities, proposal semantics and transactional settlement.
- LocalMath owns spatial mathematics/publication and the shared KA execution
  machinery; scientific rules come from their domain owner.
- MTK/SciML/MethodOfLines own native equations, discretization and integration.
- The metabolic package and its solver stack own metabolic constraints/solves.
- PottsModels owns reusable biological equations, initializers and model tests.
- MakiePotts consumes public committed observations.

An adapter translates only the boundary neither side already owns. No private
buffer access, duplicate equation store, alternate executor, type piracy or
always-loaded optional dependency.

### Judge ergonomics by novel authoring, not constructor count

A user must be able to change one equation, share one field between two native
systems, replace one growth law, and move a helper into another module without
compiler edits or manual refresh code. Those are ordinary integration tests.

Concise scope removes repeated anchors and registration, not scientific choices.
Numerical `remake` does not mutate structure. Direct component/quantity references
replace incidental paths. Observations select existing quantities instead of
introducing another maintained copy for reporting.

The snippets here use explicit constructor forms where that is the honest
established representation. Finishing the chain still requires the concise
public workflow, not merely making these verbose forms pass.

### Defend behavior, ownership and cost

Use independent tiny-system energy oracles, analytic PDE/transfer cases, Boolean
truth-table tests and a small independently solvable metabolic problem.
Exercise two cells competing for one pool; native output feeding mechanics;
division/retirement with native and extensive state; held-value restart;
relationship invalidation; and late failures with clocks and RNG accounted for.

Run ordinary package tests, executable docs, Aqua/ExplicitImports as applicable,
extension load-order/compatibility tests and actual admitted CPU/GPU combinations.
Keep fixtures local. Do not replace scientific assertions with syntax checks,
struct-layout tests or ceremonial metadata.

Measure compilation, preparation, allocation, source-update fan-out, warm
execution and host/device transfers. Reuse symbolic definitions across numerical
cell instances. Pool mutable solver workspaces only with exclusive ownership and
verified reset/continuation semantics.

Functional support, paper reproduction, deterministic results, portable restart,
exact replay and performance are separate claims. Each needs direct tests or
reproducible experiments. A correct amount ledger does not prove an imported
metabolic network is elementally balanced.

### Resolve actual gaps before inventing public vocabulary

The concrete unresolved boundaries exposed here are reciprocal/multifield native
binding, optimization coupling, the foam proposal law, richer relationship
dependencies, and compartment site transitions/topology. Some may already fit
planned public composition; that must be demonstrated before allocating new
abstractions or PRs.

The canonical map now identifies 62 PRs after the user-approved composition-first
amendment. This atlas is not evidence that all fourteen models are implemented or that every paper has
been transcribed. A further model example must use the same established APIs,
with missing signatures visibly unresolved until selected and exercised.

## Scientific references

These identify the models; equations and parameter tables still require faithful
transcription and validation before reproduction claims.

- [Merks 2008](https://journals.plos.org/ploscompbiol/article?id=10.1371/journal.pcbi.1000163)
- [OpenVT reference models](https://www.openvt.org/pages/working-groups/reference-models-wg.html)
- [Wortel 2021 activity/migration](https://pmc.ncbi.nlm.nih.gov/articles/PMC8390880/)
- [Jiang 1999 foam](https://journals.aps.org/pre/abstract/10.1103/PhysRevE.59.5819)
- [Bauer 2009 ECM](https://journals.plos.org/ploscompbiol/article?id=10.1371/journal.pcbi.1000445)
- [Jiang 2005 avascular tumour](https://pmc.ncbi.nlm.nih.gov/articles/PMC1366955/)
- [Bauer 2007 angiogenesis](https://pubmed.ncbi.nlm.nih.gov/17277180/)
- [FBCA 2020](https://boa.unimib.it/handle/10281/255735)
- [Chaste sorting](https://chaste.github.io/old_releases/release_3.0/UserTutorials/RunningPottsBasedSimulations.html)
- [Akeeb, Marcus and Jiang 2026](https://doi.org/10.1371/journal.pcbi.1014747)
- [Multiscale signaling 2021](https://journals.plos.org/ploscompbiol/article?id=10.1371/journal.pcbi.1009081)
- [Zajac, Jones and Glazier 2003](https://pubmed.ncbi.nlm.nih.gov/12727459/)
- [Starruß et al. 2007](https://doi.org/10.1007/s10955-007-9298-9)
- [Fortuna 2020](https://pmc.ncbi.nlm.nih.gov/articles/PMC7264849/),
  [chemotaxis extension](https://arxiv.org/abs/2312.00776)
