abstract type AbstractProgramEngine end
struct SequentialProgramEngine <: AbstractProgramEngine end
struct CheckerboardProgramEngine <: AbstractProgramEngine end
struct CPUProgramBackend end

struct CompiledScalar{T <: AbstractFloat}
    value::T
    parameter_index::Int32
    function CompiledScalar(value::T, parameter_index::Integer = 0) where {
            T <: AbstractFloat,
        }
        0 <= parameter_index <= typemax(Int32) ||
            throw(ArgumentError("compiled scalar parameter index is out of range"))
        new{T}(value, Int32(parameter_index))
    end
end

@inline function compiled_scalar_value(
        scalar::CompiledScalar{T}, parameters::AbstractVector{T}
    ) where {T}
    index = scalar.parameter_index
    return index == 0 ? scalar.value : @inbounds parameters[index]
end

struct CompiledActivityPlan{T <: AbstractFloat}
    kind::Int16
    maximum::CompiledScalar{T}
    strength::CompiledScalar{T}
    neighborhood_offsets::Matrix{Int8}
    activate_extensions::Bool
    decay_per_mcs::T
end

struct CompiledFieldPlan{T <: AbstractFloat}
    enabled::Bool
    diffusion::CompiledScalar{T}
    decay::CompiledScalar{T}
    secretion::CompiledScalar{T}
    chemotaxis_kind::Int16
    chemotaxis_strength::CompiledScalar{T}
    substeps::Int32
    duration_per_mcs::T
end

struct CompiledPottsProgram{
        T <: AbstractFloat,
        N,
        E <: AbstractProgramEngine,
        B,
        A,
        F,
    }
    shape::NTuple{N, Int}
    periodic::NTuple{N, Bool}
    proposal_offsets::Matrix{Int8}
    contact_offsets::Matrix{Int8}
    kind_count::Int16
    medium_kind::Int16
    volume_targets::Vector{CompiledScalar{T}}
    volume_strengths::Vector{CompiledScalar{T}}
    contact_energies::Matrix{CompiledScalar{T}}
    connectivity_kinds::BitVector
    temperature::CompiledScalar{T}
    attempts_per_site::Int32
    parameter_defaults::Vector{T}
    activity::A
    field::F
    engine::E
    backend::B
    fingerprint::String
end

function CompiledPottsProgram(
        shape::NTuple{N, Int},
        periodic::NTuple{N, Bool},
        proposal_offsets::Matrix{Int8},
        contact_offsets::Matrix{Int8},
        kind_count::Integer,
        medium_kind::Integer,
        volume_targets::Vector{CompiledScalar{T}},
        volume_strengths::Vector{CompiledScalar{T}},
        contact_energies::Matrix{CompiledScalar{T}},
        connectivity_kinds::BitVector,
        temperature::CompiledScalar{T},
        attempts_per_site::Integer,
        parameter_defaults::Vector{T},
        activity,
        field,
        engine::E,
        backend::B,
        fingerprint::AbstractString,
    ) where {T <: AbstractFloat, N, E <: AbstractProgramEngine, B}
    all(>(0), shape) || throw(ArgumentError("program dimensions must be positive"))
    size(proposal_offsets, 1) == N ||
        throw(ArgumentError("proposal offsets have the wrong dimensionality"))
    size(contact_offsets, 1) == N ||
        throw(ArgumentError("contact offsets have the wrong dimensionality"))
    kind_count > 0 || throw(ArgumentError("a program requires at least one kind"))
    1 <= medium_kind <= kind_count ||
        throw(ArgumentError("the medium kind must be declared"))
    length(volume_targets) == kind_count ||
        throw(ArgumentError("volume target table has the wrong size"))
    length(volume_strengths) == kind_count ||
        throw(ArgumentError("volume strength table has the wrong size"))
    size(contact_energies) == (kind_count, kind_count) ||
        throw(ArgumentError("contact table has the wrong size"))
    length(connectivity_kinds) == kind_count ||
        throw(ArgumentError("connectivity table has the wrong size"))
    attempts_per_site > 0 ||
        throw(ArgumentError("attempts per site must be positive"))
    return CompiledPottsProgram{
        T, N, E, B, typeof(activity), typeof(field),
    }(
        shape,
        periodic,
        copy(proposal_offsets),
        copy(contact_offsets),
        Int16(kind_count),
        Int16(medium_kind),
        copy(volume_targets),
        copy(volume_strengths),
        copy(contact_energies),
        copy(connectivity_kinds),
        temperature,
        Int32(attempts_per_site),
        copy(parameter_defaults),
        activity,
        field,
        engine,
        backend,
        String(fingerprint),
    )
end

struct ProgramInitialState{T <: AbstractFloat, N, A, F}
    ownership::Array{Int32, N}
    cell_kinds::Vector{Int16}
    activity::A
    field::F
end

function ProgramInitialState(
        ownership::AbstractArray{<:Integer, N},
        cell_kinds::AbstractVector{<:Integer};
        scalar_type::Type{T} = Float64,
        activity = nothing,
        field = nothing,
    ) where {N, T <: AbstractFloat}
    owned = Array{Int32, N}(ownership)
    kinds = Int16.(cell_kinds)
    activity_values = activity === nothing ? nothing : Array{T, N}(activity)
    field_values = field === nothing ? nothing : Array{T, N}(field)
    return ProgramInitialState{T, N, typeof(activity_values), typeof(field_values)}(
        owned, kinds, activity_values, field_values
    )
end

struct ProgramSnapshot{T <: AbstractFloat, N, A, F}
    mcs::Int
    ownership::Array{Int32, N}
    cell_kinds::Vector{Int16}
    volumes::Vector{Int}
    activity::A
    field::F
end

struct ProgramCheckpoint{S, P}
    schema::VersionNumber
    program_fingerprint::String
    snapshot::S
    parameters::P
    seed::UInt64
    replica::UInt32
    accepted::Int
    rejected::Int
    null_attempts::Int
    checksum::String
end

function _program_checkpoint_checksum(
        schema,
        fingerprint,
        snapshot,
        parameters,
        seed,
        replica,
        accepted,
        rejected,
        null_attempts,
    )
    payload = string(
        schema, '\n',
        fingerprint, '\n',
        snapshot.mcs, '\n',
        size(snapshot.ownership), '\n',
        join(vec(snapshot.ownership), ','), '\n',
        join(snapshot.cell_kinds, ','), '\n',
        join(snapshot.volumes, ','), '\n',
        snapshot.activity === nothing ? "nothing" :
        join(vec(snapshot.activity), ','), '\n',
        snapshot.field === nothing ? "nothing" :
        join(vec(snapshot.field), ','), '\n',
        join(parameters, ','), '\n',
        seed, '\n',
        replica, '\n',
        accepted, '\n',
        rejected, '\n',
        null_attempts,
    )
    return bytes2hex(SHA.sha256(codeunits(payload)))
end

function program_checkpoint(runtime)
    runtime.settled || throw(ArgumentError(
        "a checkpoint requires a settled complete-MCS boundary"
    ))
    schema = v"1.0.0"
    snapshot = program_snapshot(runtime)
    parameters = copy(runtime.parameters)
    checksum = _program_checkpoint_checksum(
        schema,
        runtime.program.fingerprint,
        snapshot,
        parameters,
        runtime.seed,
        runtime.replica,
        runtime.accepted,
        runtime.rejected,
        runtime.null_attempts,
    )
    return ProgramCheckpoint(
        schema,
        runtime.program.fingerprint,
        snapshot,
        parameters,
        runtime.seed,
        runtime.replica,
        runtime.accepted,
        runtime.rejected,
        runtime.null_attempts,
        checksum,
    )
end

function restore_program_checkpoint(
        program::CompiledPottsProgram, checkpoint::ProgramCheckpoint
    )
    checkpoint.schema == v"1.0.0" ||
        throw(ArgumentError("unsupported CorePotts checkpoint schema"))
    checkpoint.program_fingerprint == program.fingerprint ||
        throw(ArgumentError("checkpoint executable identity does not match"))
    expected = _program_checkpoint_checksum(
        checkpoint.schema,
        checkpoint.program_fingerprint,
        checkpoint.snapshot,
        checkpoint.parameters,
        checkpoint.seed,
        checkpoint.replica,
        checkpoint.accepted,
        checkpoint.rejected,
        checkpoint.null_attempts,
    )
    expected == checkpoint.checksum ||
        throw(ArgumentError("checkpoint integrity checksum mismatch"))
    initial = ProgramInitialState(
        checkpoint.snapshot.ownership,
        checkpoint.snapshot.cell_kinds;
        scalar_type = eltype(program.parameter_defaults),
        activity = checkpoint.snapshot.activity,
        field = checkpoint.snapshot.field,
    )
    runtime = initialize_program(
        program,
        initial,
        checkpoint.parameters,
        checkpoint.seed,
        checkpoint.replica;
        initial_mcs = checkpoint.snapshot.mcs,
    )
    runtime.volumes == checkpoint.snapshot.volumes ||
        throw(ArgumentError("checkpoint logical volume invariant failed"))
    runtime.accepted = checkpoint.accepted
    runtime.rejected = checkpoint.rejected
    runtime.null_attempts = checkpoint.null_attempts
    return runtime
end

mutable struct ProgramRuntime{T <: AbstractFloat, N, P, A, F}
    program::P
    ownership::Array{Int32, N}
    cell_kinds::Vector{Int16}
    volumes::Vector{Int}
    activity::A
    field::F
    parameters::Vector{T}
    seed::UInt64
    replica::UInt32
    mcs::Int
    accepted::Int
    rejected::Int
    null_attempts::Int
    settled::Bool
end

function initialize_program(
        program::CompiledPottsProgram{T, N},
        initial::ProgramInitialState,
        parameters::AbstractVector{<:Real},
        seed::UInt64,
        replica::UInt32;
        initial_mcs::Integer = 0,
    ) where {T, N}
    size(initial.ownership) == program.shape ||
        throw(ArgumentError("initial ownership shape does not match the program"))
    length(parameters) == length(program.parameter_defaults) ||
        throw(ArgumentError("runtime parameter buffer has the wrong length"))
    maximum(initial.ownership; init = Int32(0)) <= length(initial.cell_kinds) ||
        throw(ArgumentError("initial ownership references an unknown cell label"))
    minimum(initial.ownership; init = Int32(0)) >= 0 ||
        throw(ArgumentError("initial ownership labels must be nonnegative"))
    all(kind -> 1 <= kind <= program.kind_count, initial.cell_kinds) ||
        throw(ArgumentError("initial cell kind is outside the compiled kind table"))
    initial_mcs >= 0 || throw(ArgumentError("initial MCS must be nonnegative"))

    volumes = zeros(Int, length(initial.cell_kinds))
    for owner in initial.ownership
        owner == 0 || (volumes[owner] += 1)
    end
    activity = if program.activity === nothing
        nothing
    elseif initial.activity === nothing
        zeros(T, program.shape)
    else
        size(initial.activity) == program.shape ||
            throw(ArgumentError("activity state shape does not match the program"))
        copy(initial.activity)
    end
    field = if program.field === nothing || !program.field.enabled
        nothing
    elseif initial.field === nothing
        zeros(T, program.shape)
    else
        size(initial.field) == program.shape ||
            throw(ArgumentError("field state shape does not match the program"))
        copy(initial.field)
    end
    return ProgramRuntime{
        T, N, typeof(program), typeof(activity), typeof(field),
    }(
        program,
        copy(initial.ownership),
        copy(initial.cell_kinds),
        volumes,
        activity,
        field,
        T.(parameters),
        seed,
        replica,
        Int(initial_mcs),
        0,
        0,
        0,
        true,
    )
end

function program_snapshot(runtime::ProgramRuntime{T, N}) where {T, N}
    runtime.settled || throw(ArgumentError(
        "a program snapshot requires a settled complete-MCS boundary"
    ))
    activity = runtime.activity === nothing ? nothing : copy(runtime.activity)
    field = runtime.field === nothing ? nothing : copy(runtime.field)
    return ProgramSnapshot{T, N, typeof(activity), typeof(field)}(
        runtime.mcs,
        copy(runtime.ownership),
        copy(runtime.cell_kinds),
        copy(runtime.volumes),
        activity,
        field,
    )
end

@inline function _trajectory_seed(seed::UInt64, replica::UInt32)
    return _rng_mix64(
        xor(seed, UInt64(0x706f7474732d7631), UInt64(replica) * UInt64(0x9e3779b97f4a7c15))
    )
end

@inline function _program_address(
        stream::RNGStream, mcs::Int, operation::Integer, entity::Integer;
        subround::Integer = 0, draw::Integer = 0,
    )
    return RNGAddress(
        stream = stream,
        mcs = mcs,
        subround = subround,
        operation = operation,
        entity_kind = SiteEntity,
        entity = entity,
        draw = draw,
    )
end

@inline function _program_bounded(
        runtime::ProgramRuntime, stream::RNGStream, operation, entity, bound;
        subround = 0, draw = 0,
    )
    address = _program_address(
        stream, runtime.mcs + 1, operation, entity; subround, draw
    )
    return Int(bounded_uint(
        Philox4x32x10V1(),
        _trajectory_seed(runtime.seed, runtime.replica),
        address,
        UInt32(bound),
    )) + 1
end

@inline function _program_uniform(
        ::Type{T}, runtime::ProgramRuntime, stream::RNGStream, operation, entity;
        subround = 0, draw = 0,
    ) where {T}
    address = _program_address(
        stream, runtime.mcs + 1, operation, entity; subround, draw
    )
    return uniform_open01(
        T,
        Philox4x32x10V1(),
        _trajectory_seed(runtime.seed, runtime.replica),
        address,
    )
end

@inline function _neighbor_index(
        program::CompiledPottsProgram{T, N},
        index::CartesianIndex{N},
        offsets::Matrix{Int8},
        direction::Int,
    ) where {T, N}
    coords = Tuple(index)
    candidate = ntuple(N) do dimension
        value = coords[dimension] + Int(offsets[dimension, direction])
        if program.periodic[dimension]
            mod1(value, program.shape[dimension])
        elseif 1 <= value <= program.shape[dimension]
            value
        else
            0
        end
    end
    any(iszero, candidate) && return nothing
    return CartesianIndex(candidate)
end

@inline _owner_kind(runtime::ProgramRuntime, owner::Int32) =
    owner == 0 ? runtime.program.medium_kind : @inbounds runtime.cell_kinds[owner]

@inline function _volume_delta(runtime::ProgramRuntime{T}, old_owner, new_owner) where {T}
    old_owner == new_owner && return zero(T)
    program = runtime.program
    parameters = runtime.parameters
    delta = zero(T)
    if old_owner != 0
        kind = @inbounds runtime.cell_kinds[old_owner]
        strength = compiled_scalar_value(program.volume_strengths[kind], parameters)
        target = compiled_scalar_value(program.volume_targets[kind], parameters)
        volume = @inbounds runtime.volumes[old_owner]
        delta += strength * ((T(volume - 1) - target)^2 - (T(volume) - target)^2)
    end
    if new_owner != 0
        kind = @inbounds runtime.cell_kinds[new_owner]
        strength = compiled_scalar_value(program.volume_strengths[kind], parameters)
        target = compiled_scalar_value(program.volume_targets[kind], parameters)
        volume = @inbounds runtime.volumes[new_owner]
        delta += strength * ((T(volume + 1) - target)^2 - (T(volume) - target)^2)
    end
    return delta
end

function _contact_delta(
        runtime::ProgramRuntime{T, N},
        target::CartesianIndex{N},
        old_owner::Int32,
        new_owner::Int32,
    ) where {T, N}
    old_kind = _owner_kind(runtime, old_owner)
    new_kind = _owner_kind(runtime, new_owner)
    delta = zero(T)
    table = runtime.program.contact_energies
    for direction in axes(runtime.program.contact_offsets, 2)
        neighbor = _neighbor_index(
            runtime.program, target, runtime.program.contact_offsets, direction
        )
        neighbor === nothing && continue
        neighbor_owner = @inbounds runtime.ownership[neighbor]
        neighbor_kind = _owner_kind(runtime, neighbor_owner)
        old_owner == neighbor_owner || (
            delta -= compiled_scalar_value(
                @inbounds(table[old_kind, neighbor_kind]), runtime.parameters
            )
        )
        new_owner == neighbor_owner || (
            delta += compiled_scalar_value(
                @inbounds(table[new_kind, neighbor_kind]), runtime.parameters
            )
        )
    end
    return delta
end

function _connected_after_removal(
        runtime::ProgramRuntime{T, N},
        target::CartesianIndex{N},
        owner::Int32,
    ) where {T, N}
    owner == 0 && return true
    kind = @inbounds runtime.cell_kinds[owner]
    runtime.program.connectivity_kinds[kind] || return true
    neighbors = CartesianIndex{N}[]
    for direction in axes(runtime.program.proposal_offsets, 2)
        candidate = _neighbor_index(
            runtime.program, target, runtime.program.proposal_offsets, direction
        )
        candidate === nothing && continue
        @inbounds runtime.ownership[candidate] == owner || continue
        candidate == target || push!(neighbors, candidate)
    end
    length(neighbors) <= 1 && return true
    visited = Set{CartesianIndex{N}}((first(neighbors),))
    frontier = CartesianIndex{N}[first(neighbors)]
    neighbor_set = Set(neighbors)
    while !isempty(frontier)
        current = pop!(frontier)
        for direction in axes(runtime.program.proposal_offsets, 2)
            candidate = _neighbor_index(
                runtime.program,
                current,
                runtime.program.proposal_offsets,
                direction,
            )
            candidate === nothing && continue
            candidate == target && continue
            candidate in neighbor_set || continue
            candidate in visited && continue
            push!(visited, candidate)
            push!(frontier, candidate)
        end
    end
    return length(visited) == length(neighbor_set)
end

function _local_activity_geomean(
        runtime::ProgramRuntime{T, N},
        site::CartesianIndex{N},
        owner::Int32,
    ) where {T, N}
    owner == 0 && return zero(T)
    plan = runtime.program.activity
    plan === nothing && return zero(T)
    total = zero(T)
    count = 0
    if @inbounds runtime.ownership[site] == owner
        total += log1p(max(zero(T), @inbounds(runtime.activity[site])))
        count += 1
    end
    for direction in axes(plan.neighborhood_offsets, 2)
        neighbor = _neighbor_index(
            runtime.program, site, plan.neighborhood_offsets, direction
        )
        neighbor === nothing && continue
        @inbounds runtime.ownership[neighbor] == owner || continue
        total += log1p(max(zero(T), @inbounds(runtime.activity[neighbor])))
        count += 1
    end
    return count == 0 ? zero(T) : exp(total / T(count)) - one(T)
end

function _activity_delta(
        runtime::ProgramRuntime{T, N},
        source::CartesianIndex{N},
        target::CartesianIndex{N},
        old_owner::Int32,
        new_owner::Int32,
    ) where {T, N}
    plan = runtime.program.activity
    plan === nothing && return zero(T)
    new_owner == 0 && return zero(T)
    @inbounds runtime.cell_kinds[new_owner] == plan.kind || return zero(T)
    maximum = compiled_scalar_value(plan.maximum, runtime.parameters)
    maximum > zero(T) || return zero(T)
    strength = compiled_scalar_value(plan.strength, runtime.parameters)
    source_activity = _local_activity_geomean(runtime, source, new_owner)
    target_activity = _local_activity_geomean(runtime, target, old_owner)
    return -(strength / maximum) * (source_activity - target_activity)
end

function _chemotaxis_delta(
        runtime::ProgramRuntime{T, N},
        source::CartesianIndex{N},
        target::CartesianIndex{N},
        new_owner::Int32,
    ) where {T, N}
    plan = runtime.program.field
    plan === nothing && return zero(T)
    plan.enabled || return zero(T)
    new_owner == 0 && return zero(T)
    @inbounds runtime.cell_kinds[new_owner] == plan.chemotaxis_kind || return zero(T)
    strength = compiled_scalar_value(plan.chemotaxis_strength, runtime.parameters)
    return -strength * (@inbounds(runtime.field[target]) - @inbounds(runtime.field[source]))
end

function _commit_copy!(
        runtime::ProgramRuntime{T, N},
        target::CartesianIndex{N},
        old_owner::Int32,
        new_owner::Int32,
    ) where {T, N}
    @inbounds runtime.ownership[target] = new_owner
    old_owner == 0 || (@inbounds runtime.volumes[old_owner] -= 1)
    new_owner == 0 || (@inbounds runtime.volumes[new_owner] += 1)
    plan = runtime.program.activity
    if plan !== nothing && runtime.activity !== nothing
        old_owner == new_owner || (@inbounds runtime.activity[target] = zero(T))
        if plan.activate_extensions && old_owner == 0 && new_owner != 0 &&
                @inbounds(runtime.cell_kinds[new_owner]) == plan.kind
            @inbounds runtime.activity[target] =
                compiled_scalar_value(plan.maximum, runtime.parameters)
        end
    end
    return nothing
end

function _attempt!(
        runtime::ProgramRuntime{T, N},
        target::CartesianIndex{N},
        attempt_identity::Int,
        subround::Int,
    ) where {T, N}
    program = runtime.program
    direction = _program_bounded(
        runtime,
        ProposalDirectionStream,
        2,
        attempt_identity,
        size(program.proposal_offsets, 2);
        subround,
    )
    source = _neighbor_index(program, target, program.proposal_offsets, direction)
    source === nothing && (runtime.null_attempts += 1; return false)
    old_owner = @inbounds runtime.ownership[target]
    new_owner = @inbounds runtime.ownership[source]
    old_owner == new_owner && (runtime.null_attempts += 1; return false)
    _connected_after_removal(runtime, target, old_owner) ||
        (runtime.rejected += 1; return false)

    delta = _volume_delta(runtime, old_owner, new_owner)
    delta += _contact_delta(runtime, target, old_owner, new_owner)
    delta += _activity_delta(runtime, source, target, old_owner, new_owner)
    delta += _chemotaxis_delta(runtime, source, target, new_owner)
    temperature = compiled_scalar_value(program.temperature, runtime.parameters)
    temperature >= zero(T) ||
        throw(ArgumentError("temperature must remain nonnegative"))
    accepted = delta <= zero(T)
    if !accepted && temperature > zero(T)
        probability = exp(-delta / temperature)
        draw = _program_uniform(
            T,
            runtime,
            AcceptanceStream,
            3,
            attempt_identity;
            subround,
        )
        accepted = draw < probability
    end
    if accepted
        _commit_copy!(runtime, target, old_owner, new_owner)
        runtime.accepted += 1
        return true
    end
    runtime.rejected += 1
    return false
end

function _advance_sequential!(runtime::ProgramRuntime)
    site_count = length(runtime.ownership)
    attempts = site_count * Int(runtime.program.attempts_per_site)
    indices = CartesianIndices(runtime.ownership)
    for attempt in 1:attempts
        target_linear = _program_bounded(
            runtime, ProposalRecipientStream, 1, attempt, site_count
        )
        _attempt!(runtime, indices[target_linear], attempt, 0)
    end
    return nothing
end

function _advance_checkerboard!(runtime::ProgramRuntime{T, N}) where {T, N}
    colors = 1 << N
    attempt_identity = 0
    for color in 0:(colors - 1)
        for target in CartesianIndices(runtime.ownership)
            encoded = 0
            coordinates = Tuple(target)
            for dimension in 1:N
                encoded |= ((coordinates[dimension] - 1) & 1) << (dimension - 1)
            end
            encoded == color || continue
            for _ in 1:Int(runtime.program.attempts_per_site)
                attempt_identity += 1
                _attempt!(runtime, target, attempt_identity, color)
            end
        end
    end
    return nothing
end

function _after_mcs!(runtime::ProgramRuntime{T, N}) where {T, N}
    plan = runtime.program.activity
    if plan !== nothing && runtime.activity !== nothing
        decay = plan.decay_per_mcs
        for index in eachindex(runtime.activity)
            @inbounds runtime.activity[index] =
                max(zero(T), runtime.activity[index] - decay)
        end
    end
    field_plan = runtime.program.field
    if field_plan !== nothing && field_plan.enabled && runtime.field !== nothing
        substeps = Int(field_plan.substeps)
        dt = field_plan.duration_per_mcs / T(substeps)
        diffusion = compiled_scalar_value(field_plan.diffusion, runtime.parameters)
        decay = compiled_scalar_value(field_plan.decay, runtime.parameters)
        secretion = compiled_scalar_value(field_plan.secretion, runtime.parameters)
        scratch = similar(runtime.field)
        for _ in 1:substeps
            for site in CartesianIndices(runtime.field)
                center = @inbounds runtime.field[site]
                laplace = zero(T)
                for direction in axes(runtime.program.proposal_offsets, 2)
                    neighbor = _neighbor_index(
                        runtime.program,
                        site,
                        runtime.program.proposal_offsets,
                        direction,
                    )
                    neighbor === nothing && continue
                    laplace += @inbounds(runtime.field[neighbor]) - center
                end
                owner = @inbounds runtime.ownership[site]
                source = owner != 0 &&
                         @inbounds(runtime.cell_kinds[owner]) ==
                         field_plan.chemotaxis_kind ? secretion : zero(T)
                @inbounds scratch[site] = max(
                    zero(T),
                    center + dt * (diffusion * laplace - decay * center + source),
                )
            end
            runtime.field, scratch = scratch, runtime.field
        end
    end
    return nothing
end

function advance_mcs!(runtime::ProgramRuntime)
    runtime.settled ||
        throw(ArgumentError("cannot advance an unsettled program runtime"))
    runtime.settled = false
    if runtime.program.engine isa SequentialProgramEngine
        _advance_sequential!(runtime)
    elseif runtime.program.engine isa CheckerboardProgramEngine
        _advance_checkerboard!(runtime)
    else
        error("unreachable program engine")
    end
    _after_mcs!(runtime)
    runtime.mcs += 1
    runtime.settled = true
    return runtime
end

function update_program_parameters!(
        runtime::ProgramRuntime{T}, parameters::AbstractVector{<:Real}
    ) where {T}
    runtime.settled ||
        throw(ArgumentError("parameter updates require a settled MCS boundary"))
    length(parameters) == length(runtime.parameters) ||
        throw(ArgumentError("runtime parameter buffer has the wrong length"))
    replacement = T.(parameters)
    all(isfinite, replacement) ||
        throw(ArgumentError("runtime parameters must be finite"))
    copyto!(runtime.parameters, replacement)
    return runtime
end

program_execution_report(program::CompiledPottsProgram) = (
    engine = nameof(typeof(program.engine)),
    backend = nameof(typeof(program.backend)),
    scalar_type = eltype(program.parameter_defaults),
    shape = program.shape,
    attempts_per_site = program.attempts_per_site,
    rng = :Philox4x32x10V1,
    numerical_policy = (
        math = :accurate,
        reductions = :deterministic,
        bounds = :checked,
    ),
)

program_capability_report(program::CompiledPottsProgram) = (
    sequential = program.engine isa SequentialProgramEngine,
    checkerboard = program.engine isa CheckerboardProgramEngine,
    cpu = program.backend isa CPUProgramBackend,
    activity = program.activity !== nothing,
    field = program.field !== nothing && program.field.enabled,
)
