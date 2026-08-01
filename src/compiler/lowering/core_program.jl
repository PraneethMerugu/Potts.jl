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

function _lower_relationships(statements, manifest, ::Type{T}) where {
        T <: AbstractFloat,
    }
    resources = _ordered_relationships(statements)
    return Tuple(
        begin
            capacity = _numeric_value(
                _statement_option(relationship, :capacity)
            )
            maximum_degree = _numeric_value(
                _statement_option(relationship, :maximum_degree)
            )
            capacity isa Real && isinteger(capacity) || throw(ArgumentError(
                "relationship capacity must be structurally resolved"
            ))
            maximum_degree isa Real && isinteger(maximum_degree) || throw(
                ArgumentError(
                    "relationship maximum_degree must be structurally resolved"
                )
            )
            payload = _statement_option(
                relationship, :payload, NamedTuple()
            )
            payload isa NamedTuple || throw(ArgumentError(
                "relationship payload declaration must be a named tuple"
            ))
            defaults = Tuple(
                _compiled_scalar(getproperty(payload, name), manifest, T)
                for name in keys(payload)
            )
            CorePotts.RelationshipStoreSchema(
                Int(capacity),
                Int(maximum_degree),
                defaults,
            )
        end
        for relationship in resources
    )
end

function _token_suffix(value, prefix::AbstractString)
    name = String(Symbol(SymbolicIndexingInterface.getname(Symbolics.unwrap(value))))
    startswith(name, prefix) || return nothing
    return Symbol(name[(lastindex(prefix) + 1):end])
end

function _lower_observations(statements, kinds, state_layout)
    manifest = NamedTuple[]
    state_variables = Dict{Any, Symbol}()
    for statement in statements
        statement isa Union{
            SiteState, CellState, MediumState, ModelState, FieldState,
            HistoryState,
        } || continue
        arguments = _statement_arguments(statement)
        haskey(arguments, :variable) || continue
        state_variables[arguments.variable] = Symbol(statement_id(statement))
    end
    relationship_names = Symbol[
        Symbol(statement_id(statement))
        for statement in _ordered_relationships(statements)
    ]
    for statement in statements
        statement isa Observation || continue
        expression = _statement_arguments(statement).expression
        name = Symbol(statement_id(statement))
        if any(variable -> isequal(expression, variable), keys(state_variables))
            state_name = state_variables[expression]
            layout_entry = only(filter(
                entry -> entry.schema.identity.name === state_name,
                state_layout.entries,
            ))
            push!(manifest, (
                name,
                kind = :state_export,
                state_name,
                evaluator = StateExportObservationEvaluator(
                    layout_entry.handle
                ),
            ))
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
            push!(manifest, (
                name,
                kind = :occupied_sites,
                evaluator = OccupiedSitesObservationEvaluator(
                    Int16(kinds[kind_name])
                ),
            ))
        elseif operation in (neighbor_count, degree) && length(arguments) == 2
            relationship_name = _token_suffix(
                first(arguments), "__potts_relationship_set__"
            )
            relationship_name === nothing && throw(ArgumentError(
                "observation `$name` has an unsupported neighbor-count source"
            ))
            endpoint = _numeric_value(last(arguments))
            endpoint isa Integer || isinteger(endpoint) ||
                throw(ArgumentError("relationship degree endpoint must be integral"))
            relationship_slot = findfirst(==(relationship_name), relationship_names)
            relationship_slot === nothing && throw(ArgumentError(
                "observation `$name` references an undeclared relationship state"
            ))
            push!(manifest, (
                name,
                kind = :relationship_degree,
                relationship_name,
                evaluator = RelationshipDegreeObservationEvaluator(
                    Int32(relationship_slot), Int32(endpoint)
                ),
            ))
        else
            throw(ArgumentError(
                "no concrete V1 observation lowering exists for `$name`: " *
                "$(repr(expression))"
            ))
        end
    end
    return Tuple(manifest)
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
        stage_plan::CorePotts.StageExecutionPlan,
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
    proposal_offsets = _relation_offsets(
        all_statements, :proposal, dimensions, VonNeumann()
    )
    contact_offsets = _relation_offsets(
        all_statements, :contact, dimensions, Moore()
    )
    attempts, temperature = _protocol_settings(all_statements, manifest, T)
    relationships = _lower_relationships(all_statements, manifest, T)
    observation_manifest = _lower_observations(
        all_statements, kinds, descriptor_plan.state_layout
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
        count,
        medium_kind,
        temperature,
        attempts,
        defaults,
        relationships,
        descriptor_plan,
        stage_plan,
        core_engine,
        core_backend,
        program_fingerprint;
        medium_kinds,
    ), Tuple(_kind_name(declaration) for declaration in sorted_declarations),
       observation_manifest
end
