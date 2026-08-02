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

function _lower_observations(
        ir::AnalyzedTermIR,
        kinds,
        state_layout,
        relationship_endpoint_policies,
    )
    manifest = NamedTuple[]
    records = ir.source.records
    for (record_index, record) in enumerate(records)
        record.kind === :Observation || continue
        name = _qualified_public_name(record.identity)
        root_index = findfirst(
            root -> root.record == record_index && root.role === :expression,
            ir.graph.roots,
        )
        root_index === nothing && throw(ArgumentError(
            "observation `$name` has no normalized expression root"
        ))
        root = ir.graph.roots[root_index]
        node = ir.graph.nodes[Int(root.node)]
        if node.payload isa StateBindingPayload
            state_identity = node.payload.identity
            state_index = findfirst(
                candidate -> candidate.identity == state_identity,
                records,
            )
            state_index === nothing && throw(ArgumentError(
                "observation `$name` references an unresolved state"
            ))
            state_record = records[state_index]
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
        if node.operation === :occupancy && length(node.operands) == 2
            kind_node = ir.graph.nodes[Int(first(node.operands))]
            kind_node.payload isa KindBindingPayload || throw(ArgumentError(
                "observation `$name` has no resolved kind binding"
            ))
            haskey(kinds, kind_node.payload.identity) || throw(ArgumentError(
                "observation `$name` references an undeclared kind"
            ))
            push!(manifest, (
                name,
                kind = :occupied_sites,
                evaluator = OccupiedSitesObservationEvaluator(
                    Int16(kinds[kind_node.payload.identity])
                ),
            ))
        elseif node.operation in (:neighbor_count, :degree) &&
                length(node.operands) == 2
            relationship_node = ir.graph.nodes[Int(first(node.operands))]
            relationship_node.payload isa ResourceBindingPayload &&
                relationship_node.payload.kind === :RelationshipState ||
                throw(ArgumentError(
                    "observation `$name` has no resolved relationship binding"
                ))
            relationship_index = findfirst(
                candidate -> candidate.identity ==
                    relationship_node.payload.identity,
                records,
            )
            relationship_index === nothing && throw(ArgumentError(
                "observation `$name` references an undeclared relationship state"
            ))
            relationship = records[relationship_index]
            endpoint_node = ir.graph.nodes[Int(last(node.operands))]
            endpoint_node.payload isa LiteralPayload || throw(ArgumentError(
                "relationship degree endpoint must be a normalized literal"
            ))
            endpoint = _numeric_value(endpoint_node.payload.value)
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
                "$(node.operation)"
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

function _append_relative_write_offsets!(
        values::Vector{NTuple{N, Int}},
        ::CorePotts.EmptyFootprint,
        proposal_offsets,
    ) where {N}
    return values
end

function _append_relative_write_offsets!(
        values::Vector{NTuple{N, Int}},
        footprint::CorePotts.FiniteSpatialFootprint,
        proposal_offsets,
    ) where {N}
    base_offsets = if footprint.anchor isa
            CorePotts.ProposalTargetFootprintAnchor
        (ntuple(_ -> 0, N),)
    elseif footprint.anchor isa CorePotts.ProposalSourceFootprintAnchor
        Tuple(
            ntuple(dimension -> Int(proposal_offsets[dimension, column]), N)
            for column in axes(proposal_offsets, 2)
        )
    else
        throw(ArgumentError(
            "checkerboard exclusive writes require a proposal source/target anchor"
        ))
    end
    for base in base_offsets, offset in footprint.offsets
        length(offset) == N || throw(ArgumentError(
            "exclusive write footprint has the wrong dimensionality"
        ))
        push!(values, ntuple(
            dimension -> base[dimension] + Int(offset[dimension]), N
        ))
    end
    return values
end

function _append_relative_write_offsets!(
        values::Vector{NTuple{N, Int}},
        footprint::CorePotts.FootprintUnion,
        proposal_offsets,
    ) where {N}
    for member in footprint.footprints
        _append_relative_write_offsets!(values, member, proposal_offsets)
    end
    return values
end

function _append_relative_write_offsets!(
        values::Vector{NTuple{N, Int}},
        footprint::CorePotts.AbstractFootprint,
        proposal_offsets,
    ) where {N}
    throw(ArgumentError(
        "checkerboard cannot prove exclusive write footprint $(typeof(footprint))"
    ))
end

function _append_exclusive_access!(
        resources,
        access::CorePotts.ResourceAccess,
        proposal_offsets,
        ::Val{N},
    ) where {N}
    policy = access.write_policy
    policy isa CorePotts.NoWriteAccess && return resources
    policy isa Union{
        CorePotts.CommutativeIntegerWriteAccess,
        CorePotts.DeferredRequestWriteAccess,
    } && return resources
    policy isa CorePotts.ExclusiveWriteAccess || throw(ArgumentError(
        "checkerboard encountered an unknown write-access policy"
    ))
    offsets = NTuple{N, Int}[]
    _append_relative_write_offsets!(
        offsets, access.write_footprint, proposal_offsets
    )
    isempty(offsets) && throw(ArgumentError(
        "checkerboard exclusive write access has no finite spatial offsets"
    ))
    for resource in access.writes
        append!(get!(resources, resource, NTuple{N, Int}[]), offsets)
    end
    return resources
end

function _checkerboard_conflict_displacements(
        accesses::AbstractVector{<:CorePotts.ResourceAccess},
        proposal_offsets,
        ::Val{N},
    ) where {N}
    resources = Dict{Any, Vector{NTuple{N, Int}}}(
        :ownership => [ntuple(_ -> 0, N)]
    )
    for access in accesses
        _append_exclusive_access!(
            resources, access, proposal_offsets, Val(N)
        )
    end
    displacements = NTuple{N, Int}[]
    for offsets in Base.values(resources)
        sort!(unique!(offsets))
        for left in offsets, right in offsets
            push!(displacements, ntuple(
                dimension -> left[dimension] - right[dimension], N
            ))
        end
    end
    filter!(offset -> !all(iszero, offset), displacements)
    sort!(unique!(displacements))
    matrix = Matrix{Int16}(undef, N, length(displacements))
    for (column, offset) in enumerate(displacements), dimension in 1:N
        typemin(Int16) <= offset[dimension] <= typemax(Int16) || throw(
            ArgumentError("checkerboard footprint displacement exceeds Int16")
        )
        matrix[dimension, column] = Int16(offset[dimension])
    end
    return matrix
end

function _checkerboard_conflict_displacements(
        descriptor_plan::CorePotts.DescriptorExecutionPlan,
        stage_plan::CorePotts.StageExecutionPlan,
        proposal_offsets,
        ::Val{N},
    ) where {N}
    accesses = CorePotts.ResourceAccess[]
    for group in descriptor_plan.groups
        for descriptor in group.launch.instances
            push!(
                accesses,
                CorePotts.descriptor_resource_access(descriptor),
            )
        end
    end
    for group in stage_plan.accepted_copy
        for descriptor in group.instances
            push!(
                accesses,
                CorePotts.descriptor_resource_access(descriptor),
            )
        end
    end
    return _checkerboard_conflict_displacements(
        accesses, proposal_offsets, Val(N)
    )
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
    tracker_plan = _lower_tracker_plan(ir, engine, T)
    checkerboard_plan = if core_engine isa CorePotts.CheckerboardProgramEngine
        conflicts = _checkerboard_conflict_displacements(
            descriptor_plan,
            stage_plan,
            proposal_offsets,
            Val(dimensions),
        )
        CorePotts.CheckerboardPlan(shape, periodic, conflicts)
    else
        CorePotts.NoCheckerboardPlan()
    end
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
        CorePotts.checkerboard_plan_report(checkerboard_plan),
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
        checkerboard_plan,
    ), Tuple((
        identity = _manifest_identity(declaration.identity),
        resource_identity = _qualified_resource_identity(declaration.identity),
        name = _qualified_public_name(declaration.identity),
        local_name = Symbol(declaration.identity.local_id),
        kind = declaration.kind,
    ) for declaration in declarations), observation_manifest
end
