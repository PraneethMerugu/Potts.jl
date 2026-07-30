_statement_option(statement, name::Symbol, default = nothing) =
    haskey(_statement_options(statement), name) ?
    getproperty(_statement_options(statement), name) : default

function _all_system_statements(system::PottsSystem)
    result = AbstractPottsStatement[]
    append!(result, statements(system))
    for child in getfield(system, :systems)
        append!(result, _all_system_statements(child))
    end
    return result
end

function _kind_name(kind::Union{CellKind, MediumKind})
    return Symbol(statement_id(kind))
end

function _neighborhood_offsets(neighborhood::VonNeumann, dimensions::Int)
    radius = neighborhood.radius
    offsets = NTuple{dimensions, Int}[]
    for dimension in 1:dimensions, distance in 1:radius
        push!(offsets, ntuple(i -> i == dimension ? distance : 0, dimensions))
        push!(offsets, ntuple(i -> i == dimension ? -distance : 0, dimensions))
    end
    return _offset_matrix(offsets, dimensions)
end

function _neighborhood_offsets(neighborhood::Moore, dimensions::Int)
    radius = neighborhood.radius
    ranges = ntuple(_ -> (-radius):radius, dimensions)
    offsets = NTuple{dimensions, Int}[]
    for candidate in Iterators.product(ranges...)
        all(iszero, candidate) && continue
        push!(offsets, Tuple(candidate))
    end
    sort!(offsets)
    return _offset_matrix(offsets, dimensions)
end

function _offset_matrix(offsets, dimensions)
    isempty(offsets) &&
        throw(ArgumentError("a spatial relation requires at least one offset"))
    result = Matrix{Int8}(undef, dimensions, length(offsets))
    for (column, offset) in enumerate(offsets), dimension in 1:dimensions
        typemin(Int8) <= offset[dimension] <= typemax(Int8) ||
            throw(ArgumentError("V1 relation radius exceeds Int8 storage"))
        result[dimension, column] = Int8(offset[dimension])
    end
    return result
end

function _relation_offsets(statements, name::Symbol, dimensions::Int, fallback)
    relation = findfirst(statement ->
        statement isa SpatialRelation &&
        Symbol(statement_id(statement)) === name, statements)
    relation === nothing && return _neighborhood_offsets(fallback, dimensions)
    neighborhood = _statement_option(statements[relation], :neighborhood)
    neighborhood isa Union{VonNeumann, Moore} || throw(ArgumentError(
        "relation `$name` must use VonNeumann or Moore in V1"
    ))
    return _neighborhood_offsets(neighborhood, dimensions)
end

function _lower_activity(statements, kinds, manifest, ::Type{T}, dimensions) where {
        T <: AbstractFloat,
    }
    term = findfirst(statement ->
        statement isa ProposalEnergy &&
        _statement_option(statement, :mechanism) === :activity, statements)
    term === nothing && return nothing
    statement = statements[term]
    kind = kinds[_kind_name(_statement_option(statement, :kind))]
    reduction = _statement_option(statement, :reduction, Moore())
    offsets = _neighborhood_offsets(reduction, dimensions)
    maximum = _compiled_scalar(_statement_option(statement, :maximum), manifest, T)
    strength = _compiled_scalar(_statement_option(statement, :strength), manifest, T)
    activity_state = _statement_option(statement, :activity)
    activate_extensions = any(statements) do candidate
        candidate isa AcceptedCopyProcess || return false
        arguments = _statement_arguments(candidate)
        any(arguments.effects) do effect
            effect isa Assign && isequal(effect.target, activity_state)
        end
    end
    decay = one(T)
    for candidate in statements
        candidate isa SynchronousProcess || continue
        arguments = _statement_arguments(candidate)
        any(effect -> effect isa Assign && isequal(effect.target, activity_state),
            arguments.effects) || continue
        decay = T(_numeric_value(_statement_option(candidate, :decay, one(T))))
    end
    return CorePotts.CompiledActivityPlan(
        Int16(kind), maximum, strength, offsets, activate_extensions, decay
    )
end

function _lower_field(statements, kinds, manifest, ::Type{T}) where {
        T <: AbstractFloat,
    }
    chemotaxis_index = findfirst(statement ->
        statement isa ProposalEnergy &&
        _statement_option(statement, :mechanism) === :chemotaxis, statements)
    chemotaxis_index === nothing && return nothing
    chemotaxis = statements[chemotaxis_index]
    field_ref = _statement_option(chemotaxis, :field)
    field_state_index = findfirst(statement ->
        statement isa FieldState && (
            isequal(statement, field_ref) ||
            Symbol(statement_id(statement)) ===
                (field_ref isa Symbol ? field_ref :
                 field_ref isa AbstractPottsStatement ?
                 Symbol(statement_id(field_ref)) : Symbol(""))
        ), statements)
    field_state_index === nothing && throw(ArgumentError(
        "chemotaxis references an undeclared FieldState"
    ))
    field_state = statements[field_state_index]
    kind = kinds[_kind_name(_statement_option(chemotaxis, :kind))]
    diffusion = _compiled_scalar(
        _statement_option(field_state, :diffusion, 0.0), manifest, T
    )
    decay = _compiled_scalar(
        _statement_option(field_state, :decay, 0.0), manifest, T
    )
    secretion = _compiled_scalar(
        _statement_option(field_state, :secretion, 0.0), manifest, T
    )
    strength = _compiled_scalar(
        _statement_option(chemotaxis, :strength), manifest, T
    )
    substeps = Int(_statement_option(field_state, :substeps, 1))
    substeps > 0 || throw(ArgumentError("field substeps must be positive"))
    duration = T(_numeric_value(
        _statement_option(field_state, :duration_per_mcs, 1.0)
    ))
    return CorePotts.CompiledFieldPlan(
        true,
        diffusion,
        decay,
        secretion,
        Int16(kind),
        strength,
        Int32(substeps),
        duration,
    )
end

function _protocol_settings(statements, manifest, ::Type{T}) where {
        T <: AbstractFloat,
    }
    attempts = 1
    temperature_value = one(T)
    for statement in statements
        statement isa Protocol || continue
        for stage in _statement_arguments(statement).stages
            stage isa SweepStage || continue
            attempts = stage.attempts.count
            if haskey(stage.options, :temperature)
                temperature_value = stage.options.temperature
            end
        end
    end
    return attempts, _compiled_scalar(temperature_value, manifest, T)
end

function _lower_core_program(
        completed::PottsSystem,
        engine::AbstractPottsEngine,
        backend::AbstractPottsBackend,
        ::Type{T},
        manifest::ParameterManifest,
        fingerprint_seed::String,
    ) where {T <: AbstractFloat}
    all_statements = _all_system_statements(completed)
    domains = filter(statement -> statement isa LatticeDomain, all_statements)
    length(domains) == 1 ||
        throw(ArgumentError("V1 compilation requires exactly one LatticeDomain"))
    domain = only(domains)
    shape = _statement_option(domain, :shape)
    shape isa Tuple{Vararg{Int}} ||
        throw(ArgumentError("lattice shape must be resolved to integer dimensions"))
    dimensions = length(shape)
    dimensions > 0 || throw(ArgumentError("lattice must have positive dimension"))
    boundary = _statement_option(domain, :boundary, Periodic())
    periodic = if boundary isa Periodic
        ntuple(_ -> true, dimensions)
    elseif boundary isa Union{Closed, FrozenBorder}
        ntuple(_ -> false, dimensions)
    else
        throw(ArgumentError("unsupported V1 lattice boundary $(typeof(boundary))"))
    end

    declarations = filter(
        statement -> statement isa Union{CellKind, MediumKind}, all_statements
    )
    isempty(declarations) &&
        throw(ArgumentError("V1 compilation requires declared cell/medium kinds"))
    sorted_declarations = sort(declarations; by = statement ->
        (statement isa MediumKind ? 0 : 1, String(Symbol(statement_id(statement)))))
    kinds = Dict{Symbol, Int}()
    for (index, declaration) in enumerate(sorted_declarations)
        name = _kind_name(declaration)
        haskey(kinds, name) &&
            throw(ArgumentError("duplicate kind `$name`"))
        kinds[name] = index
    end
    media = filter(statement -> statement isa MediumKind, sorted_declarations)
    length(media) == 1 ||
        throw(ArgumentError("V1 compilation requires exactly one MediumKind"))
    medium_kind = kinds[_kind_name(only(media))]
    count = length(kinds)
    defaults = _default_parameter_buffer(manifest, T)
    zero_scalar = CorePotts.CompiledScalar(zero(T))
    volume_targets = fill(zero_scalar, count)
    volume_strengths = fill(zero_scalar, count)
    contact_energies = fill(zero_scalar, count, count)
    connectivity_kinds = falses(count)

    for statement in all_statements
        mechanism = _statement_option(statement, :mechanism)
        if statement isa ProposalEnergy && mechanism === :volume
            kind = kinds[_kind_name(_statement_option(statement, :kind))]
            volume_targets[kind] = _compiled_scalar(
                _statement_option(statement, :target), manifest, T
            )
            volume_strengths[kind] = _compiled_scalar(
                _statement_option(statement, :strength), manifest, T
            )
        elseif statement isa ProposalEnergy && mechanism === :contact
            for law in _statement_option(statement, :laws, ())
                pair = first(law)
                energy = _compiled_scalar(last(law), manifest, T)
                first_kind = kinds[_kind_name(pair.first)]
                second_kind = kinds[_kind_name(pair.second)]
                contact_energies[first_kind, second_kind] = energy
                contact_energies[second_kind, first_kind] = energy
            end
        elseif statement isa ProposalConstraint &&
                mechanism === :local_connectivity
            kind = kinds[_kind_name(_statement_option(statement, :kind))]
            connectivity_kinds[kind] = true
        elseif statement isa ProposalEnergy &&
                !(mechanism in (:volume, :contact, :activity, :chemotaxis))
            throw(ArgumentError(
                "no V1 lowering is registered for ProposalEnergy mechanism " *
                "$(repr(mechanism))"
            ))
        end
    end

    proposal_offsets = _relation_offsets(
        all_statements, :proposal, dimensions, VonNeumann()
    )
    contact_offsets = _relation_offsets(
        all_statements, :contact, dimensions, Moore()
    )
    attempts, temperature = _protocol_settings(all_statements, manifest, T)
    activity = _lower_activity(all_statements, kinds, manifest, T, dimensions)
    field = _lower_field(all_statements, kinds, manifest, T)
    core_engine = engine isa SequentialEngine ?
                  CorePotts.SequentialProgramEngine() :
                  CorePotts.CheckerboardProgramEngine()
    core_backend = CorePotts.CPUProgramBackend()
    program_fingerprint = _sha256_hex(
        "core-program-v1",
        fingerprint_seed,
        nameof(typeof(engine)),
        nameof(typeof(backend)),
        T,
        shape,
        periodic,
        proposal_offsets,
        contact_offsets,
        sort(collect(kinds); by = first),
    )
    return CorePotts.CompiledPottsProgram(
        shape,
        periodic,
        proposal_offsets,
        contact_offsets,
        count,
        medium_kind,
        volume_targets,
        volume_strengths,
        contact_energies,
        connectivity_kinds,
        temperature,
        attempts,
        defaults,
        activity,
        field,
        core_engine,
        core_backend,
        program_fingerprint,
    ), Tuple(sorted_declarations)
end
