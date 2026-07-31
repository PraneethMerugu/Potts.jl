# Lower analyzed facts into the mechanism-free CorePotts program.

_statement_option(statement, name::Symbol, default = nothing) =
    haskey(_statement_options(statement), name) ?
    getproperty(_statement_options(statement), name) : default

function _all_system_statements(
        system::PottsSystem, namespace::Tuple = ()
    )
    result = AbstractPottsStatement[]
    append!(
        result,
        (
            _namespace_statement_for_lowering(statement, namespace)
            for statement in statements(system)
        ),
    )
    for child in getfield(system, :systems)
        append!(
            result,
            _all_system_statements(
                child, (namespace..., nameof(child))
            ),
        )
    end
    return result
end

function _kind_name(kind::Union{CellKind, MediumKind})
    return Symbol(statement_id(kind))
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
        statement isa ProposalDrive &&
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

function _lower_field(
        statements, kinds, manifest, ::Type{T}, dimensions
    ) where {
        T <: AbstractFloat,
    }
    field_states = filter(statement -> statement isa FieldState, statements)
    isempty(field_states) && return nothing
    length(field_states) == 1 || throw(ArgumentError(
        "the V1 runtime currently supports one FieldState per executable"
    ))
    field_state = only(field_states)
    chemotaxis_index = findfirst(statement ->
        statement isa ProposalDrive &&
        _statement_option(statement, :mechanism) === :chemotaxis, statements)
    chemotaxis = chemotaxis_index === nothing ?
                  nothing : statements[chemotaxis_index]
    if chemotaxis !== nothing
        field_ref = _statement_option(chemotaxis, :field)
        isequal(field_state, field_ref) ||
            Symbol(statement_id(field_state)) ===
            (field_ref isa Symbol ? field_ref :
             field_ref isa AbstractPottsStatement ?
             Symbol(statement_id(field_ref)) : Symbol("")) ||
            throw(ArgumentError(
                "chemotaxis references an undeclared FieldState"
            ))
    end
    source_kind_ref = _statement_option(
        field_state,
        :source_kind,
        chemotaxis === nothing ? nothing :
        _statement_option(chemotaxis, :kind),
    )
    source_kind = source_kind_ref === nothing ? 0 :
                  kinds[_kind_name(source_kind_ref)]
    chemotaxis_kind = chemotaxis === nothing ? 0 :
                       kinds[_kind_name(_statement_option(chemotaxis, :kind))]
    diffusion = _compiled_scalar(
        _statement_option(field_state, :diffusion, 0.0), manifest, T
    )
    decay = _compiled_scalar(
        _statement_option(field_state, :decay, 0.0), manifest, T
    )
    secretion = _compiled_scalar(
        _statement_option(field_state, :secretion, 0.0), manifest, T
    )
    strength = chemotaxis === nothing ?
               CorePotts.CompiledScalar(zero(T)) :
               _compiled_scalar(
                   _statement_option(chemotaxis, :strength), manifest, T
               )
    substeps = Int(_statement_option(field_state, :substeps, 1))
    substeps > 0 || throw(ArgumentError("field substeps must be positive"))
    duration_value = _statement_option(
        field_state, :duration_per_mcs, 1.0
    )
    duration = T(_numeric_value(
        duration_value,
        _reference_for(manifest.reference_units, duration_value),
    ))
    stencil_offsets = _relation_offsets(
        statements, :field_stencil, dimensions, VonNeumann()
    )
    return CorePotts.CompiledFieldPlan(
        true,
        diffusion,
        decay,
        secretion,
        Int16(source_kind),
        Int16(chemotaxis_kind),
        strength,
        stencil_offsets,
        Int32(substeps),
        duration,
    )
end

function _lower_history(statements)
    histories = filter(statement -> statement isa HistoryState, statements)
    isempty(histories) && return nothing
    length(histories) == 1 || throw(ArgumentError(
        "the V1 runtime currently supports one HistoryState per executable"
    ))
    statement = only(histories)
    source = _statement_option(statement, :of, nothing)
    source === nothing && throw(ArgumentError(
        "HistoryState requires an explicit `of` source in V1"
    ))
    activity_states = filter(candidate ->
        candidate isa SiteState &&
        isequal(_statement_arguments(candidate).variable, source), statements)
    length(activity_states) == 1 || throw(ArgumentError(
        "V1 history source must identify one declared SiteState"
    ))
    depth = _numeric_value(_statement_option(statement, :depth, 1))
    depth isa Real && isinteger(depth) ||
        throw(ArgumentError("history depth must be structurally resolved"))
    return CorePotts.CompiledHistoryPlan(Int(depth), :activity)
end

function _lower_relationships(statements, kinds, manifest, ::Type{T}) where {
        T <: AbstractFloat,
    }
    resources = filter(statement -> statement isa RelationshipState, statements)
    isempty(resources) && return nothing
    length(resources) == 1 || throw(ArgumentError(
        "the V1 runtime currently supports one RelationshipState per executable"
    ))
    relationship = only(resources)
    endpoints = _statement_option(relationship, :endpoints)
    endpoints isa Undirected || throw(ArgumentError(
        "V1 relationship lowering currently requires Undirected endpoints"
    ))
    kind_a = kinds[_kind_name(endpoints.kind_a)]
    kind_b = kinds[_kind_name(endpoints.kind_b)]
    capacity = _numeric_value(_statement_option(relationship, :capacity))
    maximum_degree =
        _numeric_value(_statement_option(relationship, :maximum_degree))
    capacity isa Real && isinteger(capacity) ||
        throw(ArgumentError("relationship capacity must be structurally resolved"))
    maximum_degree isa Real && isinteger(maximum_degree) || throw(ArgumentError(
        "relationship maximum_degree must be structurally resolved"
    ))
    payload = _statement_option(relationship, :payload, NamedTuple())
    all(name -> haskey(payload, name), (:strength, :target, :maximum)) ||
        throw(ArgumentError(
            "relationship payload requires strength, target, and maximum"
        ))
    strength = _compiled_scalar(payload.strength, manifest, T)
    target = _compiled_scalar(payload.target, manifest, T)
    maximum = _compiled_scalar(payload.maximum, manifest, T)
    create_on_copy = any(statements) do candidate
        candidate isa AcceptedCopyProcess || return false
        any(_statement_arguments(candidate).effects) do effect
            effect isa Create && isequal(effect.relationship, relationship)
        end
    end
    break_after_mcs = any(statements) do candidate
        candidate isa Union{RelationshipProcess, LifecycleProcess} || return false
        any(_statement_arguments(candidate).effects) do effect
            effect isa Remove && isequal(effect.relationship, relationship)
        end
    end
    lifecycle = _statement_option(
        relationship, :lifecycle, RejectEndpointRetirement()
    )
    lifecycle isa Union{RemoveWithEndpoint, RejectEndpointRetirement} ||
        throw(ArgumentError("unsupported relationship lifecycle policy"))
    remove_with_endpoint = lifecycle isa RemoveWithEndpoint
    return CorePotts.CompiledRelationshipPlan(
        Int(capacity),
        Int(maximum_degree),
        kind_a,
        kind_b,
        strength,
        target,
        maximum;
        create_on_accepted_copy = create_on_copy,
        break_after_mcs,
        remove_with_endpoint,
    )
end

function _lower_elongation(statements, kinds, manifest, ::Type{T}) where {
        T <: AbstractFloat,
    }
    terms = filter(statement ->
        statement isa HamiltonianTerm &&
        _statement_option(statement, :mechanism) === :elongation, statements)
    isempty(terms) && return nothing
    length(terms) == 1 || throw(ArgumentError(
        "the V1 runtime currently supports one elongation term"
    ))
    term = only(terms)
    kind = kinds[_kind_name(_statement_option(term, :kind))]
    return CorePotts.CompiledElongationPlan(
        Int16(kind),
        _compiled_scalar(_statement_option(term, :target), manifest, T),
        _compiled_scalar(_statement_option(term, :strength), manifest, T),
    )
end

function _token_suffix(value, prefix::AbstractString)
    name = String(Symbol(SymbolicIndexingInterface.getname(Symbolics.unwrap(value))))
    startswith(name, prefix) || return nothing
    return Symbol(name[(lastindex(prefix) + 1):end])
end

function _lower_observations(statements, kinds)
    plans = CorePotts.AbstractProgramObservation[]
    manifest = NamedTuple[]
    field_variables = Dict{Any, Symbol}()
    for statement in statements
        statement isa FieldState || continue
        arguments = _statement_arguments(statement)
        haskey(arguments, :variable) || continue
        field_variables[arguments.variable] = Symbol(statement_id(statement))
    end
    for statement in statements
        statement isa Observation || continue
        expression = _statement_arguments(statement).expression
        name = Symbol(statement_id(statement))
        if any(variable -> isequal(expression, variable), keys(field_variables))
            push!(plans, CorePotts.FieldStateObservation())
            push!(manifest, (name, kind = :field_state))
            continue
        end
        unwrapped = Symbolics.unwrap(expression)
        operation = try
            Symbolics.operation(unwrapped)
        catch
            nothing
        end
        arguments = try
            Symbolics.arguments(unwrapped)
        catch
            Any[]
        end
        if operation === occupancy && length(arguments) == 2
            kind_name = _token_suffix(first(arguments), "__potts_kind__")
            kind_name === nothing && throw(ArgumentError(
                "observation `$name` has an invalid occupancy kind"
            ))
            push!(plans, CorePotts.OccupiedSitesObservation(
                Int16(kinds[kind_name])
            ))
            push!(manifest, (name, kind = :occupied_sites))
        elseif operation === neighbor_count && length(arguments) == 2
            relationship_name = _token_suffix(
                first(arguments), "__potts_relationship_set__"
            )
            relationship_name === nothing && throw(ArgumentError(
                "observation `$name` has an unsupported neighbor-count source"
            ))
            endpoint = _numeric_value(last(arguments))
            endpoint isa Integer || isinteger(endpoint) ||
                throw(ArgumentError("relationship degree endpoint must be integral"))
            push!(plans, CorePotts.RelationshipDegreeObservation(
                Int32(endpoint)
            ))
            push!(manifest, (
                name, kind = :relationship_degree, relationship_name
            ))
        else
            throw(ArgumentError(
                "no concrete V1 observation lowering exists for `$name`: " *
                "$(repr(expression))"
            ))
        end
    end
    return Tuple(plans), Tuple(manifest)
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
        descriptor_plan::CorePotts.DescriptorExecutionPlan,
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
    isempty(media) &&
        throw(ArgumentError("V1 compilation requires at least one MediumKind"))
    medium_kind = kinds[_kind_name(first(media))]
    medium_kinds = falses(length(kinds))
    for declaration in media
        medium_kinds[kinds[_kind_name(declaration)]] = true
    end
    count = length(kinds)
    defaults = _default_parameter_buffer(manifest, T)
    zero_scalar = CorePotts.CompiledScalar(zero(T))
    volume_targets = fill(zero_scalar, count)
    volume_strengths = fill(zero_scalar, count)
    contact_energies = fill(zero_scalar, count, count)
    connectivity_kinds = falses(count)

    for statement in all_statements
        mechanism = _statement_option(statement, :mechanism)
        if statement isa HamiltonianTerm && mechanism === :volume
            kind = kinds[_kind_name(_statement_option(statement, :kind))]
            volume_targets[kind] = _compiled_scalar(
                _statement_option(statement, :target), manifest, T
            )
            volume_strengths[kind] = _compiled_scalar(
                _statement_option(statement, :strength), manifest, T
            )
        elseif statement isa HamiltonianTerm && mechanism === :contact
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
        elseif statement isa HamiltonianTerm &&
                !(mechanism in (
                    nothing, :symbolic,
                    :volume, :contact, :relationship, :elongation,
                ))
            throw(ArgumentError(
                "no V1 lowering is registered for HamiltonianTerm mechanism " *
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
    field = _lower_field(all_statements, kinds, manifest, T, dimensions)
    history = _lower_history(all_statements)
    elongation = _lower_elongation(all_statements, kinds, manifest, T)
    relationships = _lower_relationships(all_statements, kinds, manifest, T)
    observations, observation_manifest =
        _lower_observations(all_statements, kinds)
    cell_state_fields = Tuple(
        Symbol(statement_id(statement))
        for statement in all_statements
        if statement isa CellState &&
           haskey(_statement_arguments(statement), :variable)
    )
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
        history,
        elongation,
        relationships,
        observations,
        descriptor_plan,
        core_engine,
        core_backend,
        program_fingerprint;
        medium_kinds,
        cell_state_fields,
    ), Tuple(_kind_name(declaration) for declaration in sorted_declarations),
       observation_manifest
end
