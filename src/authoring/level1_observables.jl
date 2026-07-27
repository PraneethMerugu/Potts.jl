abstract type AbstractScientificObservable end

struct CellVolume <: AbstractScientificObservable
    name::SemanticName
end
CellVolume(; name::Symbol = :volume, namespace::Namespace = Namespace(:observables)) =
    CellVolume(SemanticName(name; namespace))

struct CellTypeObservable <: AbstractScientificObservable
    name::SemanticName
end
CellTypeObservable(; name::Symbol = :cell_type,
    namespace::Namespace = Namespace(:observables)) =
    CellTypeObservable(SemanticName(name; namespace))

struct CellBoundaryMeasure{M <: CorePotts.AbstractBoundaryMetric} <:
        AbstractScientificObservable
    name::SemanticName
    metric::M
end
CellBoundaryMeasure(metric::CorePotts.AbstractBoundaryMetric =
    CorePotts.BoundaryEdgeCount(); name::Symbol = :boundary_measure,
    namespace::Namespace = Namespace(:observables)) =
    CellBoundaryMeasure(SemanticName(name; namespace), metric)

struct CellPropertyValues <: AbstractScientificObservable
    name::SemanticName
    property::SemanticName
end
function CellPropertyValues(property::CellProperty; name::Symbol = property.name.name,
        namespace::Namespace = Namespace(:observables))
    return CellPropertyValues(SemanticName(name; namespace), semantic_identity(property))
end

"""
    LatticeOwnership(; name=:ownership, namespace=Namespace(:observables))

Typed scientific observable requesting the complete logical ownership lattice and the
generation-aware metadata needed to interpret every finite owner.
"""
struct LatticeOwnership <: AbstractScientificObservable
    name::SemanticName
end
LatticeOwnership(; name::Symbol = :ownership,
    namespace::Namespace = Namespace(:observables)) =
    LatticeOwnership(SemanticName(name; namespace))

semantic_identity(observable::AbstractScientificObservable) = observable.name
_observable_symbol(observable::AbstractScientificObservable) = observable.name.name
_validate_declaration(::AbstractScientificObservable, context::_ValidationContext) = ()
_normalize_component(observable::AbstractScientificObservable, ::Type) = observable
_canonical_write(io::IO, observable::AbstractScientificObservable) =
    _canonical_fields(io, observable)
_lower_component(::AbstractScientificObservable, context::_LoweringContext) =
    _LoweredComponents()

function _declaration_report(observable::AbstractScientificObservable)
    return DeclarationReport(observable.name, :observable, (), (observable.name.name,),
        (:completed_mcs_observation,), (), (:ScientificObservable,),
        (observable_type = nameof(typeof(observable)),),
        CorePotts.ScientificCapabilities())
end

function _scope_declaration(observable::CellVolume,
        fragment::ModelFragment, mapping)
    return CellVolume(_mapped_identity(mapping, observable.name))
end
function _scope_declaration(observable::CellTypeObservable,
        fragment::ModelFragment, mapping)
    return CellTypeObservable(_mapped_identity(mapping, observable.name))
end
function _scope_declaration(observable::CellBoundaryMeasure,
        fragment::ModelFragment, mapping)
    return CellBoundaryMeasure(_mapped_identity(mapping, observable.name), observable.metric)
end
function _scope_declaration(observable::CellPropertyValues,
        fragment::ModelFragment, mapping)
    return CellPropertyValues(_mapped_identity(mapping, observable.name),
        _mapped_identity(mapping, observable.property))
end
function _scope_declaration(observable::LatticeOwnership,
        fragment::ModelFragment, mapping)
    return LatticeOwnership(_mapped_identity(mapping, observable.name))
end

struct ObservationSet{O <: Tuple}
    observables::O
end

function ObservationSet(observables::AbstractScientificObservable...)
    isempty(observables) && throw(ArgumentError(
        "an observation set must contain at least one scientific observable"))
    names = map(observable -> observable.name.name, observables)
    length(unique(names)) == length(names) || throw(ArgumentError(
        "an observation set must use distinct result names"))
    return ObservationSet(Tuple(observables))
end

Base.length(set::ObservationSet) = length(set.observables)
Base.iterate(set::ObservationSet, state...) = iterate(set.observables, state...)

struct CellValue{T}
    id::CorePotts.CellID
    generation::CorePotts.CellGeneration
    cell_type::CorePotts.CellTypeID
    value::T
end

struct CellValues{R <: AbstractVector}
    rows::R
end
Base.length(values::CellValues) = length(values.rows)
Base.isempty(values::CellValues) = isempty(values.rows)
Base.iterate(values::CellValues, state...) = iterate(values.rows, state...)
Base.getindex(values::CellValues, index::Integer) = values.rows[index]

struct CellFrame{V}
    mcs::Int
    values::V
end

struct CellSeries{F <: AbstractVector}
    frames::F
end
Base.length(series::CellSeries) = length(series.frames)
Base.iterate(series::CellSeries, state...) = iterate(series.frames, state...)
Base.getindex(series::CellSeries, index::Integer) = series.frames[index]

"""Generation-aware finite-cell metadata accompanying one ownership observation."""
struct ObservedCell
    id::CorePotts.CellID
    generation::CorePotts.CellGeneration
    cell_type::CorePotts.CellTypeID
end
observed_cell_id(cell::ObservedCell) = cell.id
observed_cell_generation(cell::ObservedCell) = cell.generation
observed_cell_type(cell::ObservedCell) = cell.cell_type

"""
Logical ownership values at one observation boundary.

`owners` is host-owned semantic `OwnerRef` data. `cells` supplies generation and biological type
for every finite owner, and `medium_ids` identifies every conceptual medium domain.
"""
struct OwnershipValues{N, A <: AbstractArray{CorePotts.OwnerRef, N},
        C <: AbstractVector{ObservedCell}, M <: AbstractVector{CorePotts.MediumID}}
    owners::A
    cells::C
    medium_ids::M
end
ownership_size(values::OwnershipValues) = size(values.owners)
ownership_owner_at(values::OwnershipValues, site) = values.owners[site]
ownership_cells(values::OwnershipValues) = Tuple(values.cells)

"""One spatial observation captured at Monte Carlo step `mcs`."""
struct SpatialFrame{V}
    mcs::Int
    values::V
end
spatial_mcs(frame::SpatialFrame) = frame.mcs
spatial_values(frame::SpatialFrame) = frame.values

"""
Ordered spatial observations retained by a Potts solution.

The element values remain visualization-neutral. In particular, a
`SpatialSeries` produced by [`LatticeOwnership`](@ref) contains semantic
ownership and cell metadata rather than colors or backend-specific arrays.
"""
struct SpatialSeries{F <: AbstractVector}
    frames::F
end
Base.length(series::SpatialSeries) = length(series.frames)
Base.iterate(series::SpatialSeries, state...) = iterate(series.frames, state...)
Base.getindex(series::SpatialSeries, index::Integer) = series.frames[index]

function _cell_values(state, value_at)
    rows = map(CorePotts.active_cell_ids(state)) do id
        CellValue(id, CorePotts.generation(state, id), CorePotts.cell_type(state, id),
            value_at(id))
    end
    return CellValues(rows)
end

observe(state, problem::CorePotts.PottsProblem, ::CellVolume) =
    _cell_values(state, id -> CorePotts.finite_volume(state, id))

observe(state, problem::CorePotts.PottsProblem, ::CellTypeObservable) =
    _cell_values(state, id -> CorePotts.cell_type(state, id))

function observe(state, problem::CorePotts.PottsProblem,
        observable::CellBoundaryMeasure)
    geometry = CorePotts.problem_geometry(problem)
    dimensions = length(CorePotts.domain_dimensions(geometry))
    relation = CorePotts.first_shell_relation(
        CorePotts.SurfaceRole(), Val(dimensions);
        spacing = CorePotts.domain_spacing(geometry))
    return _cell_values(state, id -> CorePotts.boundary_measure(
        state, geometry, relation, CorePotts.CellOwner(id), observable.metric))
end

function observe(state, problem::CorePotts.PottsProblem,
        observable::CellPropertyValues)
    key = Symbol(_property_prefix(observable.property))
    return _cell_values(state, id -> CorePotts.property_value(state, key, id))
end

function observe(state, problem::CorePotts.PottsProblem, ::LatticeOwnership)
    cells = map(CorePotts.active_cell_ids(state)) do id
        ObservedCell(id, CorePotts.generation(state, id), CorePotts.cell_type(state, id))
    end
    owners = copy(CorePotts.lattice_storage(state))
    return OwnershipValues(owners, cells, CorePotts.medium_ids(state))
end

function observe(integrator::CorePotts.PottsIntegrator, set::ObservationSet)
    state = CorePotts.logical_state(integrator)
    names = Tuple(observable.name.name for observable in set.observables)
    values = Tuple(observe(state, integrator.prob, observable)
        for observable in set.observables)
    return NamedTuple{names}(values)
end

"""
    observation_policy(set::ObservationSet)

Create a CorePotts snapshot policy that evaluates and retains the declared
scientific observables at each save point.
"""
observation_policy(set::ObservationSet) =
    CorePotts.ObservableSnapshotPolicy(integrator -> observe(integrator, set))

function observe(solution::CorePotts.PottsSolution,
        observable::AbstractScientificObservable)
    frames = CellFrame[]
    handle = CorePotts.PottsObservableHandle(observable.name.name)
    indices = firstindex(solution):lastindex(solution)
    if all(index -> CorePotts.snapshot_residency(solution[index]) === :observable,
            indices)
        values = solution[handle]
        for (index, frame) in zip(indices, values)
            push!(frames, CellFrame(
                CorePotts.snapshot_mcs(solution[index]), frame))
        end
        return CellSeries(frames)
    end
    problem = CorePotts.solution_problem(solution)
    for index in indices
        saved = solution[index]
        CorePotts.snapshot_residency(saved) === :host || throw(ArgumentError(
            "post-hoc observation requires retained host state or a saved observable"))
        push!(frames, CellFrame(CorePotts.snapshot_mcs(saved),
            observe(CorePotts.snapshot_state(saved), problem, observable)))
    end
    return CellSeries(frames)
end

function observe(solution::CorePotts.PottsSolution, observable::LatticeOwnership)
    frames = SpatialFrame[]
    handle = CorePotts.PottsObservableHandle(observable.name.name)
    indices = firstindex(solution):lastindex(solution)
    if all(index -> CorePotts.snapshot_residency(solution[index]) === :observable,
            indices)
        values = solution[handle]
        for (index, frame) in zip(indices, values)
            push!(frames, SpatialFrame(
                CorePotts.snapshot_mcs(solution[index]), frame))
        end
        return SpatialSeries(frames)
    end
    problem = CorePotts.solution_problem(solution)
    for index in indices
        saved = solution[index]
        state = CorePotts.snapshot_state(saved)
        push!(frames, SpatialFrame(CorePotts.snapshot_mcs(saved),
            observe(state, problem, observable)))
    end
    return SpatialSeries(frames)
end

function observation_table(solution::CorePotts.PottsSolution,
        observables::AbstractScientificObservable...)
    isempty(observables) && throw(ArgumentError(
        "an observation table requires at least one observable"))
    any(observable -> observable isa LatticeOwnership, observables) &&
        throw(ArgumentError(
            "LatticeOwnership is spatial array data; use observe(solution, ownership) " *
            "instead of the per-cell observation table"))
    series = Tuple(observe(solution, observable) for observable in observables)
    names = Tuple(observable.name.name for observable in observables)
    rows = NamedTuple[]
    for frame_index in firstindex(solution):lastindex(solution)
        frame_values = Tuple(item.frames[frame_index].values for item in series)
        isempty(frame_values) && continue
        first_rows = first(frame_values).rows
        for cell_index in eachindex(first_rows)
            identity = first_rows[cell_index]
            all(values -> values.rows[cell_index].id == identity.id &&
                values.rows[cell_index].generation == identity.generation,
                frame_values) || throw(ArgumentError(
                    "observable frames do not share one identity-aware cell ordering"))
            values = Tuple(item.rows[cell_index].value for item in frame_values)
            metadata = (mcs = CorePotts.snapshot_mcs(solution[frame_index]),
                id = identity.id,
                generation = identity.generation, cell_type = identity.cell_type)
            push!(rows, merge(metadata, NamedTuple{names}(values)))
        end
    end
    return rows
end
