# Lower analyzed facts into the mechanism-free CorePotts program.

_statement_option(statement, name::Symbol, default = nothing) =
    haskey(_statement_options(statement), name) ?
    getproperty(_statement_options(statement), name) : default

_statement_option(record::QualifiedStatement, name::Symbol, default = nothing) =
    get(_record_options(record), name, default)

function _relation_offsets(
        source::FrozenSourceGraph,
        domain::QualifiedStatement,
        name::Symbol,
        dimensions::Int,
        fallback,
    )
    relation = _resource_record(source, domain, :SpatialRelation, name)
    relation === nothing && return _neighborhood_offsets(fallback, dimensions)
    neighborhood = _statement_option(relation, :neighborhood)
    neighborhood isa Union{VonNeumann, Moore} || throw(ArgumentError(
        "relation `$name` must use VonNeumann or Moore in V1"
    ))
    return _neighborhood_offsets(neighborhood, dimensions)
end

function _lower_relationships(
        ir::AnalyzedTermIR,
        relationship_endpoint_policies,
        manifest,
        ::Type{T},
    ) where {
        T <: AbstractFloat,
    }
    return Tuple(
        begin
            relationship = _relationship_policy_record(ir, policy)
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
        for policy in relationship_endpoint_policies
    )
end

function _token_suffix(value, prefix::AbstractString)
    name = String(Symbol(SymbolicIndexingInterface.getname(Symbolics.unwrap(value))))
    startswith(name, prefix) || return nothing
    return Symbol(name[(lastindex(prefix) + 1):end])
end

function _lower_observations(
        ir::AnalyzedTermIR,
        kinds,
        state_layout,
        relationship_endpoint_policies,
    )
    manifest = NamedTuple[]
    records = ir.source.records
    state_variables = Pair{QualifiedStatement, Any}[]
    for record in records
        record.kind in (
            :SiteState, :CellState, :MediumState, :ModelState, :FieldState,
            :HistoryState,
        ) || continue
        arguments = _record_arguments(record)
        haskey(arguments, :variable) || continue
        push!(state_variables, record => arguments.variable)
    end
    for record in records
        record.kind === :Observation || continue
        expression = _record_arguments(record).expression
        name = _qualified_public_name(record.identity)
        state_index = findfirst(
            pair -> isequal(expression, last(pair)), state_variables
        )
        if state_index !== nothing
            state_record = first(state_variables[state_index])
            state_name = _qualified_public_name(state_record.identity)
            identity = _qualified_resource_identity(state_record.identity)
            layout_entry = only(filter(
                entry -> entry.schema.identity == identity,
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
            requested = _token_suffix(first(arguments), "__potts_kind__")
            requested === nothing && throw(ArgumentError(
                "observation `$name` has an invalid occupancy kind"
            ))
            declaration = _resource_record(
                ir.source, record, :CellKind, requested
            )
            declaration === nothing && (declaration = _resource_record(
                ir.source, record, :MediumKind, requested
            ))
            declaration === nothing && throw(ArgumentError(
                "observation `$name` references an undeclared kind"
            ))
            push!(manifest, (
                name,
                kind = :occupied_sites,
                evaluator = OccupiedSitesObservationEvaluator(
                    Int16(kinds[declaration.identity])
                ),
            ))
        elseif operation in (neighbor_count, degree) && length(arguments) == 2
            requested = _token_suffix(
                first(arguments), "__potts_relationship_set__"
            )
            requested === nothing && throw(ArgumentError(
                "observation `$name` has an unsupported neighbor-count source"
            ))
            relationship = _resource_record(
                ir.source, record, :RelationshipState, requested
            )
            relationship === nothing && throw(ArgumentError(
                "observation `$name` references an undeclared relationship state"
            ))
            endpoint = _numeric_value(last(arguments))
            endpoint isa Integer || isinteger(endpoint) ||
                throw(ArgumentError("relationship degree endpoint must be integral"))
            endpoint_policy = _relationship_endpoint_policy(
                relationship_endpoint_policies, relationship.identity
            )
            push!(manifest, (
                name,
                kind = :relationship_degree,
                relationship_name = _qualified_public_name(
                    relationship.identity
                ),
                evaluator = RelationshipDegreeObservationEvaluator(
                    endpoint_policy.slot, Int32(endpoint)
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

function _protocol_settings(records, manifest, ::Type{T}) where {
        T <: AbstractFloat,
    }
    attempts = 1
    temperature_value = one(T)
    for record in records
        record.kind === :Protocol || continue
        for stage in _record_arguments(record).stages
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
        ir::AnalyzedTermIR,
        engine::AbstractPottsEngine,
        backend::AbstractPottsBackend,
        ::Type{T},
        manifest::ParameterManifest,
        descriptor_plan::CorePotts.DescriptorExecutionPlan,
        stage_plan::CorePotts.StageExecutionPlan,
        relationship_endpoint_policies,
        fingerprint_seed::String,
    ) where {T <: AbstractFloat}
    records = ir.source.records
    domains = filter(record -> record.kind === :LatticeDomain, records)
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

    declarations = _ordered_kind_records(records)
    isempty(declarations) &&
        throw(ArgumentError("V1 compilation requires declared cell/medium kinds"))
    kinds = Dict(
        declaration.identity => index
        for (index, declaration) in enumerate(declarations)
    )
    media = filter(record -> record.kind === :MediumKind, declarations)
    isempty(media) &&
        throw(ArgumentError("V1 compilation requires at least one MediumKind"))
    medium_kind = kinds[first(media).identity]
    medium_kinds = falses(length(kinds))
    for declaration in media
        medium_kinds[kinds[declaration.identity]] = true
    end
    count = length(kinds)
    defaults = _default_parameter_buffer(manifest, T)
    proposal_offsets = _relation_offsets(
        ir.source, domain, :proposal, dimensions, VonNeumann()
    )
    contact_offsets = _relation_offsets(
        ir.source, domain, :contact, dimensions, Moore()
    )
    attempts, temperature = _protocol_settings(records, manifest, T)
    relationships = _lower_relationships(
        ir, relationship_endpoint_policies, manifest, T
    )
    observation_manifest = _lower_observations(
        ir,
        kinds,
        descriptor_plan.state_layout,
        relationship_endpoint_policies,
    )
    core_engine = engine isa SequentialEngine ?
                  CorePotts.SequentialProgramEngine() :
                  CorePotts.CheckerboardProgramEngine()
    core_backend = CorePotts.CPUProgramBackend()
    tracker_plan = CorePotts.TrackerExecutionPlan(
        (CorePotts.OwnershipCountTracker(),),
        _sha256_hex("potts-tracker-plan-v1", :cell_volume),
    )
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
        Tuple((record.identity, kinds[record.identity]) for record in declarations),
        tracker_plan.fingerprint,
        descriptor_plan.fingerprint,
        stage_plan.fingerprint,
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
        tracker_plan,
        descriptor_plan,
        stage_plan,
        core_engine,
        core_backend,
        program_fingerprint;
        medium_kinds,
    ), Tuple((
        identity = _manifest_identity(declaration.identity),
        resource_identity = _qualified_resource_identity(declaration.identity),
        name = _qualified_public_name(declaration.identity),
        local_name = Symbol(declaration.identity.local_id),
        kind = declaration.kind,
    ) for declaration in declarations), observation_manifest
end
