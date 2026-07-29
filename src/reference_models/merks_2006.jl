module Merks2006

using ...Authoring
using OrdinaryDiffEqTsit5: Tsit5
import CorePotts
import ProcessBigraphs
import SciMLBase

export Profile, Model, profile, canonical_profile, reduced_profile
export model, problem, composite, observation_plan, initial_labels
export field_declaration, semantic_manifest, differential_from_v1
export MigrationRequiredError, restore_v2

const SEMANTIC_VERSION = v"2.0.0"
const SOURCE_DOI = "10.1016/j.ydbio.2005.10.003"

"""Named source and execution profile for the Merks 2006 model family."""
struct Profile
    identity::Symbol
    dimensions::NTuple{2,Int}
    cells::Int
    central_extent::Int
    target_area_sites::Float64
    target_length_sites::Float64
    temperature::Float64
    chemotaxis_gamma::Float64
    volume_strength::Float64
    source_length_strength::Float64
    secretion_rate::Float64
    diffusion::Float64
    decay::Float64
    subcycles_per_mcs::Int
    mcs::Int
    seed::UInt64
    backend_claim::Symbol
    source_trace::NamedTuple
    deviations::Tuple
    expected_observations::Tuple
    scientific_nonclaims::Tuple
end

function Profile(identity::Symbol, dimensions::NTuple{2,<:Integer};
        cells::Integer,
        central_extent::Integer,
        target_area_sites::Real=100.0,
        target_length_sites::Real=50.0,
        temperature::Real=50.0,
        chemotaxis_gamma::Real=1000.0,
        volume_strength::Real=50.0,
        source_length_strength::Real=5.0,
        secretion_rate::Real=1.8e-4,
        diffusion::Real=0.1,
        decay::Real=1.8e-4,
        subcycles_per_mcs::Integer=15,
        mcs::Integer=2,
        seed::Integer=2006,
        backend_claim::Symbol=:cpu,
        deviations::Tuple=(),
        scientific_nonclaims::Tuple=(
            :no_figure_5_reproduction,
            :no_morphometry_claim,
            :no_ensemble_claim,
            :no_source_author_endorsement,
        ))
    dims = (Int(dimensions[1]), Int(dimensions[2]))
    all(>(0), dims) ||
        throw(ArgumentError("Merks dimensions must be positive"))
    0 < cells <= typemax(UInt32) ||
        throw(ArgumentError("Merks cell count must fit UInt32"))
    0 < central_extent <= minimum(dims) ||
        throw(ArgumentError("Merks placement extent must fit the domain"))
    subcycles_per_mcs > 0 ||
        throw(ArgumentError("Merks subcycle count must be positive"))
    mcs > 0 || throw(ArgumentError("Merks runtime bound must be positive"))
    0 <= seed <= typemax(UInt64) ||
        throw(ArgumentError("Merks seed must fit UInt64"))
    values = Float64.(
        (
            target_area_sites,
            target_length_sites,
            temperature,
            chemotaxis_gamma,
            volume_strength,
            source_length_strength,
            secretion_rate,
            diffusion,
            decay,
        ),
    )
    all(isfinite, values) && all(>(0), values) ||
        throw(ArgumentError(
            "Merks physical parameters must be finite and positive"))
    source_trace = (
        doi=SOURCE_DOI,
        equations=(3, 4, 5, 6),
        phase16_evidence="merks-vasculogenesis-reference-assembly-v1",
        source_field_boundary=:periodic_minimize_boundary_effects,
        connectivity=:clockwise_moore_local_rejection,
        placement=:deterministic_seeded_nonoverlap,
        semantic_model_version=string(SEMANTIC_VERSION),
    )
    return Profile(
        identity,
        dims,
        Int(cells),
        Int(central_extent),
        values...,
        Int(subcycles_per_mcs),
        Int(mcs),
        UInt64(seed),
        backend_claim,
        source_trace,
        deviations,
        (
            :cell_count,
            :occupied_sites,
            :disconnected_cells,
            :field_mass,
            :field_range,
        ),
        scientific_nonclaims,
    )
end

canonical_profile() = Profile(
    :canonical_500x500,
    (500, 500);
    cells=282,
    central_extent=333,
    mcs=2,
    backend_claim=:qualified_cpu,
)

reduced_profile() = Profile(
    :reduced_docs_cpu,
    (20, 20);
    cells=2,
    central_extent=16,
    target_area_sites=5.0,
    target_length_sites=5.0,
    mcs=2,
    seed=11,
    backend_claim=:cpu,
    deviations=(
        :reduced_domain,
        :reduced_cell_count,
        :reduced_target_area,
        :reduced_target_length,
        :shortened_runtime,
        :documentation_seed,
    ),
)

function profile(identity::Symbol=:reduced_docs_cpu)
    identity === :canonical_500x500 && return canonical_profile()
    identity === :reduced_docs_cpu && return reduced_profile()
    throw(ArgumentError(
        "Merks profile must be :canonical_500x500 or :reduced_docs_cpu"))
end

"""Reusable downstream-owned Merks v2 semantic model."""
struct Model{P,M,C,E,B,F}
    profile::P
    potts::M
    cell::C
    extracellular::E
    border::B
    field::F
end

function _moore_roles()
    topology = CorePotts.MooreTopology{2}()
    return CorePotts.SpatialRoles(
        proposal=CorePotts.static_relation(
            CorePotts.ProposalRole(), topology),
        contact=CorePotts.static_relation(
            CorePotts.ContactRole(), topology),
        surface=CorePotts.static_relation(
            CorePotts.SurfaceRole(), topology),
        connectivity=CorePotts.static_relation(
            CorePotts.ConnectivityRole(), topology),
        query=CorePotts.static_relation(
            CorePotts.SpatialQueryRole(), topology),
    )
end

function model(spec::Profile=profile())
    cell = CellType(:endothelial)
    extracellular = Medium(:extracellular_matrix)
    border = Medium(:border)
    volume = Volume(
        cell => (
            target=spec.target_area_sites,
            strength=spec.volume_strength,
        ),
    )
    elongation = Elongation(
        cell => (
            target=spec.target_length_sites / 4,
            strength=16 * spec.source_length_strength,
        );
        target_division=CloneOnDivision(),
    )
    contact = PairwiseLaw(
        :contact_energy,
        (cell, cell) => 40.0,
        (cell, extracellular) => 20.0,
        (cell, border) => 100.0,
        (extracellular, extracellular) => 0.0,
        (extracellular, border) => 0.0,
        (border, border) => 0.0,
    )
    field = Field(
        :chemoattractant;
        placement=CellCentered(),
        boundary=PeriodicField(),
        interpolation=Nearest(),
    )
    chemotaxis = Chemotaxis(
        field,
        cell => spec.chemotaxis_gamma / spec.temperature;
        response=LinearResponse(),
        mode=ExtensionChemotaxis(),
    )
    potts = PottsModel(
        cell,
        extracellular,
        border,
        volume,
        elongation,
        Adhesion(contact),
        field,
        chemotaxis,
        LocalConnectivity(),
        _moore_roles(),
    )
    return Model(spec, potts, cell, extracellular, border, field)
end

function initial_labels(spec::Profile=profile())
    labels = zeros(UInt64, spec.dimensions)
    grid_width = ceil(Int, sqrt(spec.cells))
    lower = ntuple(axis ->
        fld(spec.dimensions[axis] - spec.central_extent, 2) + 1, 2)
    spacing = spec.central_extent / grid_width
    radius = sqrt(spec.target_area_sites / pi)
    identity = 0
    for gy in 1:grid_width, gx in 1:grid_width
        identity == spec.cells && break
        identity += 1
        center = (
            lower[1] - 1 + (gx - 0.5) * spacing,
            lower[2] - 1 + (gy - 0.5) * spacing,
        )
        bound = ceil(Int, radius) + 1
        xbounds = (
            max(1, floor(Int, center[1]) - bound):
            min(spec.dimensions[1], ceil(Int, center[1]) + bound)
        )
        ybounds = (
            max(1, floor(Int, center[2]) - bound):
            min(spec.dimensions[2], ceil(Int, center[2]) + bound)
        )
        candidates = Tuple(
            CartesianIndex(x, y)
            for y in ybounds for x in xbounds
        )
        isempty(candidates) && throw(ArgumentError(
            "Merks profile is too small for its initial cells"))
        ranked = sort!(collect(candidates); by=site -> (
            sum((site[axis] - center[axis])^2 for axis in 1:2),
            Tuple(site),
        ))
        wanted = max(1, round(Int, spec.target_area_sites))
        length(ranked) >= wanted || throw(ArgumentError(
            "Merks initial disk contains fewer sites than its target area"))
        for site in ranked[1:wanted]
            iszero(labels[site]) || throw(ArgumentError(
                "Merks deterministic initial cells overlap"))
            labels[site] = UInt64(identity)
        end
    end
    return labels
end

function problem(
        definition::Model=model();
        labels=initial_labels(definition.profile),
        field_values=zeros(Float64, definition.profile.dimensions),
        tspan=(0, definition.profile.mcs))
    size(labels) == definition.profile.dimensions ||
        throw(ArgumentError("Merks labels do not match the profile domain"))
    size(field_values) == definition.profile.dimensions ||
        throw(ArgumentError("Merks field does not match the profile domain"))
    identities = Tuple(
        identity => definition.cell
        for identity in sort!(collect(Set(filter(!iszero, labels))))
    )
    return PottsProblem(
        definition.potts,
        CartesianDomain(
            definition.profile.dimensions;
            spacing=(1.0, 1.0),
            boundaries=(
                AxisBoundary(ClosedBoundary()),
                AxisBoundary(ClosedBoundary()),
            ),
        ),
        Layout(LabelledCells(labels, identities));
        fields=(definition.field => field_values,),
        capacity=max(length(identities), definition.profile.cells),
        tspan,
        seed=definition.profile.seed,
    )
end

problem(spec::Profile; kwargs...) = problem(model(spec); kwargs...)

function _labels(state)
    labels = zeros(UInt64, CorePotts.lattice_size(state))
    for site in eachindex(labels)
        owner = CorePotts.owner_at(state, site)
        labels[site] = CorePotts.is_cell_owner(owner) ?
            UInt64(CorePotts.value(CorePotts.cell_id(owner))) : UInt64(0)
    end
    return labels
end

function semantic_manifest(definition::Model=model())
    return (
        family=:Merks2006,
        semantic_version=string(SEMANTIC_VERSION),
        profile=definition.profile.identity,
        source_trace=definition.profile.source_trace,
        deviations=definition.profile.deviations,
        scientific_nonclaims=definition.profile.scientific_nonclaims,
        fingerprint=semantic_fingerprint(definition.potts).digest,
    )
end

function differential_from_v1(definition::Model=model())
    return (
        ownership=(
            from=:CorePotts,
            to=:PottsToolkit_ReferenceModels_Merks2006,
        ),
        managed_field_constructor=(
            from=:concrete_process_type,
            to=:managed_field_process,
        ),
        schema_access=(from=:representation_field, to=:typed_store_handles),
        integrator_access=(from=:representation_fields, to=:SciML_public_lifecycle),
        semantic_version=(from=1, to=2),
        checkpoint=(from=:v1_reader_retained, to=:explicit_v2_identity),
        preserved_parameters=(
            :target_area_sites,
            :target_length_sites,
            :temperature,
            :chemotaxis_gamma,
            :volume_strength,
            :source_length_strength,
            :secretion_rate,
            :diffusion,
            :decay,
        ),
        preserved_source_trace=true,
        intentional_changes=(
            :downstream_model_ownership,
            :public_lifecycle,
            :public_process_bigraph_authoring,
            :new_semantic_fingerprint,
        ),
    )
end

struct _CPMStep{M} <: ProcessBigraphs.AbstractStep
    definition::M
end

function ProcessBigraphs.ports(::_CPMStep)
    return (
        ProcessBigraphs.PortSpec(
            Array{UInt64,2}, :labels, :input;
            interval_behavior=:event_updated),
        ProcessBigraphs.PortSpec(
            Array{Float64,2}, :mcs_field, :input;
            interval_behavior=:event_updated),
        ProcessBigraphs.PortSpec(
            Array{UInt64,2}, :labels_out, :output;
            update_law=:replace),
    )
end

ProcessBigraphs.semantic_version(::_CPMStep) = string(SEMANTIC_VERSION)
ProcessBigraphs.semantic_parameters(step::_CPMStep) = (
    family=:Merks2006,
    source_doi=SOURCE_DOI,
    profile=step.definition.profile.identity,
    potts_fingerprint=semantic_fingerprint(step.definition.potts).digest,
)

function ProcessBigraphs.invoke(
        step::_CPMStep,
        inputs::ProcessBigraphs.PortView,
        context::ProcessBigraphs.InvocationContext)
    spec = step.definition.profile
    mod(context.end_time.tick, spec.subcycles_per_mcs) == 0 ||
        throw(ArgumentError(
            "Merks CPM runs only at complete field-subcycle boundaries"))
    target = Int(div(context.end_time.tick, spec.subcycles_per_mcs))
    experiment = problem(
        step.definition;
        labels=inputs[:labels],
        field_values=inputs[:mcs_field],
        tspan=(target - 1, target),
    )
    algorithm = SequentialCPM(temperature=spec.temperature)
    integrator = SciMLBase.init(experiment, algorithm)
    SciMLBase.step!(integrator)
    labels = _labels(CorePotts.logical_state(integrator))
    report = CorePotts.current_mcs_report(integrator)
    return ProcessBigraphs.InvocationResult((
        ProcessBigraphs.emit(
            context,
            :labels_out,
            ProcessBigraphs.ReplaceUpdate(),
            labels,
        ),
    ); diagnostics=(
        target_mcs=target,
        accepted_copies=report.accepted_copies,
    ))
end

struct _SecretionStep{T<:AbstractFloat} <: ProcessBigraphs.AbstractStep
    rate::T
end

function ProcessBigraphs.ports(::_SecretionStep)
    return (
        ProcessBigraphs.PortSpec(
            Array{UInt64,2}, :labels, :input;
            interval_behavior=:event_updated),
        ProcessBigraphs.PortSpec(
            Array{Float64,2}, :forcing, :output;
            update_law=:replace),
        ProcessBigraphs.PortSpec(
            Array{Float64,2}, :decay_weights, :output;
            update_law=:replace),
    )
end

ProcessBigraphs.semantic_version(::_SecretionStep) = string(SEMANTIC_VERSION)
ProcessBigraphs.semantic_parameters(step::_SecretionStep) = (
    family=:Merks2006,
    source_equation=6,
    secretion_rate=step.rate,
)

function ProcessBigraphs.invoke(
        step::_SecretionStep,
        inputs::ProcessBigraphs.PortView,
        context::ProcessBigraphs.InvocationContext)
    labels = inputs[:labels]
    forcing = map(label -> iszero(label) ? 0.0 : Float64(step.rate), labels)
    decay_weights = map(label -> iszero(label) ? 1.0 : 0.0, labels)
    return ProcessBigraphs.InvocationResult((
        ProcessBigraphs.emit(
            context,
            :forcing,
            ProcessBigraphs.ReplaceUpdate(),
            forcing,
        ),
        ProcessBigraphs.emit(
            context,
            :decay_weights,
            ProcessBigraphs.ReplaceUpdate(),
            decay_weights,
        ),
    ))
end

function field_declaration(
        spec::Profile=profile();
        initial_field=zeros(Float64, spec.dimensions))
    field_problem = ProcessBigraphs.BoundedCartesianFieldProblem(
        "merks-chemoattractant",
        initial_field;
        spacing=(2.0, 2.0),
        diffusion=spec.diffusion,
        decay=spec.decay,
        tick_duration=2.0,
        time_scale=ProcessBigraphs.TimeScale(2, 1, :second),
    )
    return ProcessBigraphs.sciml_field_declaration(
        field_problem,
        Tsit5();
        algorithm_id="ordinarydiffeq-tsit5",
        solver_options=(abstol=1.0e-9, reltol=1.0e-9),
    )
end

function composite(
        definition::Model=model();
        labels=initial_labels(definition.profile),
        declaration=field_declaration(definition.profile),
        initial_field=zeros(Float64, definition.profile.dimensions),
        resource_authorization=(
            backend=:cpu,
            precision=:float64,
            residency=:host,
        ),
        compile::Bool=true)
    spec = definition.profile
    size(labels) == spec.dimensions ||
        throw(ArgumentError("Merks labels do not match the profile"))
    scale = ProcessBigraphs.TimeScale(2, 1, :second)
    forcing = map(
        label -> iszero(label) ? 0.0 : spec.secretion_rate,
        labels,
    )
    decay_weights = map(label -> iszero(label) ? 1.0 : 0.0, labels)
    field_process = ProcessBigraphs.managed_field_process(
        declaration;
        resource_authorization,
        subcycles_per_mcs=spec.subcycles_per_mcs,
    )
    assembled = ProcessBigraphs.compose(
        :Merks2006;
        scale,
        profile=:reproducible,
    ) do system
        label_store = ProcessBigraphs.store!(
            system,
            :labels,
            ProcessBigraphs.LeafSchema(
                UInt64;
                shape=spec.dimensions,
                default=copy(labels),
                update_law=:replace,
                ontology="CPM cell identity",
            ),
        )
        field_store = ProcessBigraphs.store!(
            system,
            :field,
            ProcessBigraphs.LeafSchema(
                Float64;
                shape=spec.dimensions,
                default=copy(initial_field),
                update_law=:replace,
                units="concentration",
            ),
        )
        mcs_field_store = ProcessBigraphs.store!(
            system,
            :mcs_field,
            ProcessBigraphs.LeafSchema(
                Float64;
                shape=spec.dimensions,
                default=copy(initial_field),
                update_law=:replace,
                units="concentration",
            ),
        )
        forcing_store = ProcessBigraphs.store!(
            system,
            :forcing,
            ProcessBigraphs.LeafSchema(
                Float64;
                shape=spec.dimensions,
                default=forcing,
                update_law=:replace,
                units="concentration/second",
            ),
        )
        decay_store = ProcessBigraphs.store!(
            system,
            :decay_weights,
            ProcessBigraphs.LeafSchema(
                Float64;
                shape=spec.dimensions,
                default=decay_weights,
                update_law=:replace,
            ),
        )

        field = ProcessBigraphs.mount!(
            system, :field_solver, field_process)
        ProcessBigraphs.attach!(system, field, (
            field=field_store,
            forcing=forcing_store,
            decay_weights=decay_store,
            field_out=field_store,
            mcs_field=mcs_field_store,
        ))
        ProcessBigraphs.schedule!(
            system,
            field,
            ProcessBigraphs.Every(
                ProcessBigraphs.Duration(1, scale)),
        )

        cpm = ProcessBigraphs.mount!(
            system, :cellular_potts, _CPMStep(definition))
        ProcessBigraphs.attach!(system, cpm, (
            labels=label_store,
            mcs_field=mcs_field_store,
            labels_out=label_store,
        ))

        secretion = ProcessBigraphs.mount!(
            system,
            :secretion_mask,
            _SecretionStep(spec.secretion_rate),
        )
        ProcessBigraphs.attach!(system, secretion, (
            labels=label_store,
            forcing=forcing_store,
            decay_weights=decay_store,
        ))
        ProcessBigraphs.schedule!(
            system,
            secretion,
            ProcessBigraphs.After(cpm),
        )
        ProcessBigraphs.observable!(system, :labels, label_store)
        ProcessBigraphs.observable!(system, :field, field_store)
    end
    return compile ? ProcessBigraphs.compile(assembled) : assembled
end

composite(spec::Profile; kwargs...) = composite(model(spec); kwargs...)

const ObservationRecord = NamedTuple{
    (
        :mcs,
        :cell_count,
        :occupied_sites,
        :disconnected_cells,
        :field_mass,
        :field_minimum,
        :field_maximum,
    ),
    Tuple{Int,Int,Int,Int,Float64,Float64,Float64},
}

struct _Observer <: ProcessBigraphs.AbstractObserver
    subcycles_per_mcs::Int
end

ProcessBigraphs.observer_semantic_version(::_Observer) = string(SEMANTIC_VERSION)
ProcessBigraphs.observer_semantic_parameters(observer::_Observer) = (
    family=:Merks2006,
    subcycles_per_mcs=observer.subcycles_per_mcs,
    connectivity=:eight_neighbor_components,
)

function _observation_counts(labels)
    visited = falses(size(labels))
    observed = Set{UInt64}()
    disconnected = Set{UInt64}()
    frontier = CartesianIndex{2}[]
    occupied = 0
    offsets = (
        (-1, -1), (0, -1), (1, -1), (1, 0),
        (1, 1), (0, 1), (-1, 1), (-1, 0),
    )
    for site in CartesianIndices(labels)
        label = labels[site]
        iszero(label) && continue
        occupied += 1
        visited[site] && continue
        label in observed && push!(disconnected, label)
        push!(observed, label)
        push!(frontier, site)
        visited[site] = true
        while !isempty(frontier)
            current = pop!(frontier)
            for offset in offsets
                neighbor = current + CartesianIndex(offset)
                checkbounds(Bool, labels, neighbor) || continue
                if !visited[neighbor] && labels[neighbor] == label
                    visited[neighbor] = true
                    push!(frontier, neighbor)
                end
            end
        end
    end
    return length(observed), occupied, length(disconnected)
end

function ProcessBigraphs.observe(
        observer::_Observer,
        projection,
        context)
    labels = projection[ProcessBigraphs.path("labels")]
    field = projection[ProcessBigraphs.path("field")]
    cells, occupied, disconnected = _observation_counts(labels)
    return ProcessBigraphs.ObservationResult(ObservationRecord((
        Int(div(context.time.tick, observer.subcycles_per_mcs)),
        cells,
        occupied,
        disconnected,
        sum(field),
        minimum(field),
        maximum(field),
    )))
end

function observation_plan(spec::Profile=profile())
    scale = ProcessBigraphs.TimeScale(2, 1, :second)
    cadence = ProcessBigraphs.Duration(spec.subcycles_per_mcs, scale)
    observer = ProcessBigraphs.ObserverSpec(
        "merks-state-observer",
        _Observer(spec.subcycles_per_mcs),
        (
            ProcessBigraphs.path("labels"),
            ProcessBigraphs.path("field"),
        ),
        ProcessBigraphs.PeriodicObservationSchedule(cadence);
        record_schema=ProcessBigraphs.RecordSchema(
            ObservationRecord;
            identity="merks-state-observation-v2",
        ),
    )
    return ProcessBigraphs.ObservationPlan((observer,))
end

observation_plan(definition::Model) = observation_plan(definition.profile)

struct MigrationRequiredError <: Exception
    message::String
end
Base.showerror(io::IO, error::MigrationRequiredError) =
    print(io, error.message)

"""
Restore a Merks v2 ProcessBigraph checkpoint.

The runtime's fingerprint checks reject v1 bytes. `acknowledge_v1=true` does
not reinterpret old bytes; it produces an actionable migration error because
Phase 17 deliberately has no silent v1-as-v2 restoration.
"""
function restore_v2(
        checkpoint,
        definition::Model=model();
        acknowledge_v1::Bool=false)
    candidate = composite(definition)
    executor = ProcessBigraphs.SerialExecutor(
        root_seed=definition.profile.seed,
        observation_plan=observation_plan(definition),
    )
    try
        return ProcessBigraphs.restore(candidate, executor, checkpoint)
    catch error
        acknowledge_v1 || rethrow()
        throw(MigrationRequiredError(
            "Merks v1 checkpoint identity cannot be interpreted as semantic v2; " *
            "restart from an explicitly exported v1 logical state and record the migration"))
    end
end

end
