abstract type AbstractObservationPhase end
struct CompletedMCS <: AbstractObservationPhase end
struct NamedPhaseSnapshot <: AbstractObservationPhase
    phase::Symbol
end

abstract type AbstractObservationFailurePolicy end
struct RequiredObservation <: AbstractObservationFailurePolicy end
struct BestEffortTelemetry <: AbstractObservationFailurePolicy end

abstract type AbstractObservationSchema end
struct RecordSchema <: AbstractObservationSchema
    name::Symbol
    version::VersionNumber
end

struct PhaseObservation{O, P <: AbstractObservationPhase, S,
        R <: AbstractObservationSchema, F <: AbstractObservationFailurePolicy}
    name::Symbol
    observable::O
    phase::P
    schedule::S
    schema::R
    failure::F
    version::VersionNumber
end
function PhaseObservation(name::Symbol, observable;
        phase::AbstractObservationPhase = CompletedMCS(),
        schedule = EveryMCS(),
        schema::AbstractObservationSchema = RecordSchema(name, v"1.0.0"),
        failure::AbstractObservationFailurePolicy = RequiredObservation(),
        version::VersionNumber = CONTINUOUS_SYSTEM_CONTRACT_VERSION)
    return PhaseObservation(name, observable, phase, schedule,
        schema, failure, version)
end
component_identity(observation::PhaseObservation) =
    ComponentIdentity(observation.name, observation.version, :paper_observation)
component_semantic_data(observation::PhaseObservation) = (
    observable = _semantic_observable(observation.observable),
    phase = observation.phase, schedule = observation.schedule,
    schema = observation.schema, failure = observation.failure)

_semantic_observable(law::DirectLaw) =
    (name = law.name, version = law.version)
function _semantic_observable(observable)
    hasmethod(component_identity, Tuple{typeof(observable)}) ||
        throw(ArgumentError(
            "observation laws require DirectLaw or component identity"))
    identity = component_identity(observable)
    return (key = identity.key, version = identity.version,
        category = identity.category)
end

struct PaperObservationRecord{P <: AbstractObservationPhase,
        S <: AbstractObservationSchema, V}
    observation::Symbol
    mcs::UInt64
    publication_epoch::UInt64
    phase::P
    schema::S
    value::V
end

struct ObservationFailureRecord
    observation::Symbol
    mcs::UInt64
    error_type::Symbol
    message::String
end

@inline function _next_observation_epoch!(
        state::CoupledObservationState, name::Symbol)
    epoch = get(
        state.publication_epochs, name, UInt64(0)) + UInt64(1)
    state.publication_epochs[name] = epoch
    return epoch
end

_observation_requires_logical_snapshot(::Any) = true
_observation_requires_logical_snapshot(::ActivitySummary) = false
_is_bounded_native_observation(::Any) = false

const CELL_TABLE_OBSERVATION_CAPACITY = UInt32(1)
const CELL_TABLE_OBSERVATION_UNTRACKED = UInt32(2)
const CELL_TABLE_OBSERVATION_INVALID_VOLUME = UInt32(3)
const CELL_TABLE_OBSERVATION_NONFINITE_CENTER = UInt32(4)
const CELL_TABLE_OBSERVATION_NONFINITE_PROPERTY = UInt32(5)

struct BoundedCellTableWorkspace{
        I <: AbstractVector{UInt32},
        G <: AbstractVector{UInt64},
        A <: AbstractVector{UInt8},
        X <: Tuple,
        C <: Tuple}
    cell_id::I
    cell_generation::G
    cell_type::I
    present::A
    coordinates::X
    columns::C
    row_count::I
    failure_key::I
end

function BoundedCellTableWorkspace(
        core, moments::UnwrappedMomentStorage,
        source_columns::Tuple, cell_capacity::Integer)
    cell_capacity > 0 || throw(ArgumentError(
        "bounded cell-table cell capacity must be positive"))
    cell_capacity <= Int(_COUPLED_PROCESS_MAX_CELL) ||
        throw(ArgumentError(
            "bounded cell-table capacity exceeds packed failure-key capacity"))
    cell_id = similar(core.cell_types, UInt32, cell_capacity)
    generation = similar(core.generations, UInt64, cell_capacity)
    cell_type = similar(core.cell_types, UInt32, cell_capacity)
    present = similar(core.active, UInt8, cell_capacity)
    coordinates = map(prototype ->
        similar(prototype, eltype(prototype), cell_capacity),
        moments.coordinate_sums)
    columns = map(column ->
        similar(column, eltype(column), cell_capacity), source_columns)
    row_count = similar(core.cell_types, UInt32, 1)
    failure_key = similar(core.cell_types, UInt32, 1)
    for array in (
            cell_id, generation, cell_type, present,
            coordinates..., columns..., row_count)
        fill!(array, zero(eltype(array)))
    end
    failure_key[1] = _COUPLED_PROCESS_FAILURE_SENTINEL
    return BoundedCellTableWorkspace(
        cell_id, generation, cell_type, present,
        coordinates, columns,
        row_count, failure_key)
end

function Adapt.adapt_structure(
        to, workspace::BoundedCellTableWorkspace)
    return BoundedCellTableWorkspace(
        Adapt.adapt(to, workspace.cell_id),
        Adapt.adapt(to, workspace.cell_generation),
        Adapt.adapt(to, workspace.cell_type),
        Adapt.adapt(to, workspace.present),
        map(coordinate ->
            Adapt.adapt(to, coordinate),
            workspace.coordinates),
        map(column -> Adapt.adapt(to, column), workspace.columns),
        Adapt.adapt(to, workspace.row_count),
        Adapt.adapt(to, workspace.failure_key))
end

bounded_cell_table_workspace_bytes(
    workspace::BoundedCellTableWorkspace) =
    sum(_array_bytes, (
        workspace.cell_id, workspace.cell_generation,
        workspace.cell_type, workspace.present,
        workspace.coordinates...,
        workspace.columns..., workspace.row_count,
        workspace.failure_key); init = 0)

struct BoundedCellTableObservation{
        B <: NamedTuple,
        N <: Tuple,
        W <: BoundedCellTableWorkspace}
    name::Symbol
    bindings::B
    coordinate_names::N
    workspace::W
    schema_fingerprint::NTuple{32, UInt8}
    version::VersionNumber
end

_bounded_observation_workspace_bytes(
    observation::BoundedCellTableObservation) =
    bounded_cell_table_workspace_bytes(observation.workspace)

function BoundedCellTableObservation(
        name::Symbol, state::CompiledScientificState;
        bindings::NamedTuple,
        coordinate_names = nothing,
        cell_capacity::Integer =
            length(state.potts.storage.active),
        version::VersionNumber =
            CONTINUOUS_SYSTEM_CONTRACT_VERSION)
    isempty(String(name)) && throw(ArgumentError(
        "bounded cell-table observation identity must not be empty"))
    isempty(bindings) && throw(ArgumentError(
        "bounded cell-table observation requires at least one property binding"))
    output_names = propertynames(bindings)
    source_names = Tuple(bindings)
    all(name -> name isa Symbol, source_names) ||
        throw(ArgumentError(
            "bounded cell-table sources must be property symbols"))
    execution = scientific_execution(state)
    moments = execution.trackers.moments
    moments isa UnwrappedMomentStorage || throw(ArgumentError(
        "bounded cell-table observation requires unwrapped moments"))
    dimensions = length(moments.coordinate_sums)
    resolved_coordinate_names = coordinate_names === nothing ?
        _default_cell_table_coordinate_names(dimensions) :
        Tuple(coordinate_names)
    length(resolved_coordinate_names) == dimensions ||
        throw(DimensionMismatch(
            "bounded cell-table coordinate names must match the tracked dimension"))
    all(name -> name isa Symbol, resolved_coordinate_names) ||
        throw(ArgumentError(
            "bounded cell-table coordinate names must be symbols"))
    names = (
        :cell_id, resolved_coordinate_names..., output_names...)
    length(unique(names)) == length(names) ||
        throw(ArgumentError(
            "bounded cell-table source column names must be unique"))
    source_columns = map(
        key -> getproperty(execution.core.properties, key),
        source_names)
    capacity = length(execution.core.active)
    all(column -> column isa AbstractVector &&
            eltype(column) <: Real &&
            length(column) == capacity,
        source_columns) || throw(ArgumentError(
        "bounded cell-table properties must be equal-capacity real vectors"))
    workspace = BoundedCellTableWorkspace(
        execution.core, moments, source_columns, cell_capacity)
    fingerprint = _canonical_digest(
        name, version, names, bindings,
        :ascending_persistent_cell_identity,
        :typed_generation_envelope)
    return BoundedCellTableObservation(
        name, bindings, resolved_coordinate_names,
        workspace, fingerprint, version)
end

function _default_cell_table_coordinate_names(
        dimensions::Integer)
    dimensions > 0 || throw(ArgumentError(
        "bounded cell-table observations require at least one coordinate"))
    conventional = (:x, :y, :z)
    return ntuple(index -> index <= length(conventional) ?
        conventional[index] : Symbol(:coordinate_, index),
        dimensions)
end

function Adapt.adapt_structure(
        to, observation::BoundedCellTableObservation)
    return BoundedCellTableObservation(
        observation.name, observation.bindings,
        observation.coordinate_names,
        Adapt.adapt(to, observation.workspace),
        observation.schema_fingerprint,
        observation.version)
end

component_identity(observation::BoundedCellTableObservation) =
    ComponentIdentity(
        observation.name, observation.version,
        :bounded_cell_table_observation)
component_semantic_data(
        observation::BoundedCellTableObservation) = (
    bindings = observation.bindings,
    coordinate_names = observation.coordinate_names,
    cell_capacity = length(observation.workspace.present),
    ordering = :ascending_persistent_cell_identity,
    inactive_slots = :excluded,
)

_observation_requires_logical_snapshot(
    ::BoundedCellTableObservation) = false
_is_bounded_native_observation(
    ::BoundedCellTableObservation) = true

@inline function _cell_table_source_columns(
        core, observation::BoundedCellTableObservation)
    return map(
        key -> getproperty(core.properties, key),
        Tuple(observation.bindings))
end

@inline _pack_cell_table_columns!(
    ::Tuple{}, ::Tuple{}, cell) = true
@inline function _pack_cell_table_columns!(
        outputs::Tuple, inputs::Tuple, cell)
    value = @inbounds first(inputs)[cell]
    isfinite(value) || return false
    @inbounds first(outputs)[cell] = value
    return _pack_cell_table_columns!(
        Base.tail(outputs), Base.tail(inputs), cell)
end

@inline _pack_cell_table_coordinates!(
    ::Tuple{}, ::Tuple{}, cell, inverse_volume) = true
@inline function _pack_cell_table_coordinates!(
        outputs::Tuple, sums::Tuple, cell,
        inverse_volume)
    value = @inbounds first(sums)[cell] * inverse_volume
    isfinite(value) || return false
    @inbounds first(outputs)[cell] = value
    return _pack_cell_table_coordinates!(
        Base.tail(outputs), Base.tail(sums),
        cell, inverse_volume)
end

@inline function _record_cell_table_failure!(
        failure_key, code, cell)
    key = _coupled_process_failure_key(UInt32(code), cell)
    Atomix.@atomic min(failure_key[1], key)
    return nothing
end

@kernel function _initialize_bounded_cell_table!(
        present, row_count, failure_key)
    row = @index(Global, Linear)
    @inbounds begin
        present[row] = UInt8(0)
        if row == 1
            row_count[1] = UInt32(0)
            failure_key[1] =
                _COUPLED_PROCESS_FAILURE_SENTINEL
        end
    end
end

@kernel function _pack_bounded_cell_table!(
        cell_id, cell_generation, cell_type, present,
        output_coordinates, output_columns,
        input_columns, active, generations, types,
        finite_volumes, tracked, coordinate_sums,
        row_count, failure_key)
    cell = @index(Global, Linear)
    @inbounds if active[cell] != UInt8(0)
        if cell > length(present)
            _record_cell_table_failure!(
                failure_key,
                CELL_TABLE_OBSERVATION_CAPACITY, cell)
        elseif tracked[cell] == UInt8(0)
            _record_cell_table_failure!(
                failure_key,
                CELL_TABLE_OBSERVATION_UNTRACKED, cell)
        elseif finite_volumes[cell] <= Int32(0)
            _record_cell_table_failure!(
                failure_key,
                CELL_TABLE_OBSERVATION_INVALID_VOLUME, cell)
        else
            T = eltype(first(output_coordinates))
            inverse_volume = inv(T(finite_volumes[cell]))
            if !_pack_cell_table_coordinates!(
                    output_coordinates, coordinate_sums,
                    cell, inverse_volume)
                _record_cell_table_failure!(
                    failure_key,
                    CELL_TABLE_OBSERVATION_NONFINITE_CENTER,
                    cell)
            elseif !_pack_cell_table_columns!(
                    output_columns, input_columns, cell)
                _record_cell_table_failure!(
                    failure_key,
                    CELL_TABLE_OBSERVATION_NONFINITE_PROPERTY,
                    cell)
            else
                cell_id[cell] = UInt32(cell)
                cell_generation[cell] = generations[cell]
                cell_type[cell] = types[cell]
                present[cell] = UInt8(1)
                Atomix.@atomic row_count[1] += UInt32(1)
            end
        end
    end
end

struct BoundedCellTablePublication{
        I <: AbstractVector{UInt32},
        G <: AbstractVector{UInt64},
        X <: NamedTuple,
        C <: NamedTuple,
        F}
    target_mcs::UInt64
    source_mcs::UInt64
    publication_epoch::UInt64
    model_fingerprint::F
    profile_identity::Symbol
    semantic_seed::UInt64
    active_row_count::UInt32
    capacity::UInt32
    schema_fingerprint::NTuple{32, UInt8}
    cell_id::I
    cell_generation::G
    cell_type::I
    coordinates::X
    columns::C
end

function cell_table_columns(
        publication::BoundedCellTablePublication)
    return merge(
        (cell_id = publication.cell_id,),
        publication.coordinates,
        publication.columns)
end

function _bounded_cell_table_backend_valid(
        plan::ExecutionPlan, execution,
        observation::BoundedCellTableObservation,
        input_columns::Tuple)
    workspace = observation.workspace
    moments = execution.trackers.moments
    arrays = (
        execution.core.active, execution.core.generations,
        execution.core.cell_types,
        execution.trackers.finite_volumes,
        moments.tracked, moments.coordinate_sums...,
        input_columns..., workspace.cell_id,
        workspace.cell_generation, workspace.cell_type,
        workspace.present, workspace.coordinates...,
        workspace.columns...,
        workspace.row_count, workspace.failure_key)
    return all(array -> array isa AbstractArray &&
        isbitstype(eltype(array)) &&
        isequal(
            KernelAbstractions.get_backend(array),
            plan.backend), arrays)
end

function _execute_bounded_cell_table_pack!(
        plan::ExecutionPlan,
        scientific::CompiledScientificState,
        observation::BoundedCellTableObservation)
    execution = scientific_execution(scientific)
    moments = execution.trackers.moments
    moments isa UnwrappedMomentStorage || throw(ArgumentError(
        "bounded cell-table execution requires unwrapped moments"))
    input_columns =
        _cell_table_source_columns(execution.core, observation)
    _bounded_cell_table_backend_valid(
        plan, execution, observation, input_columns) ||
        throw(ArgumentError(
            "bounded cell-table storage has a backend mismatch"))
    capacity = length(execution.core.active)
    all(==(capacity), map(length, input_columns)) ||
        throw(DimensionMismatch(
            "bounded cell-table input capacities differ"))
    workspace = observation.workspace
    cell_capacity = length(workspace.present)
    all(==(cell_capacity), map(length, (
        workspace.cell_id, workspace.cell_generation,
        workspace.cell_type, workspace.coordinates...,
        workspace.columns...))) ||
        throw(DimensionMismatch(
            "bounded cell-table output capacities differ"))
    initialize = _execution_kernel(
        plan, _initialize_bounded_cell_table!,
        cell_capacity)
    launch!(plan, initialize,
        workspace.present, workspace.row_count,
        workspace.failure_key; ndrange = cell_capacity)
    pack = _execution_kernel(
        plan, _pack_bounded_cell_table!, capacity)
    launch!(plan, pack,
        workspace.cell_id, workspace.cell_generation,
        workspace.cell_type, workspace.present,
        workspace.coordinates,
        workspace.columns, input_columns,
        execution.core.active, execution.core.generations,
        execution.core.cell_types,
        execution.trackers.finite_volumes,
        moments.tracked, moments.coordinate_sums,
        workspace.row_count, workspace.failure_key;
        ndrange = capacity)
    synchronize_observation!(plan)
    if !(plan.backend isa KernelAbstractions.CPU)
        record_transfer!(plan, :device_to_host)
    end
    key = only(Adapt.adapt(
        Array, workspace.failure_key))
    key == _COUPLED_PROCESS_FAILURE_SENTINEL ||
        throw(ArgumentError(
            "bounded cell-table observation failed with status $(_coupled_process_failure_code(key)) at cell $(_coupled_process_failing_cell(key))"))
    return observation
end

function _publication_array(
        plan::ExecutionPlan, array::AbstractArray)
    if !(plan.backend isa KernelAbstractions.CPU)
        record_transfer!(plan, :device_to_host)
    end
    return copy(Adapt.adapt(Array, array))
end

function _materialize_bounded_cell_table(
        integrator::CoupledIntegrator,
        observation::BoundedCellTableObservation,
        target_mcs::UInt64, epoch::UInt64)
    plan = integrator.potts.plan
    workspace = observation.workspace
    present = _publication_array(plan, workspace.present)
    indices = findall(!iszero, present)
    count = UInt32(length(indices))
    device_count = only(_publication_array(
        plan, workspace.row_count))
    count == device_count || throw(ArgumentError(
        "bounded cell-table row count disagrees with packed rows"))
    compact(array) = _publication_array(plan, array)[indices]
    output_names = propertynames(observation.bindings)
    columns = NamedTuple{output_names}(
        map(compact, workspace.columns))
    coordinates = NamedTuple{
        observation.coordinate_names}(
        map(compact, workspace.coordinates))
    profile = Symbol(nameof(
        typeof(integrator.potts.plan.capabilities.family)))
    return BoundedCellTablePublication(
        target_mcs, target_mcs - UInt64(1), epoch,
        coupled_model_fingerprint(integrator),
        profile, integrator.potts.seed, count,
        UInt32(length(workspace.present)),
        observation.schema_fingerprint,
        compact(workspace.cell_id),
        compact(workspace.cell_generation),
        compact(workspace.cell_type),
        coordinates,
        columns)
end

struct LosslessOwnershipSnapshot
    name::Symbol
    maximum_sites::UInt64
    maximum_cells::UInt32
    schema_fingerprint::NTuple{32, UInt8}
    version::VersionNumber
end

function LosslessOwnershipSnapshot(
        name::Symbol, state::CompiledScientificState;
        maximum_sites::Integer =
            length(state.potts.storage.ownership.tags),
        maximum_cells::Integer =
            length(state.potts.storage.active),
        version::VersionNumber =
            CONTINUOUS_SYSTEM_CONTRACT_VERSION)
    isempty(String(name)) && throw(ArgumentError(
        "lossless ownership snapshot identity must not be empty"))
    maximum_sites > 0 || throw(ArgumentError(
        "lossless ownership snapshot site capacity must be positive"))
    maximum_cells > 0 || throw(ArgumentError(
        "lossless ownership snapshot cell capacity must be positive"))
    maximum_sites <= typemax(UInt64) || throw(ArgumentError(
        "lossless ownership snapshot site capacity exceeds UInt64"))
    maximum_cells <= typemax(UInt32) || throw(ArgumentError(
        "lossless ownership snapshot cell capacity exceeds UInt32"))
    fingerprint = _canonical_digest(
        name, version, :canonical_linear_site_order,
        :owner_tag_and_identity, :active_slot_generation_type,
        UInt64(maximum_sites), UInt32(maximum_cells))
    return LosslessOwnershipSnapshot(
        name, UInt64(maximum_sites), UInt32(maximum_cells),
        fingerprint, version)
end

component_identity(observation::LosslessOwnershipSnapshot) =
    ComponentIdentity(
        observation.name, observation.version,
        :lossless_ownership_snapshot)
component_semantic_data(
        observation::LosslessOwnershipSnapshot) = (
    maximum_sites = observation.maximum_sites,
    maximum_cells = observation.maximum_cells,
    ordering = :canonical_linear_site,
    payload = :lossless_owner_and_cell_identity,
)

_observation_requires_logical_snapshot(
    ::LosslessOwnershipSnapshot) = false
_is_bounded_native_observation(
    ::LosslessOwnershipSnapshot) = true

struct LosslessOwnershipPublication{
        O <: AbstractArray{UInt8},
        I <: AbstractArray{UInt32},
        A <: AbstractVector{UInt8},
        G <: AbstractVector{UInt64},
        C <: AbstractVector{UInt32},
        D, F}
    target_mcs::UInt64
    source_mcs::UInt64
    publication_epoch::UInt64
    model_fingerprint::F
    profile_identity::Symbol
    semantic_seed::UInt64
    schema_fingerprint::NTuple{32, UInt8}
    domain::D
    owner_tags::O
    owner_ids::I
    active::A
    cell_generations::G
    cell_types::C
end

function _domain_publication_metadata(
        domain::CompiledCartesianDomain)
    descriptor = domain.descriptor
    return (
        dims = Tuple(Int.(descriptor.dims)),
        spacing = Tuple(descriptor.spacing),
        boundaries = map(axis -> (
            negative = _boundary_semantics(axis.negative),
            positive = _boundary_semantics(axis.positive),
        ), descriptor.boundaries),
    )
end

function _materialize_lossless_ownership(
        integrator::CoupledIntegrator,
        observation::LosslessOwnershipSnapshot,
        target_mcs::UInt64, epoch::UInt64)
    state = integrator.potts.state
    core = state.potts.storage
    site_count = length(core.ownership.tags)
    cell_count = length(core.active)
    UInt64(site_count) <= observation.maximum_sites ||
        throw(ArgumentError(
            "lossless ownership snapshot site capacity exceeded"))
    UInt32(cell_count) <= observation.maximum_cells ||
        throw(ArgumentError(
            "lossless ownership snapshot cell capacity exceeded"))
    arrays = (
        core.ownership.tags, core.ownership.ids,
        core.active, core.generations, core.cell_types)
    all(array -> isequal(
            KernelAbstractions.get_backend(array),
            integrator.potts.plan.backend), arrays) ||
        throw(ArgumentError(
            "lossless ownership snapshot storage has a backend mismatch"))
    synchronize_observation!(integrator.potts.plan)
    profile = Symbol(nameof(typeof(
        integrator.potts.plan.capabilities.family)))
    return LosslessOwnershipPublication(
        target_mcs, target_mcs - UInt64(1), epoch,
        coupled_model_fingerprint(integrator), profile,
        integrator.potts.seed,
        observation.schema_fingerprint,
        _domain_publication_metadata(state.domain),
        _publication_array(
            integrator.potts.plan, core.ownership.tags),
        _publication_array(
            integrator.potts.plan, core.ownership.ids),
        _publication_array(
            integrator.potts.plan, core.active),
        _publication_array(
            integrator.potts.plan, core.generations),
        _publication_array(
            integrator.potts.plan, core.cell_types))
end

function _execute_bounded_observable!(
        integrator::CoupledIntegrator,
        observation::BoundedCellTableObservation,
        target_mcs::UInt64, epoch::UInt64)
    _execute_bounded_cell_table_pack!(
        integrator.potts.plan, integrator.potts.state,
        observation)
    return _materialize_bounded_cell_table(
        integrator, observation, target_mcs, epoch)
end

function _execute_bounded_observable!(
        integrator::CoupledIntegrator,
        observation::LosslessOwnershipSnapshot,
        target_mcs::UInt64, epoch::UInt64)
    return _materialize_lossless_ownership(
        integrator, observation, target_mcs, epoch)
end

function execute_bounded_observation!(
        integrator::CoupledIntegrator,
        observation::PhaseObservation,
        target_mcs::UInt64)
    observation.phase isa CompletedMCS || throw(ArgumentError(
        "bounded native observations require the completed-MCS snapshot"))
    _observation_due(
        observation.schedule, target_mcs) || return integrator
    state = integrator.observations
    last = get(
        state.last_published, observation.name, UInt64(0))
    last < target_mcs || return integrator
    epoch = get(
        state.publication_epochs,
        observation.name, UInt64(0)) + UInt64(1)
    try
        value = _execute_bounded_observable!(
            integrator, observation.observable,
            target_mcs, epoch)
        record = PaperObservationRecord(
            observation.name, target_mcs, epoch,
            observation.phase, observation.schema, value)
        push!(state.records, record)
        state.last_published[observation.name] = target_mcs
        state.publication_epochs[observation.name] = epoch
    catch error
        observation.failure isa RequiredObservation && rethrow()
        push!(state.records, ObservationFailureRecord(
            observation.name, target_mcs,
            Symbol(nameof(typeof(error))), sprint(showerror, error)))
    end
    return integrator
end

function _observation_due(schedule, target_mcs::UInt64)
    schedule isa AbstractMCSSchedule || throw(ArgumentError(
        "PhaseObservation schedule must implement AbstractMCSSchedule"))
    return is_due(schedule, target_mcs)
end

function _evaluate_observable(law::DirectLaw, coupled, potts, mcs)
    function_value = law.function_value
    applicable(function_value, coupled, potts, mcs) &&
        return function_value(coupled, potts, mcs)
    applicable(function_value, coupled, potts) &&
        return function_value(coupled, potts)
    applicable(function_value, potts, mcs) &&
        return function_value(potts, mcs)
    applicable(function_value, potts) && return function_value(potts)
    throw(ArgumentError(
        "observation law `$(law.name)` has no supported read-only call signature"))
end
function _evaluate_observable(observable, coupled, potts, mcs)
    applicable(observable, coupled, potts, mcs) &&
        return observable(coupled, potts, mcs)
    applicable(observable, coupled, potts) &&
        return observable(coupled, potts)
    applicable(observable, potts, mcs) &&
        return observable(potts, mcs)
    applicable(observable, potts) && return observable(potts)
    throw(ArgumentError(
        "observable $(typeof(observable)) has no supported read-only call signature"))
end

function execute_observation!(state::CoupledObservationState,
        observation::PhaseObservation, coupled, potts, target_mcs::UInt64)
    observation.phase isa CompletedMCS || throw(ArgumentError(
        "named intermediate observation snapshots require an explicit phase publisher"))
    _observation_due(observation.schedule, target_mcs) || return state
    last = get(state.last_published, observation.name, UInt64(0))
    last < target_mcs || return state
    try
        value = _evaluate_observable(
            observation.observable, deepcopy(coupled), potts, target_mcs)
        epoch = _next_observation_epoch!(
            state, observation.name)
        push!(state.records, PaperObservationRecord(
            observation.name, target_mcs, epoch, observation.phase,
            observation.schema, value))
        state.last_published[observation.name] = target_mcs
    catch error
        observation.failure isa RequiredObservation && rethrow()
        push!(state.records, ObservationFailureRecord(
            observation.name, target_mcs,
            Symbol(nameof(typeof(error))), sprint(showerror, error)))
    end
    return state
end

"""
Publish the bounded Act summary through one backend-native reduction and one explicit observation
synchronization. Only the two one-element result buffers cross the device boundary.
"""
function execute_activity_observation!(state::CoupledObservationState,
        observation::PhaseObservation{<:ActivitySummary}, coupled,
        plan::ExecutionPlan, target_mcs::UInt64)
    observation.phase isa CompletedMCS || throw(ArgumentError(
        "activity summary requires the completed-MCS snapshot"))
    _observation_due(observation.schedule, target_mcs) || return state
    last = get(state.last_published, observation.name, UInt64(0))
    last < target_mcs || return state
    summary = observation.observable
    site_state = _state_by_name(coupled.site_states, summary.property)
    backend = KernelAbstractions.get_backend(site_state.values)
    isequal(backend, plan.backend) ||
        throw(ArgumentError(
            "activity observation storage backend does not match the execution plan"))
    isequal(KernelAbstractions.get_backend(summary.active_count), backend) &&
        isequal(KernelAbstractions.get_backend(summary.total), backend) ||
        throw(ArgumentError(
            "activity observation workspace must share the activity-state backend"))
    kernel = _execution_kernel(plan, _activity_summary_kernel!, 1)
    launch!(plan, kernel, summary.active_count, summary.total,
        site_state.values; ndrange = 1)
    synchronize_observation!(plan)
    if !(plan.backend isa KernelAbstractions.CPU)
        record_transfer!(plan, :device_to_host)
        record_transfer!(plan, :device_to_host)
    end
    active_count = only(Array(summary.active_count))
    total = only(Array(summary.total))
    mean_activity = iszero(active_count) ?
        zero(eltype(site_state.values)) : total / active_count
    value = (
        active_site_count = Int(active_count),
        mean_activity,
        completed_mcs = target_mcs,
    )
    epoch = _next_observation_epoch!(
        state, observation.name)
    push!(state.records, PaperObservationRecord(
        observation.name, target_mcs, epoch, observation.phase,
        observation.schema, value))
    state.last_published[observation.name] = target_mcs
    return state
end

function execute_observation!(state::CoupledObservationState,
        observation, coupled, potts, target_mcs::UInt64)
    push!(state.records, observation(coupled, potts, target_mcs))
    return state
end

struct ObservationTransform{T, I <: AbstractObservationPhase}
    name::Symbol
    input::I
    transform::T
    maximum_work::UInt64
    version::VersionNumber
end
function ObservationTransform(name::Symbol; input::AbstractObservationPhase =
        CompletedMCS(), transform, maximum_work::Integer,
        version::VersionNumber = CONTINUOUS_SYSTEM_CONTRACT_VERSION)
    maximum_work > 0 || throw(ArgumentError(
        "observation-transform work bound must be positive"))
    return ObservationTransform(name, input, transform,
        UInt64(maximum_work), version)
end
component_identity(transform::ObservationTransform) =
    ComponentIdentity(transform.name, transform.version, :observation_transform)
component_semantic_data(transform::ObservationTransform) = (
    input = transform.input,
    transform = _semantic_observable(transform.transform),
    maximum_work = transform.maximum_work)

function (transform::ObservationTransform)(coupled, potts, mcs)
    private_coupled = deepcopy(coupled)
    private_potts = deepcopy(potts)
    return _evaluate_observable(
        transform.transform, private_coupled, private_potts, mcs)
end
