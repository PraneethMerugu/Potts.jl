# Lower analyzed lifecycle facts into one mechanism-neutral CorePotts plan.

mutable struct _LifecycleRootCursor
    roots::Dict{Symbol, Vector{Int32}}
    positions::Dict{Symbol, Int}
    operation_abis::Tuple
end

function _LifecycleRootCursor(
        ir::AnalyzedTermIR, record_index::Integer, operation_abis::Tuple
    )
    roots = Dict{Symbol, Vector{Int32}}()
    for root in ir.graph.roots
        root.record == record_index || continue
        root.role in _LIFECYCLE_ROOT_ROLES || continue
        push!(get!(roots, root.role, Int32[]), root.node)
    end
    return _LifecycleRootCursor(roots, Dict{Symbol, Int}(), operation_abis)
end

function _next_lifecycle_root!(cursor::_LifecycleRootCursor, role::Symbol)
    values = get(cursor.roots, role, Int32[])
    position = get(cursor.positions, role, 0) + 1
    position <= length(values) || throw(ArgumentError(
        "normalized lifecycle root `$role` is missing at occurrence $position"
    ))
    cursor.positions[role] = position
    return values[position]
end

function _next_lifecycle_abi(cursor::_LifecycleRootCursor, role::Symbol)
    values = get(cursor.roots, role, Int32[])
    position = get(cursor.positions, role, 0) + 1
    position <= length(values) || throw(ArgumentError(
        "normalized lifecycle root `$role` is missing at occurrence $position"
    ))
    root = values[position]
    for item in cursor.operation_abis
        item.root_node == root && item.node == root && item.role === role ||
            continue
        return item.abi
    end
    return nothing
end

function _lifecycle_context_type(role::Symbol)
    role === :lifecycle_trigger &&
        return CorePotts.AbstractLifecycleTriggerEvaluationContext
    role === :lifecycle_placement &&
        return CorePotts.AbstractLifecyclePlacementEvaluationContext
    role === :lifecycle_partition &&
        return CorePotts.AbstractLifecyclePartitionEvaluationContext
    role === :lifecycle_state_transform &&
        return CorePotts.AbstractLifecycleStateTransformEvaluationContext
    throw(ArgumentError("unsupported lifecycle evaluator role `$role`"))
end

function _lifecycle_role_workspace_maximum(fact, role::Symbol)
    maxima = Int[
        item.workspace_offset + item.abi.workspace_maximum
        for item in fact.operation_abis
        if item.role === role
    ]
    return isempty(maxima) ? 0 : maximum(maxima)
end

function _lifecycle_workspace_slices(
        cursor::_LifecycleRootCursor, root::Int32, role::Symbol
    )
    slices = Dict{Int32, NamedTuple{(:offset, :maximum), Tuple{Int, Int}}}()
    for item in cursor.operation_abis
        item.root_node == root && item.role === role || continue
        slices[item.node] = (
            offset = item.workspace_offset,
            maximum = item.abi.workspace_maximum,
        )
    end
    return slices
end

function _lifecycle_evaluator!(
        evaluators::Vector{Any},
        ir::AnalyzedTermIR,
        record_index::Integer,
        role::Symbol,
        value,
        cursor::_LifecycleRootCursor,
        manifest::ParameterManifest,
        ::Type{T},
        state_handles,
        draw_handles,
        ;
        always_root::Bool = false,
    ) where {T <: AbstractFloat}
    symbolic = !(SymbolicIndexingInterface.symbolic_type(value) isa
        SymbolicIndexingInterface.NotSymbolic)
    expression = if always_root || symbolic
        root = _next_lifecycle_root!(cursor, role)
        workspace_slices = _lifecycle_workspace_slices(cursor, root, role)
        _lower_static_node(
            ir.graph,
            ir,
            root,
            manifest,
            T,
            state_handles,
            draw_handles,
            Dict{Int32, CorePotts.AbstractStaticExpression}(),
            role,
            workspace_slices,
        )
    else
        _static_literal(value, manifest, T)
    end
    evaluator = _static_evaluator(
        expression,
        _lifecycle_context_type(role),
        ir.source.records[record_index],
    )
    push!(evaluators, evaluator)
    return Int32(length(evaluators))
end

function _lifecycle_hash64(value)
    digest = SHA.sha256(codeunits(_canonical_value(value)))
    result = UInt64(0)
    for index in 1:8
        result = (result << 8) | UInt64(digest[index])
    end
    return result
end

function _lifecycle_cadence(value)
    value isa EveryMCS && return (
        CorePotts.EveryMCSLifecycleCadence, Int32(1)
    )
    value isa AtMCS && return (
        CorePotts.AtMCSLifecycleCadence, Int32(value.mcs)
    )
    value isa Every && return (
        CorePotts.PeriodicLifecycleCadence, Int32(value.cadence)
    )
    throw(ArgumentError("unsupported compiled lifecycle cadence $(typeof(value))"))
end

_lifecycle_disposition(::FilterInadmissible) =
    CorePotts.FilterLifecycleInadmissible
_lifecycle_disposition(::ErrorOnInadmissible) =
    CorePotts.ErrorLifecycleInadmissible

function _lifecycle_kind_index(ir, record, value)
    index = _compiled_kind_index(ir, record, value)
    index === nothing && throw(ArgumentError(
        "lifecycle kind does not resolve to a compiled kind index"
    ))
    return index
end

function _lifecycle_relation!(relations, ir, record, value)
    relation = _resource_record(ir.source, record, :SpatialRelation, value)
    relation === nothing && throw(ArgumentError(
        "lifecycle relation does not resolve to a SpatialRelation"
    ))
    neighborhood = _statement_option(relation, :neighborhood)
    neighborhood isa Union{VonNeumann, Moore} || throw(ArgumentError(
        "lifecycle relation requires a VonNeumann or Moore neighborhood"
    ))
    dimensions = length(_lattice_shape(ir))
    offsets = _neighborhood_offsets(neighborhood, dimensions)
    existing = findfirst(candidate -> candidate == offsets, relations)
    existing === nothing && push!(relations, offsets)
    return Int32(existing === nothing ? length(relations) : existing)
end

function _lifecycle_site_value(value, shape)
    numeric = value isa Tuple || value isa CartesianIndex ? value :
        _numeric_value(value)
    if numeric isa Integer
        1 <= numeric <= prod(shape) || throw(ArgumentError(
            "lifecycle site lies outside the compiled lattice"
        ))
        return Int(numeric)
    elseif numeric isa CartesianIndex
        checkbounds(Bool, CartesianIndices(shape), numeric) || throw(
            ArgumentError("lifecycle site lies outside the compiled lattice")
        )
        return LinearIndices(shape)[numeric]
    elseif numeric isa Tuple && length(numeric) == length(shape) &&
            all(item -> item isa Integer, numeric)
        site = CartesianIndex(Int.(numeric))
        checkbounds(Bool, CartesianIndices(shape), site) || throw(
            ArgumentError("lifecycle site lies outside the compiled lattice")
        )
        return LinearIndices(shape)[site]
    end
    throw(ArgumentError(
        "lifecycle site must resolve to a linear index or coordinate tuple"
    ))
end

function _lifecycle_point(value, ::Type{T}, ::Val{N}) where {T, N}
    value isa CellCentroid && return true, ntuple(_ -> zero(T), N)
    value isa Tuple && length(value) == N || throw(ArgumentError(
        "lifecycle plane point must be CellCentroid() or an $N-coordinate tuple"
    ))
    return false, ntuple(index -> T(_numeric_value(value[index])), N)
end

function _lifecycle_normal(value, ::Type{T}, ::Val{N}) where {T, N}
    value isa Tuple && length(value) == N || throw(ArgumentError(
        "lifecycle plane normal must be an $N-coordinate tuple"
    ))
    normal = ntuple(index -> T(_numeric_value(value[index])), N)
    norm2 = sum(abs2, normal)
    isfinite(norm2) && norm2 > zero(T) || throw(ArgumentError(
        "lifecycle plane normal must be finite and nonzero"
    ))
    inverse = inv(sqrt(norm2))
    return map(component -> component * inverse, normal)
end

function _lifecycle_rounding(value)
    value in (:exact, :conserve) && return CorePotts.ExactLifecycleRounding
    value === :floor && return CorePotts.FloorLifecycleRounding
    value === :ceil && return CorePotts.CeilLifecycleRounding
    value === :nearest && return CorePotts.NearestLifecycleRounding
    throw(ArgumentError("unsupported conservative-split rounding policy $(repr(value))"))
end

function _lifecycle_distribution_parameters(distribution)
    distribution isa Bernoulli && return UInt8(1), (
        distribution.probability, 0,
    )
    distribution isa Uniform && return UInt8(2), (
        distribution.minimum, distribution.maximum,
    )
    distribution isa Normal && return UInt8(3), (
        distribution.mean, distribution.standard_deviation,
    )
    throw(ArgumentError(
        "RedrawDaughters supports scalar Bernoulli, Uniform, or Normal in V1"
    ))
end

function _lifecycle_state_rule!(
        rules,
        evaluators,
        ir,
        record_index,
        target,
        policy,
        cursor,
        manifest,
        ::Type{T},
        state_handles,
        draw_handles,
    ) where {T <: AbstractFloat}
    record = ir.source.records[record_index]
    handle = _stage_state_handle(ir, record, target, state_handles)
    state_record = _resource_record(ir.source, record, :CellState, target)
    state_record === nothing && throw(ArgumentError(
        "lifecycle state rule does not resolve to a CellState"
    ))
    action = CorePotts.UnsupportedLifecycleState
    evaluator_a = Int32(0)
    evaluator_b = Int32(0)
    evaluator_c = Int32(0)
    evaluator_d = Int32(0)
    fraction = zero(T)
    rounding = CorePotts.ExactLifecycleRounding
    parent_distribution = UInt8(0)
    daughter_distribution = UInt8(0)
    parent_draw = UInt16(0)
    daughter_draw = UInt16(0)
    if policy isa InitializeFrom
        action = CorePotts.InitializeLifecycleState
        evaluator_a = _lifecycle_evaluator!(
            evaluators, ir, record_index, :lifecycle_state_transform,
            policy.expression, cursor, manifest, T, state_handles, draw_handles,
        )
    elseif policy isa Unsupported
        action = CorePotts.UnsupportedLifecycleState
    elseif policy isa RetireTo
        action = CorePotts.RetireToLifecycleState
        evaluator_a = _lifecycle_evaluator!(
            evaluators, ir, record_index, :lifecycle_state_transform,
            policy.expression, cursor, manifest, T, state_handles, draw_handles,
        )
    elseif policy isa Preserve
        action = CorePotts.PreserveLifecycleState
    elseif policy isa ResetTo
        action = CorePotts.ResetLifecycleState
        evaluator_a = _lifecycle_evaluator!(
            evaluators, ir, record_index, :lifecycle_state_transform,
            policy.expression, cursor, manifest, T, state_handles, draw_handles,
        )
    elseif policy isa Transform
        action = CorePotts.TransformLifecycleState
        evaluator_a = _lifecycle_evaluator!(
            evaluators, ir, record_index, :lifecycle_state_transform,
            policy.expression, cursor, manifest, T, state_handles, draw_handles,
        )
    elseif policy isa CopyToDaughters
        action = CorePotts.CopyDaughtersLifecycleState
    elseif policy isa PreserveParentResetDaughter
        action = CorePotts.PreserveParentResetDaughterLifecycleState
        evaluator_a = _lifecycle_evaluator!(
            evaluators, ir, record_index, :lifecycle_state_transform,
            policy.expression, cursor, manifest, T, state_handles, draw_handles,
        )
    elseif policy isa ResetBoth
        action = CorePotts.ResetBothLifecycleState
        evaluator_a = _lifecycle_evaluator!(
            evaluators, ir, record_index, :lifecycle_state_transform,
            policy.parent_expression, cursor, manifest, T, state_handles, draw_handles,
        )
        evaluator_b = _lifecycle_evaluator!(
            evaluators, ir, record_index, :lifecycle_state_transform,
            policy.daughter_expression, cursor, manifest, T, state_handles, draw_handles,
        )
    elseif policy isa SplitConservatively
        action = CorePotts.SplitConservativelyLifecycleState
        evaluator_a = _lifecycle_evaluator!(
            evaluators, ir, record_index, :lifecycle_state_transform,
            policy.fraction, cursor, manifest, T, state_handles, draw_handles,
        )
        rounding = _lifecycle_rounding(policy.rounding)
    elseif policy isa TransformDaughters
        action = CorePotts.TransformDaughtersLifecycleState
        evaluator_a = _lifecycle_evaluator!(
            evaluators, ir, record_index, :lifecycle_state_transform,
            policy.parent_expression, cursor, manifest, T, state_handles, draw_handles,
        )
        evaluator_b = _lifecycle_evaluator!(
            evaluators, ir, record_index, :lifecycle_state_transform,
            policy.daughter_expression, cursor, manifest, T, state_handles, draw_handles,
        )
    elseif policy isa RedrawDaughters
        action = CorePotts.RedrawDaughtersLifecycleState
        parent_distribution, parent_parameters =
            _lifecycle_distribution_parameters(policy.parent_distribution)
        daughter_distribution, daughter_parameters =
            _lifecycle_distribution_parameters(policy.daughter_distribution)
        evaluator_a = _lifecycle_evaluator!(
            evaluators, ir, record_index, :lifecycle_state_transform,
            parent_parameters[1], cursor, manifest, T, state_handles, draw_handles,
        )
        evaluator_b = _lifecycle_evaluator!(
            evaluators, ir, record_index, :lifecycle_state_transform,
            parent_parameters[2], cursor, manifest, T, state_handles, draw_handles,
        )
        evaluator_c = _lifecycle_evaluator!(
            evaluators, ir, record_index, :lifecycle_state_transform,
            daughter_parameters[1], cursor, manifest, T, state_handles, draw_handles,
        )
        evaluator_d = _lifecycle_evaluator!(
            evaluators, ir, record_index, :lifecycle_state_transform,
            daughter_parameters[2], cursor, manifest, T, state_handles, draw_handles,
        )
        parent_draw = _stable_draw_operation(
            record.identity.path, Symbol(policy.parent_draw)
        )
        daughter_draw = _stable_draw_operation(
            record.identity.path, Symbol(policy.daughter_draw)
        )
    else
        throw(ArgumentError("unsupported lifecycle state policy $(typeof(policy))"))
    end
    push!(rules, CorePotts.LifecycleStateRule(
        handle,
        _lifecycle_hash64(state_record.identity),
        action,
        evaluator_a,
        evaluator_b,
        evaluator_c,
        evaluator_d,
        fraction,
        rounding,
        parent_distribution,
        daughter_distribution,
        parent_draw,
        daughter_draw,
    ))
    return nothing
end

function _lifecycle_relationship_action(policy)
    policy isa RejectWhileLinked &&
        return CorePotts.RejectWhileLinkedLifecycleRelationship
    policy isa RemoveIncident &&
        return CorePotts.RemoveIncidentLifecycleRelationship
    policy isa PreserveCompatible &&
        return CorePotts.PreserveCompatibleLifecycleRelationship
    policy isa RemoveIncompatible &&
        return CorePotts.RemoveIncompatibleLifecycleRelationship
    policy isa RejectIncompatible &&
        return CorePotts.RejectIncompatibleLifecycleRelationship
    throw(ArgumentError(
        "unsupported lifecycle relationship policy $(typeof(policy))"
    ))
end

function _lifecycle_relationship_rule(
        ir, record, target, policy, relationship_endpoint_policies
    )
    relationship = _resource_record(
        ir.source, record, :RelationshipState, target
    )
    relationship === nothing && throw(ArgumentError(
        "lifecycle relationship policy has no qualified store"
    ))
    endpoint = _relationship_endpoint_policy(
        relationship_endpoint_policies, relationship.identity
    )
    return CorePotts.LifecycleRelationshipRule(
        endpoint.slot,
        _lifecycle_relationship_action(policy),
        endpoint.kind_a,
        endpoint.kind_b,
    )
end

function _lifecycle_effect_code(effect)
    effect isa CreateCell && return CorePotts.CreateCellLifecycleEffect
    effect isa RemoveCell && return CorePotts.RemoveCellLifecycleEffect
    effect isa Retire && return CorePotts.RetireCellLifecycleEffect
    effect isa Transition && return CorePotts.TransitionCellLifecycleEffect
    effect isa Divide && return CorePotts.DivideCellLifecycleEffect
    throw(ArgumentError("unsupported lifecycle effect $(typeof(effect))"))
end

function _lifecycle_ownership_rules(layout, required::Bool)
    required || return ()
    return Tuple(
        CorePotts.LifecycleOwnershipRule(
            entry.handle,
            begin
                lifecycle = entry.schema.lifecycle
                declared = lifecycle isa NamedTuple && haskey(lifecycle, :declared) ?
                    lifecycle.declared : nothing
                declared === :ClearOnOwnershipChange ?
                    CorePotts.ClearLifecycleOwnershipState :
                    declared === :PreserveOnOwnershipChange ?
                    CorePotts.PreserveLifecycleOwnershipState :
                    throw(ArgumentError(
                        "site-owned state has no compiled ownership-change law"
                    ))
            end,
        )
        for entry in layout.entries if entry.schema.domain === :site
    )
end

function _lower_lifecycle_plan(
        ir::AnalyzedTermIR,
        manifest::ParameterManifest,
        ::Type{T},
        state_handles,
        draw_handles,
        state_layout,
        relationship_endpoint_policies,
    ) where {T <: AbstractFloat}
    shape = _lattice_shape(ir)
    N = length(shape)
    N > 0 || throw(ArgumentError("lifecycle lowering requires a lattice"))
    cell_capacity = _cell_capacity(ir)
    cell_capacity <= typemax(Int32) || throw(ArgumentError(
        "compiled cell capacity exceeds Int32"
    ))
    evaluators = Any[]
    state_rules = Any[]
    relationship_rules = CorePotts.LifecycleRelationshipRule[]
    stencil_offsets = NTuple{N, Int16}[]
    relations = Matrix{Int8}[]
    descriptors = CorePotts.LifecycleDescriptor{N, T}[]
    facts_by_source = Dict(fact.source => fact for fact in ir.lifecycle)
    for (record_index, record) in enumerate(ir.source.records)
        record.kind === :LifecycleProcess || continue
        haskey(facts_by_source, record.identity) || continue
        arguments = first(record.normalized_payload)
        length(arguments.effects) == 1 || continue
        effect = only(arguments.effects)
        _cell_lifecycle_effect(effect) || continue
        fact = facts_by_source[record.identity]
        cursor = _LifecycleRootCursor(ir, record_index, fact.operation_abis)
        trigger = _lifecycle_evaluator!(
            evaluators,
            ir,
            record_index,
            :lifecycle_trigger,
            arguments.expression,
            cursor,
            manifest,
            T,
            state_handles,
            draw_handles;
            always_root = true,
        )
        domain = arguments.domain isa ModelDomain ?
            CorePotts.ModelLifecycleDomain : CorePotts.CellKindLifecycleDomain
        domain_kind = domain === CorePotts.CellKindLifecycleDomain ?
            _lifecycle_kind_index(ir, record, arguments.domain.kind) : Int16(0)
        cadence, cadence_value = _lifecycle_cadence(get(
            _record_options(record), :cadence, EveryMCS()
        ))
        destination_kind = effect isa CreateCell ?
            _lifecycle_kind_index(ir, record, effect.kind) :
            effect isa Transition ?
            _lifecycle_kind_index(ir, record, effect.kind) : Int16(0)
        replacement_medium = effect isa RemoveCell ?
            _lifecycle_kind_index(ir, record, effect.replacement) : Int16(0)
        placement = CorePotts.NoLifecyclePlacement
        placement_evaluator = Int32(0)
        placement_maximum = Int32(1)
        stencil_offset = Int32(length(stencil_offsets) + 1)
        stencil_count = Int32(0)
        relation_slot = Int32(0)
        if effect isa CreateCell
            if effect.placement isa SeedAt
                placement = CorePotts.SeedAtLifecyclePlacement
                site = _lifecycle_site_value(effect.placement.site, shape)
                placement_evaluator = _lifecycle_evaluator!(
                    evaluators, ir, record_index, :lifecycle_placement,
                    site, cursor, manifest, T, state_handles, draw_handles,
                )
            elseif effect.placement isa SeedStencil
                placement = CorePotts.SeedStencilLifecyclePlacement
                site = _lifecycle_site_value(effect.placement.site, shape)
                placement_evaluator = _lifecycle_evaluator!(
                    evaluators, ir, record_index, :lifecycle_placement,
                    site, cursor, manifest, T, state_handles, draw_handles,
                )
                for offset in effect.placement.offsets
                    offset isa Tuple && length(offset) == N || throw(
                        ArgumentError("SeedStencil offset dimensionality mismatch")
                    )
                    push!(stencil_offsets, ntuple(
                        index -> Int16(offset[index]), N
                    ))
                end
                stencil_count = Int32(length(effect.placement.offsets))
                placement_maximum = stencil_count
                relation_slot = _lifecycle_relation!(
                    relations, ir, record, effect.placement.relation
                )
            else
                placement = CorePotts.ExternalLifecyclePlacement
                abi = _next_lifecycle_abi(cursor, :lifecycle_placement)
                abi !== nothing && abi.role === :placement || throw(
                    ArgumentError(
                        "external lifecycle placement has no frozen placement ABI"
                    )
                )
                placement_maximum = Int32(abi.emission_maximum)
                placement_evaluator = _lifecycle_evaluator!(
                    evaluators, ir, record_index, :lifecycle_placement,
                    effect.placement, cursor, manifest, T, state_handles, draw_handles,
                )
            end
        end
        partition = CorePotts.NoLifecyclePartition
        partition_evaluator = Int32(0)
        point_from_centroid = true
        point = ntuple(_ -> zero(T), N)
        normal = ntuple(_ -> zero(T), N)
        side = CorePotts.CanonicalLifecycleSide
        geometry_draw = UInt16(0)
        side_draw = UInt16(0)
        parent_kind = Int16(0)
        daughter_kind = Int16(0)
        if effect isa Divide
            relation_slot = _lifecycle_relation!(
                relations, ir, record, effect.relation
            )
            geometry = effect.geometry
            if geometry isa RandomPlane
                partition = CorePotts.RandomPlaneLifecyclePartition
                point_from_centroid, point = _lifecycle_point(
                    geometry.point, T, Val(N)
                )
                geometry_draw = _stable_draw_operation(
                    record.identity.path, Symbol(geometry.draw)
                )
            elseif geometry isa PrincipalAxisPlane
                partition = geometry.axis === :major ?
                    CorePotts.PrincipalMajorLifecyclePartition :
                    CorePotts.PrincipalMinorLifecyclePartition
                point_from_centroid, point = _lifecycle_point(
                    geometry.point, T, Val(N)
                )
            elseif geometry isa SpecifiedNormalPlane
                partition = CorePotts.SpecifiedNormalLifecyclePartition
                point_from_centroid, point = _lifecycle_point(
                    geometry.point, T, Val(N)
                )
                normal = _lifecycle_normal(geometry.normal, T, Val(N))
            else
                partition = CorePotts.ExternalLifecyclePartition
                partition_evaluator = _lifecycle_evaluator!(
                    evaluators, ir, record_index, :lifecycle_partition,
                    geometry, cursor, manifest, T, state_handles, draw_handles,
                )
            end
            if effect.side isa StableRandomSide
                side = CorePotts.StableRandomLifecycleSide
                side_draw = _stable_draw_operation(
                    record.identity.path, Symbol(effect.side.draw_identity)
                )
            elseif !(effect.side isa CanonicalSide)
                throw(ArgumentError("unsupported lifecycle side policy"))
            end
            parent_kind = effect.parent_kind isa PreserveKind ? Int16(0) :
                _lifecycle_kind_index(ir, record, effect.parent_kind.kind)
            daughter_kind = effect.daughter_kind isa PreserveKind ? Int16(0) :
                _lifecycle_kind_index(ir, record, effect.daughter_kind.kind)
        end
        state_offset = Int32(length(state_rules) + 1)
        for item in effect.state
            item isa Pair || throw(ArgumentError(
                "lifecycle state policies must be canonical target=>policy pairs"
            ))
            _lifecycle_state_rule!(
                state_rules,
                evaluators,
                ir,
                record_index,
                first(item),
                last(item),
                cursor,
                manifest,
                T,
                state_handles,
                draw_handles,
            )
        end
        relationship_offset = Int32(length(relationship_rules) + 1)
        if hasproperty(effect, :relationships)
            for item in effect.relationships
                item isa Pair || throw(ArgumentError(
                    "lifecycle relationship policies must be canonical target=>policy pairs"
                ))
                push!(relationship_rules, _lifecycle_relationship_rule(
                    ir,
                    record,
                    first(item),
                    last(item),
                    relationship_endpoint_policies,
                ))
            end
        end
        action_identity = _lifecycle_hash64((
            _lifecycle_effect_code(effect),
            domain_kind,
            destination_kind,
            replacement_medium,
            placement,
            placement_maximum,
            stencil_count,
            relation_slot,
            partition,
            point_from_centroid,
            point,
            normal,
            side,
            parent_kind,
            daughter_kind,
            Tuple(state_rules[Int(state_offset):end]),
            Tuple(relationship_rules[Int(relationship_offset):end]),
            _lifecycle_role_workspace_maximum(fact, :lifecycle_trigger),
            _lifecycle_role_workspace_maximum(fact, :lifecycle_placement),
            _lifecycle_role_workspace_maximum(fact, :lifecycle_partition),
            _lifecycle_role_workspace_maximum(
                fact, :lifecycle_state_transform
            ),
            effect.priority,
            nameof(typeof(effect.on_inadmissible)),
        ))
        options = _record_options(record)
        push!(descriptors, CorePotts.LifecycleDescriptor{N, T}(
            Int32(record_index),
            _lifecycle_hash64(record.identity),
            action_identity,
            domain,
            domain_kind,
            trigger,
            cadence,
            cadence_value,
            _lifecycle_effect_code(effect),
            effect.priority,
            _lifecycle_disposition(effect.on_inadmissible),
            destination_kind,
            replacement_medium,
            placement,
            placement_evaluator,
            placement_maximum,
            stencil_offset,
            stencil_count,
            relation_slot,
            partition,
            partition_evaluator,
            point_from_centroid,
            point,
            normal,
            side,
            geometry_draw,
            side_draw,
            parent_kind,
            daughter_kind,
            state_offset,
            Int32(length(state_rules) - Int(state_offset) + 1),
            relationship_offset,
            Int32(length(relationship_rules) - Int(relationship_offset) + 1),
            Int32(_lifecycle_role_workspace_maximum(
                fact, :lifecycle_trigger
            )),
            Int32(_lifecycle_role_workspace_maximum(
                fact, :lifecycle_placement
            )),
            Int32(_lifecycle_role_workspace_maximum(
                fact, :lifecycle_partition
            )),
            Int32(_lifecycle_role_workspace_maximum(
                fact, :lifecycle_state_transform
            )),
            get(options, :compiler_synthesized, nothing) !== nothing,
        ))
    end
    protocol_policy = CorePotts.RejectLifecycleConflicts
    for record in ir.source.records
        record.kind === :Protocol || continue
        policy = get(
            _record_options(record),
            :lifecycle_conflicts,
            RejectLifecycleAmbiguity(),
        )
        protocol_policy = policy isa StableLifecyclePriority ?
            CorePotts.StablePriorityLifecycleConflicts :
            CorePotts.RejectLifecycleConflicts
        break
    end
    declarations = _ordered_kind_records(ir.source.records)
    forbid_extinction = falses(length(declarations))
    for (index, declaration) in enumerate(declarations)
        declaration.kind === :CellKind || continue
        get(_record_options(declaration), :extinction, nothing) isa
            ForbidExtinction && (forbid_extinction[index] = true)
    end
    maximum_requests = sum(descriptor ->
        descriptor.domain === CorePotts.ModelLifecycleDomain ? 1 : cell_capacity,
        descriptors;
        init = 0,
    )
    maximum_placement_sites = maximum(
        descriptor -> max(1, Int(descriptor.placement_maximum)),
        descriptors;
        init = 1,
    )
    maximum_policy_workspace = maximum(
        descriptor -> maximum(Int.((
            descriptor.trigger_workspace_maximum,
            descriptor.placement_workspace_maximum,
            descriptor.partition_workspace_maximum,
            descriptor.state_workspace_maximum,
        ))),
        descriptors;
        init = 0,
    )
    return CorePotts.LifecycleExecutionPlan(
        descriptors,
        CorePotts.LifecycleEvaluatorStorage(evaluators),
        CorePotts.LifecycleStateRuleStorage(state_rules),
        relationship_rules,
        _lifecycle_ownership_rules(
            state_layout,
            any(
                descriptor -> descriptor.effect in (
                    CorePotts.CreateCellLifecycleEffect,
                    CorePotts.RemoveCellLifecycleEffect,
                    CorePotts.DivideCellLifecycleEffect,
                ),
                descriptors,
            ),
        ),
        stencil_offsets,
        CorePotts.LifecycleRelationStorage(relations, Val(N)),
        protocol_policy,
        cell_capacity,
        maximum_requests,
        maximum_placement_sites,
        maximum_policy_workspace,
        forbid_extinction,
    )
end
