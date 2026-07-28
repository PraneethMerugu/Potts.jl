const MERKS_2006_ASSEMBLY_VERSION =
    "merks-vasculogenesis-reference-assembly-v1"

"""
Explicit ambiguity profile for parameters not numerically fixed by the primary
paper. Every value is part of the ProcessBigraphs semantic fingerprint.
"""
struct Merks2006AmbiguityProfile{T<:AbstractFloat}
    volume_strength::T
    source_length_strength::T
    field_boundary::Symbol
    connectivity_penalty_profile::Symbol
    placement_profile::Symbol
end

function Merks2006AmbiguityProfile(;
    volume_strength::Real=50.0,
    source_length_strength::Real=5.0,
    field_boundary::Symbol=:periodic_minimize_boundary_effects,
    connectivity_penalty_profile::Symbol=:hard_rejection,
    placement_profile::Symbol=:deterministic_seeded_nonoverlap,
)
    T = float(promote_type(
        typeof(volume_strength), typeof(source_length_strength)))
    volume = T(volume_strength)
    length_strength = T(source_length_strength)
    isfinite(volume) && volume >= zero(T) ||
        throw(ArgumentError(
            "Merks volume-strength profile must be finite and nonnegative"))
    isfinite(length_strength) && length_strength >= zero(T) ||
        throw(ArgumentError(
            "Merks length-strength profile must be finite and nonnegative"))
    field_boundary === :periodic_minimize_boundary_effects ||
        throw(ArgumentError(
            "the qualified Merks reference profile uses periodic field boundaries"))
    connectivity_penalty_profile === :hard_rejection ||
        throw(ArgumentError(
            "the qualified Merks connectivity profile is hard rejection"))
    placement_profile === :deterministic_seeded_nonoverlap ||
        throw(ArgumentError(
            "unsupported Merks placement ambiguity profile"))
    Merks2006AmbiguityProfile(
        volume,
        length_strength,
        field_boundary,
        connectivity_penalty_profile,
        placement_profile,
    )
end

struct Merks2006CPMStep{T<:AbstractFloat,P<:Merks2006AmbiguityProfile} <:
       ProcessBigraphs.AbstractStep
    subcycles_per_mcs::Int
    root_seed::UInt64
    target_area_sites::T
    target_length_sites::T
    temperature::T
    chemotaxis_gamma::T
    profile::P
end

function Merks2006CPMStep(;
    subcycles_per_mcs::Integer=15,
    root_seed::Integer=2006,
    target_area_sites::Real=100.0,
    target_length_sites::Real=50.0,
    temperature::Real=50.0,
    chemotaxis_gamma::Real=1000.0,
    profile::Merks2006AmbiguityProfile=Merks2006AmbiguityProfile(),
)
    0 < subcycles_per_mcs <= typemax(Int) ||
        throw(ArgumentError(
            "Merks CPM subcycle count must fit positive Int"))
    0 <= root_seed <= typemax(UInt64) ||
        throw(ArgumentError("Merks CPM seed must fit UInt64"))
    T = float(promote_type(
        typeof(target_area_sites),
        typeof(target_length_sites),
        typeof(temperature),
        typeof(chemotaxis_gamma),
        typeof(profile.volume_strength),
    ))
    values = T.(
        (target_area_sites, target_length_sites, temperature,
            chemotaxis_gamma))
    all(isfinite, values) && all(>(zero(T)), values) ||
        throw(ArgumentError(
            "Merks CPM physical parameters must be finite and positive"))
    normalized_profile = Merks2006AmbiguityProfile(
        volume_strength=T(profile.volume_strength),
        source_length_strength=T(profile.source_length_strength),
        field_boundary=profile.field_boundary,
        connectivity_penalty_profile=
            profile.connectivity_penalty_profile,
        placement_profile=profile.placement_profile,
    )
    Merks2006CPMStep(
        Int(subcycles_per_mcs),
        UInt64(root_seed),
        values...,
        normalized_profile,
    )
end

function ProcessBigraphs.ports(::Merks2006CPMStep)
    (
        ProcessBigraphs.PortSpec(
            Array{UInt32,2}, :labels, :input;
            interval_behavior=:event_updated),
        ProcessBigraphs.PortSpec(
            Array{Float64,2}, :mcs_field, :input;
            interval_behavior=:event_updated),
        ProcessBigraphs.PortSpec(
            Array{UInt32,2}, :labels_out, :output;
            update_law=:replace),
    )
end

ProcessBigraphs.semantic_version(::Merks2006CPMStep) = "1.0.0"
ProcessBigraphs.semantic_parameters(step::Merks2006CPMStep) = (
    contract_version=MERKS_2006_ASSEMBLY_VERSION,
    source_doi="10.1016/j.ydbio.2005.10.003",
    subcycles_per_mcs=step.subcycles_per_mcs,
    root_seed=step.root_seed,
    target_area_sites=step.target_area_sites,
    source_target_length_sites=step.target_length_sites,
    corepotts_target_major_axis_rms=step.target_length_sites / 4,
    temperature=step.temperature,
    source_chemotaxis_gamma=step.chemotaxis_gamma,
    corepotts_chemotaxis_log_bias=
        step.chemotaxis_gamma / step.temperature,
    contact_energies=(
        cell_cell=40.0,
        cell_ecm=20.0,
        cell_border=100.0,
    ),
    ambiguity_profile=(
        volume_strength=step.profile.volume_strength,
        source_length_strength=step.profile.source_length_strength,
        corepotts_elongation_strength=
            16 * step.profile.source_length_strength,
        field_boundary=step.profile.field_boundary,
        connectivity_penalty_profile=
            step.profile.connectivity_penalty_profile,
        placement_profile=step.profile.placement_profile,
    ),
)

function _merks_owners(labels::Array{UInt32,2})
    map(labels) do label
        iszero(label) ? MediumOwner(1) : CellOwner(label)
    end
end

function _merks_property_schema(
    volume::QuadraticVolumeHamiltonian,
    elongation::QuadraticElongationHamiltonian,
    chemotaxis::ChemotaxisDrive,
)
    coupling = chemotaxis.sensitivity
    property = property_key(coupling.property)
    requester = component_identity(chemotaxis)
    chemotaxis_schema = PropertySchema(PropertyDescriptor(
        property,
        Float64,
        ConstantInitializer(0.0);
        requester,
        division=CloneOnDivision(),
        transition=PreserveOnTransition(),
        kind=BiologicalProperty,
    ))
    merge_property_schemas(
        required_properties(volume),
        required_properties(elongation),
        chemotaxis_schema,
    )
end

function _merks_components(
    step::Merks2006CPMStep,
    field_values::Array{Float64,2},
    semantic_time::Float64,
    synchronization_epoch::UInt64,
)
    volume = QuadraticVolumeHamiltonian(number_type=Float64)
    elongation = QuadraticElongationHamiltonian(
        number_type=Float64,
        target_division=CloneOnDivision(),
    )
    contact_relation = merks_moore_relation(ContactRole())
    media = MediumTypeTable(
        MediumID(1) => CellTypeID(2),
        MediumID(2) => CellTypeID(3),
    )
    contact = UnorderedContactHamiltonian(
        [
            40.0 20.0 100.0
            20.0 0.0 0.0
            100.0 0.0 0.0
        ],
        media,
        contact_relation,
    )
    field = CellCenteredField(
        field_values;
        spacing=(1.0, 1.0),
        boundaries=ntuple(
            _ -> AxisFieldBoundary(PeriodicFieldBoundary()), 2),
        interpolation=NearestFieldInterpolation(),
        semantic_time,
        synchronization_epoch,
    )
    sensitivity = OwnerScalarCoupling(
        :chemotaxis_sensitivity,
        MediumID(1) => 0.0,
        MediumID(2) => 0.0;
        number_type=Float64,
    )
    chemotaxis = ChemotaxisDrive(
        field,
        sensitivity,
        LinearResponse(),
        ExtensionChemotaxis(),
    )
    connectivity = MerksLocalConnectivityConstraint()
    components = ScientificComponentSet(
        energies=(volume, contact, elongation),
        drives=(chemotaxis,),
        constraints=(connectivity,),
    )
    components, volume, elongation, chemotaxis
end

function _merks_run_mcs(
    step::Merks2006CPMStep,
    labels::Array{UInt32,2},
    field_values::Array{Float64,2},
    target_mcs::UInt64,
    semantic_time::Float64,
)
    size(labels) == size(field_values) ||
        throw(ArgumentError(
            "Merks CPM labels and chemoattractant field must align"))
    components, volume, elongation, chemotaxis = _merks_components(
        step, field_values, semantic_time, target_mcs)
    maximum_label = maximum(labels; init=UInt32(0))
    capacity = CellCapacity(max(Int(maximum_label), 1))
    cell_types = Dict(
        CellID(id) => CellTypeID(1)
        for id in UInt32(1):maximum_label
        if any(==(id), labels)
    )
    logical = LogicalPottsState(
        _merks_owners(labels),
        capacity;
        cell_types,
        medium_domains=(MediumID(1), MediumID(2)),
        property_schema=_merks_property_schema(
            volume, elongation, chemotaxis),
    )
    active = active_cell_ids(logical)
    property_values(logical, :target_volume)[value.(active)] .=
        step.target_area_sites
    property_values(logical, :volume_strength)[value.(active)] .=
        step.profile.volume_strength
    property_values(logical, :target_elongation)[value.(active)] .=
        step.target_length_sites / 4
    property_values(logical, :elongation_strength)[value.(active)] .=
        16 * step.profile.source_length_strength
    property_values(logical, :chemotaxis_sensitivity)[value.(active)] .=
        step.chemotaxis_gamma / step.temperature

    fixed = AxisBoundary(FixedExterior(MediumOwner(2)))
    domain = CartesianDomain(
        size(labels);
        spacing=(1.0, 1.0),
        boundaries=(fixed, fixed),
    )
    surface_relation = merks_moore_relation(SurfaceRole())
    moment_relation = merks_moore_relation(ConnectivityRole())
    moment_tracker = UnwrappedMomentTracker(
        moment_relation; number_type=Float64)
    scientific = compile_scientific_state(
        logical,
        domain,
        BoundaryMeasureTracker(
            BoundaryEdgeCount(), surface_relation);
        moment_tracker,
    )
    integrator = init_scientific(
        scientific,
        merks_moore_relation(ProposalRole()),
        components,
        SequentialCPM(temperature=step.temperature);
        seed=step.root_seed,
        plan=ExecutionPlan(KernelAbstractions.CPU()),
        moment_tracker,
    )
    target_mcs > 0 ||
        throw(ArgumentError("Merks CPM target MCS must be positive"))
    integrator.mcs = target_mcs - UInt64(1)
    perform_scientific_mcs!(integrator, integrator.algorithm)
    snapshot = logical_state(integrator)
    output = zeros(UInt32, size(labels))
    for site in eachindex(output)
        owner = owner_at(snapshot, site)
        @inbounds output[site] =
            is_cell_owner(owner) ? owner.value : UInt32(0)
    end
    output
end

function ProcessBigraphs.invoke(
    step::Merks2006CPMStep,
    inputs::ProcessBigraphs.PortView,
    context::ProcessBigraphs.InvocationContext,
)
    mod(context.end_time.tick, step.subcycles_per_mcs) == 0 ||
        throw(ArgumentError(
            "Merks CPM may run only at a complete 15-field-step boundary"))
    target_mcs = UInt64(
        div(context.end_time.tick, step.subcycles_per_mcs))
    labels = _merks_run_mcs(
        step,
        inputs[:labels],
        inputs[:mcs_field],
        target_mcs,
        Float64(ProcessBigraphs.physical_value(context.end_time)),
    )
    ProcessBigraphs.InvocationResult((
        ProcessBigraphs.emit(
            context,
            :labels_out,
            ProcessBigraphs.ReplaceUpdate(),
            labels,
        ),
    ); diagnostics=(mcs=target_mcs,))
end

struct Merks2006SecretionStep{T<:AbstractFloat} <:
       ProcessBigraphs.AbstractStep
    secretion_rate::T
end

function Merks2006SecretionStep(; secretion_rate::Real=1.8e-4)
    T = float(typeof(secretion_rate))
    rate = T(secretion_rate)
    isfinite(rate) && rate >= zero(T) ||
        throw(ArgumentError(
            "Merks secretion rate must be finite and nonnegative"))
    Merks2006SecretionStep(rate)
end

function ProcessBigraphs.ports(::Merks2006SecretionStep)
    (
        ProcessBigraphs.PortSpec(
            Array{UInt32,2}, :labels, :input;
            interval_behavior=:event_updated),
        ProcessBigraphs.PortSpec(
            Array{Float64,2}, :forcing, :output;
            update_law=:replace),
        ProcessBigraphs.PortSpec(
            Array{Float64,2}, :decay_weights, :output;
            update_law=:replace),
    )
end

ProcessBigraphs.semantic_version(::Merks2006SecretionStep) = "1.0.0"
ProcessBigraphs.semantic_parameters(step::Merks2006SecretionStep) = (
    contract_version=MERKS_2006_ASSEMBLY_VERSION,
    source_equation=6,
    secretion_rate=step.secretion_rate,
    secretion_support=:cell_sites,
    decay_support=:ecm_sites,
)

function ProcessBigraphs.invoke(
    step::Merks2006SecretionStep,
    inputs::ProcessBigraphs.PortView,
    context::ProcessBigraphs.InvocationContext,
)
    labels = inputs[:labels]
    forcing = map(label ->
        iszero(label) ? 0.0 : Float64(step.secretion_rate), labels)
    decay_weights = map(label ->
        iszero(label) ? 1.0 : 0.0, labels)
    ProcessBigraphs.InvocationResult((
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

const Merks2006ObservationRecord = NamedTuple{
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

struct Merks2006Observer <: ProcessBigraphs.AbstractObserver
    subcycles_per_mcs::Int
    function Merks2006Observer(subcycles_per_mcs::Integer=15)
        0 < subcycles_per_mcs <= typemax(Int) ||
            throw(ArgumentError(
                "Merks observer subcycle count must fit positive Int"))
        new(Int(subcycles_per_mcs))
    end
end

ProcessBigraphs.observer_semantic_version(::Merks2006Observer) = "1.0.0"
ProcessBigraphs.observer_semantic_parameters(observer::Merks2006Observer) = (
    contract_version=MERKS_2006_ASSEMBLY_VERSION,
    subcycles_per_mcs=observer.subcycles_per_mcs,
    connectivity=:eight_neighbor_components,
)

function _merks_observation_counts(labels::Array{UInt32,2})
    visited = falses(size(labels))
    observed_cells = Set{UInt32}()
    disconnected_cells = Set{UInt32}()
    frontier = CartesianIndex{2}[]
    occupied_sites = 0
    for site in CartesianIndices(labels)
        label = @inbounds labels[site]
        iszero(label) && continue
        occupied_sites += 1
        @inbounds visited[site] && continue
        label in observed_cells && push!(disconnected_cells, label)
        push!(observed_cells, label)
        push!(frontier, site)
        @inbounds visited[site] = true
        while !isempty(frontier)
            current = pop!(frontier)
            for offset in _MERKS_CLOCKWISE_OFFSETS
                neighbor = current + CartesianIndex(offset)
                checkbounds(Bool, labels, neighbor) || continue
                @inbounds if !visited[neighbor] &&
                        labels[neighbor] == label
                    visited[neighbor] = true
                    push!(frontier, neighbor)
                end
            end
        end
    end
    length(observed_cells), occupied_sites, length(disconnected_cells)
end

function ProcessBigraphs.observe(
    observer::Merks2006Observer,
    projection,
    context,
)
    labels = projection[ProcessBigraphs.path("labels")]
    field = projection[ProcessBigraphs.path("field")]
    size(labels) == size(field) ||
        throw(ArgumentError(
            "Merks observation labels and field must align"))
    cell_count, occupied_sites, disconnected_cells =
        _merks_observation_counts(labels)
    record = Merks2006ObservationRecord((
        Int(div(context.time.tick, observer.subcycles_per_mcs)),
        cell_count,
        occupied_sites,
        disconnected_cells,
        sum(field),
        minimum(field),
        maximum(field),
    ))
    ProcessBigraphs.ObservationResult(record)
end

"""
Read-only ProcessBigraphs observation plan for one record at every Merks MCS
boundary. The record is deliberately small and checkpoint/restart stable.
"""
function merks2006_observation_plan(
    time_scale::ProcessBigraphs.TimeScale=
        ProcessBigraphs.TimeScale(2, 1, :second);
    subcycles_per_mcs::Integer=15,
)
    observer = Merks2006Observer(subcycles_per_mcs)
    cadence = ProcessBigraphs.Duration(
        observer.subcycles_per_mcs, time_scale)
    spec = ProcessBigraphs.ObserverSpec(
        "merks-state-observer",
        observer,
        (
            ProcessBigraphs.path("labels"),
            ProcessBigraphs.path("field"),
        ),
        ProcessBigraphs.PeriodicObservationSchedule(cadence);
        record_schema=ProcessBigraphs.RecordSchema(
            Merks2006ObservationRecord;
            identity="merks-state-observation-v1",
        ),
    )
    ProcessBigraphs.ObservationPlan((spec,))
end

function merks2006_initial_labels(;
    shape::NTuple{2,<:Integer}=(500, 500),
    cells::Integer=282,
    central_extent::Integer=333,
    target_area_sites::Real=100.0,
    seed::Integer=2006,
)
    dimensions = (Int(shape[1]), Int(shape[2]))
    all(>(0), dimensions) ||
        throw(ArgumentError("Merks startup dimensions must be positive"))
    0 < cells <= typemax(UInt32) ||
        throw(ArgumentError("Merks startup cell count must fit UInt32"))
    0 < central_extent <= minimum(dimensions) ||
        throw(ArgumentError(
            "Merks central placement extent must fit the lattice"))
    isfinite(target_area_sites) && target_area_sites > 0 ||
        throw(ArgumentError(
            "Merks target area must be finite and positive"))
    0 <= seed <= typemax(UInt64) ||
        throw(ArgumentError("Merks placement seed must fit UInt64"))
    lower = ntuple(axis ->
        fld(dimensions[axis] - Int(central_extent), 2) + 1, 2)
    upper = ntuple(axis -> lower[axis] + Int(central_extent) - 1, 2)
    eligible = falses(dimensions)
    for site in CartesianIndices(eligible)
        eligible[site] =
            lower[1] <= site[1] <= upper[1] &&
            lower[2] <= site[2] <= upper[2]
    end
    declarations = [
        ProvisionalCellID(index) => CellTypeID(1)
        for index in 1:Int(cells)
    ]
    layout = SequentialRejectionPlacement(
        declarations,
        LatticeBall(sqrt(float(target_area_sites) / pi)),
        eligible;
        periodic=(false, false),
        attempt_limit=256,
        operation=0x606,
    )
    initialized = finalize_initial_state(
        dimensions,
        layout;
        capacity=CellCapacity(cells),
        medium_domains=(MediumID(1), MediumID(2)),
        seed,
    )
    logical = logical_state(initialized)
    labels = zeros(UInt32, dimensions)
    for site in eachindex(labels)
        owner = owner_at(logical, site)
        @inbounds labels[site] =
            is_cell_owner(owner) ? owner.value : UInt32(0)
    end
    labels
end

"""
Compile the Merks reference assembly around any qualified field-engine
declaration. ProcessBigraphs owns the two-second schedule and all publication
boundaries; the supplied adapter owns numerical field computation.
"""
function merks2006_composite(
    labels::Array{UInt32,2},
    field_declaration::ProcessBigraphs.EngineDeclaration;
    time_scale::ProcessBigraphs.TimeScale=
        ProcessBigraphs.TimeScale(2, 1, :second),
    resource_authorization::NamedTuple=(
        backend=:cpu,
        precision=:float64,
        residency=:host,
    ),
    subcycles_per_mcs::Integer=15,
    root_seed::Integer=2006,
    profile::Merks2006AmbiguityProfile=Merks2006AmbiguityProfile(),
    initial_field=zeros(Float64, size(labels)),
)
    size(initial_field) == size(labels) &&
        eltype(initial_field) === Float64 ||
        throw(ArgumentError(
            "Merks initial field must be an aligned Float64 array"))
    forcing = map(label ->
        iszero(label) ? 0.0 : 1.8e-4, labels)
    decay_weights = map(label ->
        iszero(label) ? 1.0 : 0.0, labels)
    schema = ProcessBigraphs.BranchSchema(
        labels=ProcessBigraphs.LeafSchema(
            UInt32;
            shape=size(labels),
            default=copy(labels),
            update_law=:replace,
            owner=:shared,
            ontology="CPM cell identity",
        ),
        field=ProcessBigraphs.LeafSchema(
            Float64;
            shape=size(labels),
            default=copy(initial_field),
            update_law=:replace,
            owner=:shared,
            units="concentration",
        ),
        mcs_field=ProcessBigraphs.LeafSchema(
            Float64;
            shape=size(labels),
            default=copy(initial_field),
            update_law=:replace,
            owner=:shared,
            units="concentration",
        ),
        forcing=ProcessBigraphs.LeafSchema(
            Float64;
            shape=size(labels),
            default=forcing,
            update_law=:replace,
            owner=:shared,
            units="concentration/second",
        ),
        decay_weights=ProcessBigraphs.LeafSchema(
            Float64;
            shape=size(labels),
            default=decay_weights,
            update_law=:replace,
            owner=:shared,
        ),
    )
    field_process = ProcessBigraphs.ManagedFieldAdvanceProcess(
        field_declaration;
        resource_authorization,
        subcycles_per_mcs,
    )
    field = ProcessBigraphs.ProcessDeclaration(
        "merks-field",
        field_process,
        ProcessBigraphs.FixedSchedule(
            ProcessBigraphs.Duration(1, time_scale)),
    )
    cpm = ProcessBigraphs.StepDeclaration(
        "merks-cpm",
        Merks2006CPMStep(
            ;
            subcycles_per_mcs,
            root_seed,
            profile,
        ),
    )
    secretion = ProcessBigraphs.StepDeclaration(
        "merks-secretion-mask",
        Merks2006SecretionStep();
        dependencies=("merks-cpm",),
    )
    bindings = (
        ProcessBigraphs.PortBinding(
            "merks-field", :field, ProcessBigraphs.path("field")),
        ProcessBigraphs.PortBinding(
            "merks-field", :forcing, ProcessBigraphs.path("forcing")),
        ProcessBigraphs.PortBinding(
            "merks-field", :decay_weights,
            ProcessBigraphs.path("decay_weights")),
        ProcessBigraphs.PortBinding(
            "merks-field", :field_out, ProcessBigraphs.path("field")),
        ProcessBigraphs.PortBinding(
            "merks-field", :mcs_field,
            ProcessBigraphs.path("mcs_field")),
        ProcessBigraphs.PortBinding(
            "merks-cpm", :labels, ProcessBigraphs.path("labels")),
        ProcessBigraphs.PortBinding(
            "merks-cpm", :mcs_field,
            ProcessBigraphs.path("mcs_field")),
        ProcessBigraphs.PortBinding(
            "merks-cpm", :labels_out, ProcessBigraphs.path("labels")),
        ProcessBigraphs.PortBinding(
            "merks-secretion-mask", :labels,
            ProcessBigraphs.path("labels")),
        ProcessBigraphs.PortBinding(
            "merks-secretion-mask", :forcing,
            ProcessBigraphs.path("forcing")),
        ProcessBigraphs.PortBinding(
            "merks-secretion-mask", :decay_weights,
            ProcessBigraphs.path("decay_weights")),
    )
    ProcessBigraphs.compile_composite(
        ProcessBigraphs.StaticComposite(
            schema,
            Dict(),
            time_scale;
            processes=(field,),
            steps=(cpm, secretion),
            bindings,
        ))
end

function merks2006_native_composite(
    labels::Array{UInt32,2};
    time_scale::ProcessBigraphs.TimeScale=
        ProcessBigraphs.TimeScale(2, 1, :second),
    initial_field=zeros(Float64, size(labels)),
    subcycles_per_mcs::Integer=15,
    root_seed::Integer=2006,
    profile::Merks2006AmbiguityProfile=Merks2006AmbiguityProfile(),
)
    adapter = CorePottsNativeFieldAdapter(
        :merks_chemoattractant,
        initial_field;
        geometry=NativeFieldGeometry(
            size(labels);
            spacing=(2.0, 2.0),
            number_type=Float64,
        ),
        diffusion=0.1,
        decay=1.8e-4,
        decay_weights=ones(Float64, size(labels)),
        tick_duration=2.0,
        substeps_per_tick=1,
        time_scale,
    )
    declaration = corepotts_native_field_declaration(
        "merks-native-field", adapter)
    merks2006_composite(
        labels,
        declaration;
        time_scale,
        subcycles_per_mcs,
        root_seed,
        profile,
        initial_field,
    )
end
