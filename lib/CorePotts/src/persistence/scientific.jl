const _CHECKPOINT_SCHEMA_VERSION = CHECKPOINT_SCHEMA_VERSION
const _COREPOTTS_PERSISTENCE_VERSION = v"0.1.0"
const _ZERO_DIGEST = ntuple(_ -> UInt8(0), 32)

struct ScientificAnalysisSnapshot{S, O <: NamedTuple}
    mcs::UInt64
    state::S
    observables::O
end

struct ExactContinuationProfile
    backend::BackendFamily
    algorithm::String
    algorithm_contract::VersionNumber
    rng_contract::VersionNumber
    julia_version::VersionNumber
    corepotts_version::VersionNumber
    numerical_mode::String
    scalar_types::Tuple
    index_types::Tuple
    dependency_identities::Tuple
    backend_runtime_identity::String
end

struct CanonicalPropertyColumn{T, A <: Vector{T}}
    key::Symbol
    values::A
end

struct CanonicalCheckpoint{N, P <: Tuple}
    schema_version::VersionNumber
    mcs::UInt64
    phase::UInt8
    dims::NTuple{N, Int}
    capacity::UInt32
    ownership_tags::Array{UInt8, N}
    ownership_ids::Array{UInt32, N}
    active::Vector{UInt8}
    generations::Vector{UInt64}
    cell_types::Vector{UInt32}
    reusable_slots::Vector{UInt32}
    reusable_count::UInt32
    medium_ids::Vector{UInt32}
    properties::P
    seed::UInt64
    profile::ExactContinuationProfile
    model_fingerprint::NTuple{32, UInt8}
    schema_fingerprint::NTuple{32, UInt8}
    topology_fingerprint::NTuple{32, UInt8}
    initial_state_fingerprint::NTuple{32, UInt8}
    ancestry_fingerprint::NTuple{32, UInt8}
    state_fingerprint::NTuple{32, UInt8}
    warnings::Tuple
    checksum::NTuple{32, UInt8}
end

struct CheckpointIntegrityError <: Exception
    message::String
end
Base.showerror(io::IO, error::CheckpointIntegrityError) = print(io, error.message)

struct CheckpointCompatibilityError <: Exception
    field::Symbol
    expected::String
    observed::String
end
Base.showerror(io::IO, error::CheckpointCompatibilityError) = print(io,
    "checkpoint compatibility mismatch for ", error.field, ": expected ",
    error.expected, ", observed ", error.observed)

struct IncompleteCheckpointError <: Exception
    key::String
end
Base.showerror(io::IO, error::IncompleteCheckpointError) =
    print(io, "checkpoint `", error.key, "` is incomplete")

struct LogicalImportReport
    source_checksum::NTuple{32, UInt8}
    source_backend::BackendFamily
    destination_backend::BackendFamily
    guarantee::Symbol
    warnings::Tuple
end

@inline function _canonical_marker!(io, value)
    write(io, codeunits(value))
    write(io, UInt8(0xff))
end

function _canonical_write!(io, value)
    if value === nothing
        _canonical_marker!(io, "nothing")
    elseif value isa Bool
        _canonical_marker!(io, value ? "true" : "false")
    elseif value isa Enum
        _canonical_marker!(io, string(typeof(value)))
        _canonical_write!(io, Integer(value))
    elseif value isa Integer
        _canonical_marker!(io, string(typeof(value)))
        _canonical_marker!(io, string(value))
    elseif value isa AbstractFloat
        _canonical_marker!(io, string(typeof(value)))
        _canonical_marker!(io, bitstring(value))
    elseif value isa VersionNumber
        _canonical_marker!(io, "VersionNumber")
        _canonical_marker!(io, string(value))
    elseif value isa Symbol
        _canonical_marker!(io, "Symbol")
        _canonical_marker!(io, String(value))
    elseif value isa AbstractString
        _canonical_marker!(io, "String")
        _canonical_marker!(io, String(value))
    elseif value isa Type
        _canonical_marker!(io, "Type")
        _canonical_marker!(io, string(value))
    elseif value isa Pair
        _canonical_marker!(io, "Pair")
        _canonical_write!(io, first(value))
        _canonical_write!(io, last(value))
    elseif value isa NamedTuple
        _canonical_marker!(io, "NamedTuple")
        _canonical_write!(io, keys(value))
        _canonical_write!(io, Tuple(value))
    elseif value isa Tuple
        _canonical_marker!(io, "Tuple")
        _canonical_write!(io, length(value))
        for item in value
            _canonical_write!(io, item)
        end
    elseif value isa AbstractArray
        host = value isa Array ? value : Adapt.adapt(Array, value)
        _canonical_marker!(io, "Array")
        _canonical_write!(io, eltype(host))
        _canonical_write!(io, size(host))
        for item in host
            _canonical_write!(io, item)
        end
    elseif value isa AbstractDict
        _canonical_marker!(io, "Dict")
        pairs = sort!(collect(value); by = pair -> string(first(pair)))
        _canonical_write!(io, Tuple(pairs))
    elseif isstructtype(typeof(value)) && !ismutabletype(typeof(value))
        _canonical_marker!(io, string(typeof(value)))
        for field in fieldnames(typeof(value))
            _canonical_marker!(io, String(field))
            _canonical_write!(io, getfield(value, field))
        end
    else
        throw(ArgumentError("value of type $(typeof(value)) has no canonical fingerprint encoding"))
    end
    return io
end

function _canonical_digest(values...)
    io = IOBuffer()
    for value in values
        _canonical_write!(io, value)
    end
    return Tuple(SHA.sha256(take!(io)))
end

function _host_model_parts(integrator::ScientificPottsIntegrator)
    lifecycle = integrator.lifecycle isa NoCompiledLifecycle ? NoCompiledLifecycle() :
        integrator.lifecycle.descriptor
    return (
        integrator.state.potts.descriptor.property_schema,
        Adapt.adapt(Array, integrator.state.domain),
        integrator.state.boundary_tracker,
        integrator.proposal_relation,
        Adapt.adapt(Array, integrator.components),
        integrator.moment_tracker,
        lifecycle,
    )
end

scientific_model_fingerprint(integrator::ScientificPottsIntegrator) =
    _canonical_digest(_host_model_parts(integrator))

function _module_identity(module_value::Module)
    version = Base.pkgversion(module_value)
    return string(nameof(module_value), '@', isnothing(version) ? "stdlib" : string(version))
end

function _continuation_profile(integrator::ScientificPottsIntegrator)
    schema = integrator.state.potts.descriptor.property_schema
    scalar_types = Tuple(sort!(unique!(String[
        string(value_type(descriptor)) for descriptor in schema.descriptors
    ])))
    index_types = (
        "ownership_tag=UInt8", "ownership_id=UInt32", "active=UInt8",
        "generation=UInt64", "cell_type=UInt32", "slot=UInt32", "mcs=UInt64",
    )
    dependencies = Tuple(sort!(String[
        _module_identity(@__MODULE__),
        _module_identity(Adapt),
        _module_identity(Atomix),
        _module_identity(ConstructionBase),
        _module_identity(KernelAbstractions),
        _module_identity(SciMLBase),
        _module_identity(StaticArrays),
    ]))
    backend_module = parentmodule(typeof(integrator.plan.backend))
    algorithm_identity = component_identity(integrator.algorithm)
    return ExactContinuationProfile(integrator.plan.capabilities.family,
        string(nameof(typeof(integrator.algorithm))), algorithm_identity.version,
        rng_contract_version(integrator.rng),
        VERSION, _COREPOTTS_PERSISTENCE_VERSION, "native_backend",
        scalar_types, index_types, dependencies, _module_identity(backend_module))
end

function _topology_fingerprint(integrator::ScientificPottsIntegrator)
    _canonical_digest(Adapt.adapt(Array, integrator.state.domain),
        integrator.state.boundary_tracker, integrator.proposal_relation)
end

function analysis_snapshot(integrator::ScientificPottsIntegrator; observables = NamedTuple())
    return ScientificAnalysisSnapshot(integrator.mcs, logical_state(integrator), observables)
end

function _checkpoint_digest(checkpoint::CanonicalCheckpoint)
    return _canonical_digest(checkpoint.schema_version, checkpoint.mcs, checkpoint.phase,
        checkpoint.dims, checkpoint.capacity, checkpoint.ownership_tags,
        checkpoint.ownership_ids, checkpoint.active, checkpoint.generations,
        checkpoint.cell_types, checkpoint.reusable_slots, checkpoint.reusable_count,
        checkpoint.medium_ids, checkpoint.properties, checkpoint.seed,
        checkpoint.profile, checkpoint.model_fingerprint, checkpoint.schema_fingerprint,
        checkpoint.topology_fingerprint, checkpoint.initial_state_fingerprint,
        checkpoint.ancestry_fingerprint, checkpoint.state_fingerprint,
        checkpoint.warnings)
end

function _checkpoint_state_digest(tags, ids, active, generations, cell_types,
        reusable_slots, reusable_count, medium_ids, properties)
    return _canonical_digest(tags, ids, active, generations, cell_types,
        reusable_slots, reusable_count, medium_ids, properties)
end

function _checkpoint_with_checksum(checkpoint::CanonicalCheckpoint{N, P}, checksum) where {N, P}
    return CanonicalCheckpoint{N, P}(checkpoint.schema_version, checkpoint.mcs,
        checkpoint.phase, checkpoint.dims, checkpoint.capacity,
        checkpoint.ownership_tags, checkpoint.ownership_ids, checkpoint.active,
        checkpoint.generations, checkpoint.cell_types, checkpoint.reusable_slots,
        checkpoint.reusable_count, checkpoint.medium_ids, checkpoint.properties,
        checkpoint.seed, checkpoint.profile, checkpoint.model_fingerprint,
        checkpoint.schema_fingerprint, checkpoint.topology_fingerprint,
        checkpoint.initial_state_fingerprint, checkpoint.ancestry_fingerprint,
        checkpoint.state_fingerprint, checkpoint.warnings, checksum)
end

function capture_checkpoint(integrator::ScientificPottsIntegrator;
        ancestry::Union{Nothing, CanonicalCheckpoint} = nothing)
    state = logical_state(integrator)
    owners = state._owners
    tags = map(owner -> owner.tag, owners)
    ids = map(owner -> owner.value, owners)
    columns = map(state.properties.schema.descriptors) do descriptor
        CanonicalPropertyColumn(descriptor.key,
            copy(property_values(state, descriptor.key)))
    end
    profile = _continuation_profile(integrator)
    reusable = zeros(UInt32, nslots(capacity(state)))
    for (index, slot) in enumerate(state._reusable)
        reusable[index] = value(slot)
    end
    N = ndims(owners)
    properties = Tuple(columns)
    active = UInt8.(state._active)
    generations = value.(state._generations)
    medium_ids = UInt32[value(id) for id in state._medium_ids]
    state_fingerprint = _checkpoint_state_digest(tags, ids, active, generations,
        state._cell_types, reusable, UInt32(length(state._reusable)), medium_ids,
        properties)
    initial_fingerprint = if ancestry !== nothing
        validate_checkpoint(ancestry)
        ancestry.initial_state_fingerprint
    elseif integrator.mcs == 0
        state_fingerprint
    else
        _ZERO_DIGEST
    end
    warnings = initial_fingerprint == _ZERO_DIGEST ?
        ("initial-state fingerprint unavailable; capture an MCS-0 ancestor for full provenance",) : ()
    checkpoint = CanonicalCheckpoint{N, typeof(properties)}(_CHECKPOINT_SCHEMA_VERSION,
        integrator.mcs, UInt8(1), size(owners), value(capacity(state)), tags, ids,
        active, generations, copy(state._cell_types), reusable,
        UInt32(length(state._reusable)), medium_ids,
        properties, integrator.seed, profile, scientific_model_fingerprint(integrator),
        _canonical_digest(state.properties.schema), _topology_fingerprint(integrator),
        initial_fingerprint, ancestry === nothing ? _ZERO_DIGEST : ancestry.checksum,
        state_fingerprint, warnings, _ZERO_DIGEST)
    return _checkpoint_with_checksum(checkpoint, _checkpoint_digest(checkpoint))
end

function validate_checkpoint(checkpoint::CanonicalCheckpoint)
    checkpoint.schema_version == _CHECKPOINT_SCHEMA_VERSION ||
        throw(CheckpointCompatibilityError(:schema_version,
            string(_CHECKPOINT_SCHEMA_VERSION), string(checkpoint.schema_version)))
    checkpoint.phase == UInt8(1) || throw(CheckpointIntegrityError(
        "checkpoint is not at a completed-MCS boundary"))
    all(>(0), checkpoint.dims) || throw(CheckpointIntegrityError(
        "checkpoint dimensions must be positive"))
    prod(checkpoint.dims) == length(checkpoint.ownership_ids) ||
        throw(CheckpointIntegrityError("checkpoint ownership dimensions are inconsistent"))
    length(checkpoint.ownership_tags) == length(checkpoint.ownership_ids) ||
        throw(CheckpointIntegrityError("checkpoint ownership tag/id lengths differ"))
    capacity = Int(checkpoint.capacity)
    all(==(capacity), (length(checkpoint.active), length(checkpoint.generations),
        length(checkpoint.cell_types), length(checkpoint.reusable_slots))) ||
        throw(CheckpointIntegrityError("checkpoint fixed-capacity columns have inconsistent lengths"))
    checkpoint.reusable_count <= checkpoint.capacity ||
        throw(CheckpointIntegrityError("checkpoint reusable count exceeds capacity"))
    all(value -> value == UInt8(0) || value == UInt8(1), checkpoint.active) ||
        throw(CheckpointIntegrityError("checkpoint active flags must be zero or one"))
    isempty(checkpoint.medium_ids) && throw(CheckpointIntegrityError(
        "checkpoint must declare at least one medium identity"))
    length(unique(checkpoint.medium_ids)) == length(checkpoint.medium_ids) ||
        throw(CheckpointIntegrityError("checkpoint medium identities must be unique"))
    all(!iszero, checkpoint.medium_ids) || throw(CheckpointIntegrityError(
        "checkpoint medium identities must be positive"))
    reusable_count = Int(checkpoint.reusable_count)
    reusable = checkpoint.reusable_slots[1:reusable_count]
    length(unique(reusable)) == reusable_count || throw(CheckpointIntegrityError(
        "checkpoint reusable identities must be unique"))
    all(slot -> 0 < slot <= checkpoint.capacity && checkpoint.active[Int(slot)] == 0,
        reusable) || throw(CheckpointIntegrityError(
        "checkpoint reusable identities must name inactive slots within capacity"))
    all(iszero, @view checkpoint.reusable_slots[(reusable_count + 1):end]) ||
        throw(CheckpointIntegrityError(
            "checkpoint reusable padding must be canonical zero storage"))
    for index in eachindex(checkpoint.ownership_tags)
        tag = checkpoint.ownership_tags[index]
        id = checkpoint.ownership_ids[index]
        if tag == _CELL_OWNER_TAG
            0 < id <= checkpoint.capacity && checkpoint.active[Int(id)] != 0 ||
                throw(CheckpointIntegrityError(
                    "checkpoint ownership names an inactive or out-of-capacity cell"))
        elseif tag == _MEDIUM_OWNER_TAG
            id in checkpoint.medium_ids || throw(CheckpointIntegrityError(
                "checkpoint ownership names an undeclared medium identity"))
        else
            throw(CheckpointIntegrityError("checkpoint contains an invalid ownership tag"))
        end
    end
    keys = Tuple(column.key for column in checkpoint.properties)
    length(unique(keys)) == length(keys) || throw(CheckpointIntegrityError(
        "checkpoint property keys must be unique"))
    all(column -> length(column.values) == capacity, checkpoint.properties) ||
        throw(CheckpointIntegrityError(
            "checkpoint property columns must match fixed cell capacity"))
    expected_state = _checkpoint_state_digest(checkpoint.ownership_tags,
        checkpoint.ownership_ids, checkpoint.active, checkpoint.generations,
        checkpoint.cell_types, checkpoint.reusable_slots, checkpoint.reusable_count,
        checkpoint.medium_ids, checkpoint.properties)
    expected_state == checkpoint.state_fingerprint || throw(
        CheckpointIntegrityError(
            "checkpoint state fingerprint does not match authoritative state"))
    expected = _checkpoint_digest(checkpoint)
    expected == checkpoint.checksum || throw(CheckpointIntegrityError(
        "checkpoint canonical checksum does not match its payload"))
    return checkpoint
end

function checkpoint_logical_state(checkpoint::CanonicalCheckpoint,
        schema::PropertySchema)
    validate_checkpoint(checkpoint)
    _canonical_digest(schema) == checkpoint.schema_fingerprint ||
        throw(CheckpointCompatibilityError(:property_schema,
            bytes2hex(collect(checkpoint.schema_fingerprint)),
            bytes2hex(collect(_canonical_digest(schema)))))
    keys = Tuple(column.key for column in checkpoint.properties)
    Tuple(property_keys(schema)) == keys || throw(CheckpointIntegrityError(
        "checkpoint property keys do not match the compatible schema"))
    owners = Array{OwnerRef}(undef, checkpoint.dims)
    for index in eachindex(owners)
        owners[index] = _owner_ref_unchecked(checkpoint.ownership_tags[index],
            checkpoint.ownership_ids[index])
    end
    active_ids = CellID[CellID(UInt32(index)) for index in eachindex(checkpoint.active)
        if checkpoint.active[index] != 0]
    cell_types = Dict(CellID(UInt32(index)) => CellTypeID(checkpoint.cell_types[index])
        for index in eachindex(checkpoint.active) if checkpoint.active[index] != 0)
    state = LogicalPottsState(owners, CellCapacity(checkpoint.capacity); active_ids,
        cell_types, medium_domains = MediumID.(checkpoint.medium_ids),
        property_schema = schema)
    state._generations .= CellGeneration.(checkpoint.generations)
    state._reusable = CellSlot[CellSlot(checkpoint.reusable_slots[index])
        for index in 1:Int(checkpoint.reusable_count)]
    for column in checkpoint.properties
        descriptor = property_descriptor(schema, column.key)
        eltype(column.values) == value_type(descriptor) || throw(
            CheckpointCompatibilityError(column.key, string(value_type(descriptor)),
                string(eltype(column.values))))
        property_values(state, column.key) .= column.values
    end
    rebuild_derived_state!(state)
    assert_valid_state(state)
    return state
end

function _checkpoint_host_domain(compiled::CompiledCartesianDomain)
    host = Adapt.adapt(Array, compiled)
    descriptor = host.descriptor
    dims = Tuple(Int.(descriptor.dims))
    obstacles = Pair{Int, OwnerRef}[]
    for site in eachindex(host.storage.mutable_mask)
        host.storage.mutable_mask[site] != 0 && continue
        push!(obstacles, site => _owner_ref_unchecked(
            host.storage.immutable_tags[site], host.storage.immutable_ids[site]))
    end
    return CartesianDomain(dims; spacing = Tuple(descriptor.spacing),
        boundaries = descriptor.boundaries, obstacles)
end

function _compile_checkpoint_lifecycle(prototype, state, plan)
    prototype.lifecycle isa NoCompiledLifecycle && return NoCompiledLifecycle()
    descriptor = prototype.lifecycle.descriptor
    return compile_lifecycle(descriptor.events, state, plan;
        resolver = descriptor.resolver,
        minimum_daughter_volume = descriptor.minimum_daughter_volume)
end

function _restore_checkpoint(checkpoint::CanonicalCheckpoint,
        prototype::ScientificPottsIntegrator, adaptor; exact::Bool,
        algorithm_workspace = NoAlgorithmWorkspace())
    validate_checkpoint(checkpoint)
    schema = prototype.state.potts.descriptor.property_schema
    checkpoint.schema_fingerprint == _canonical_digest(schema) || throw(
        CheckpointCompatibilityError(:property_schema,
            bytes2hex(collect(checkpoint.schema_fingerprint)),
            bytes2hex(collect(_canonical_digest(schema)))))
    checkpoint.topology_fingerprint == _topology_fingerprint(prototype) || throw(
        CheckpointCompatibilityError(:topology, "prototype topology", "checkpoint topology"))
    checkpoint.model_fingerprint == scientific_model_fingerprint(prototype) || throw(
        CheckpointCompatibilityError(:model, "prototype model fingerprint",
            "checkpoint model fingerprint"))
    if exact
        expected_profile = _continuation_profile(prototype)
        checkpoint.profile == expected_profile || throw(
            CheckpointCompatibilityError(:continuation_profile,
                string(expected_profile), string(checkpoint.profile)))
    end
    logical = checkpoint_logical_state(checkpoint, schema)
    domain = _checkpoint_host_domain(prototype.state.domain)
    compiled = compile_scientific_state(logical, domain,
        prototype.state.boundary_tracker; moment_tracker = prototype.moment_tracker)
    state = Adapt.adapt(adaptor, compiled)
    backend = KernelAbstractions.get_backend(state.potts.storage.active)
    plan = ExecutionPlan(backend; block_size = prototype.plan.block_size,
        metrics = ExecutionMetrics())
    exact && plan.capabilities.family != checkpoint.profile.backend && throw(
        CheckpointCompatibilityError(:backend, string(checkpoint.profile.backend),
            string(plan.capabilities.family)))
    lifecycle = _compile_checkpoint_lifecycle(prototype, state, plan)
    adapted_components = Adapt.adapt(adaptor, prototype.components)
    integrator = if prototype.algorithm isa AbstractSequentialCPMAlgorithm
        init_scientific(state, prototype.proposal_relation,
            adapted_components, prototype.algorithm;
            seed = checkpoint.seed, rng = prototype.rng, plan,
            moment_tracker = prototype.moment_tracker, lifecycle,
            initialize_mechanics = false, algorithm_workspace)
    else
        algorithm_workspace isa NoAlgorithmWorkspace || throw(
            CheckpointCompatibilityError(:algorithm_workspace,
                "no workspace for $(typeof(prototype.algorithm))",
                string(typeof(algorithm_workspace))))
        init_scientific(state, prototype.proposal_relation,
            adapted_components, prototype.algorithm;
            seed = checkpoint.seed, rng = prototype.rng, plan,
            moment_tracker = prototype.moment_tracker, lifecycle,
            initialize_mechanics = false)
    end
    integrator.mcs = checkpoint.mcs
    return integrator
end

function restore_checkpoint(checkpoint::CanonicalCheckpoint,
        prototype::ScientificPottsIntegrator; adaptor = Array)
    return _restore_checkpoint(checkpoint, prototype, adaptor; exact = true)
end

function import_checkpoint(checkpoint::CanonicalCheckpoint,
        prototype::ScientificPottsIntegrator; adaptor = Array)
    integrator = _restore_checkpoint(checkpoint, prototype, adaptor; exact = false)
    report = LogicalImportReport(checkpoint.checksum, checkpoint.profile.backend,
        integrator.plan.capabilities.family, :statistical_or_weaker,
        ("logical import does not claim exact continuation",))
    return integrator, report
end

abstract type AbstractCheckpointStore end

mutable struct MemoryCheckpointStore <: AbstractCheckpointStore
    records::Dict{String, CanonicalCheckpoint}
end
MemoryCheckpointStore() = MemoryCheckpointStore(Dict{String, CanonicalCheckpoint}())

struct HDF5CheckpointStore <: AbstractCheckpointStore
    path::String
end
struct ZarrCheckpointStore <: AbstractCheckpointStore
    path::String
end

function write_checkpoint! end
function read_checkpoint end

function write_checkpoint!(store::MemoryCheckpointStore, key,
        checkpoint::CanonicalCheckpoint; fail_after = nothing)
    name = String(key)
    staged = deepcopy(validate_checkpoint(checkpoint))
    fail_after === :payload && throw(ErrorException(
        "injected checkpoint failure after staged payload"))
    store.records[name] = staged
    return store
end

function read_checkpoint(store::MemoryCheckpointStore, key)
    name = String(key)
    haskey(store.records, name) || throw(KeyError(name))
    return deepcopy(validate_checkpoint(store.records[name]))
end

function checkpoint_storage_payload(checkpoint::CanonicalCheckpoint)
    validate_checkpoint(checkpoint)
    return (
        complete = UInt8(1), schema_version = string(checkpoint.schema_version),
        mcs = checkpoint.mcs, phase = checkpoint.phase, dims = collect(Int64, checkpoint.dims),
        capacity = checkpoint.capacity, ownership_tags = copy(checkpoint.ownership_tags),
        ownership_ids = copy(checkpoint.ownership_ids), active = copy(checkpoint.active),
        generations = copy(checkpoint.generations), cell_types = copy(checkpoint.cell_types),
        reusable_slots = copy(checkpoint.reusable_slots),
        reusable_count = checkpoint.reusable_count, medium_ids = copy(checkpoint.medium_ids),
        property_keys = String[String(column.key) for column in checkpoint.properties],
        property_values = Any[copy(column.values) for column in checkpoint.properties],
        seed = checkpoint.seed, backend = UInt8(checkpoint.profile.backend),
        algorithm = checkpoint.profile.algorithm,
        algorithm_contract = string(checkpoint.profile.algorithm_contract),
        rng_contract = string(checkpoint.profile.rng_contract),
        julia_version = string(checkpoint.profile.julia_version),
        corepotts_version = string(checkpoint.profile.corepotts_version),
        numerical_mode = checkpoint.profile.numerical_mode,
        scalar_types = String[checkpoint.profile.scalar_types...],
        index_types = String[checkpoint.profile.index_types...],
        dependency_identities = String[checkpoint.profile.dependency_identities...],
        backend_runtime_identity = checkpoint.profile.backend_runtime_identity,
        model_fingerprint = collect(checkpoint.model_fingerprint),
        schema_fingerprint = collect(checkpoint.schema_fingerprint),
        topology_fingerprint = collect(checkpoint.topology_fingerprint),
        initial_state_fingerprint = collect(checkpoint.initial_state_fingerprint),
        ancestry_fingerprint = collect(checkpoint.ancestry_fingerprint),
        state_fingerprint = collect(checkpoint.state_fingerprint),
        warnings = String[checkpoint.warnings...], checksum = collect(checkpoint.checksum),
    )
end

function checkpoint_from_storage_payload(payload)
    payload.complete == UInt8(1) || throw(IncompleteCheckpointError("storage payload"))
    dims = Tuple(Int.(payload.dims))
    N = length(dims)
    properties = Tuple(CanonicalPropertyColumn(Symbol(key), collect(values))
        for (key, values) in zip(payload.property_keys, payload.property_values))
    profile = ExactContinuationProfile(BackendFamily(payload.backend), payload.algorithm,
        VersionNumber(payload.algorithm_contract), VersionNumber(payload.rng_contract),
        VersionNumber(payload.julia_version),
        VersionNumber(payload.corepotts_version), payload.numerical_mode,
        Tuple(payload.scalar_types), Tuple(payload.index_types),
        Tuple(payload.dependency_identities), payload.backend_runtime_identity)
    checkpoint = CanonicalCheckpoint{N, typeof(properties)}(
        VersionNumber(payload.schema_version), payload.mcs, payload.phase, dims,
        payload.capacity, Array(payload.ownership_tags), Array(payload.ownership_ids),
        collect(payload.active), collect(payload.generations), collect(payload.cell_types),
        collect(payload.reusable_slots), payload.reusable_count, collect(payload.medium_ids),
        properties, payload.seed, profile, Tuple(payload.model_fingerprint),
        Tuple(payload.schema_fingerprint), Tuple(payload.topology_fingerprint),
        Tuple(payload.initial_state_fingerprint), Tuple(payload.ancestry_fingerprint),
        Tuple(payload.state_fingerprint), Tuple(payload.warnings), Tuple(payload.checksum))
    return validate_checkpoint(checkpoint)
end
