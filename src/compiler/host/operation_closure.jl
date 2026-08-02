# Dependency-derived compiler-synthesized operation closure.

function _push_operation_requirement!(requirements, operation, arity::Int)
    any(item -> first(item) === operation && last(item) == arity, requirements) ||
        push!(requirements, operation => arity)
    return requirements
end

function _node_subgraph_has_state_binding(
        nodes::Vector{NormalizedTermNode},
        root::Int32,
    )
    visited = Set{Int32}()
    function visit(index::Int32)
        index in visited && return false
        push!(visited, index)
        node = nodes[Int(index)]
        node.payload isa Union{StateBindingPayload, VariableBindingPayload} &&
            return true
        return any(visit, node.operands)
    end
    return visit(root)
end

function _record_has_relationship_create(record::QualifiedStatement)
    arguments = _record_arguments(record)
    arguments isa NamedTuple && haskey(arguments, :effects) || return false
    return any(effect -> effect isa Create, arguments.effects)
end

function _field_has_explicit_euler_stage(
        source::FrozenSourceGraph,
        field::QualifiedStatement,
    )
    variable = _state_record_variable(field)
    variable === nothing && return false
    return any(source.records) do candidate
        candidate.kind === :EquationProcess || return false
        arguments = _record_arguments(candidate)
        haskey(arguments, :writes) || return false
        any(write -> isequal(write, variable), arguments.writes) || return false
        return get(_record_options(candidate), :solver, nothing) isa ExplicitDiffusion
    end
end

function _compiler_synthesized_operation_requirements(
        source::FrozenSourceGraph,
        nodes::Vector{NormalizedTermNode},
        roots::Vector{NormalizedTermRoot},
    )
    requirements = Pair{Any, Int}[]

    for record in source.records
        if record.kind === :FieldState &&
                _field_has_explicit_euler_stage(source, record)
            _push_operation_requirement!(
                requirements, _potts_explicit_field_euler, 7
            )
        end
        if _record_has_relationship_create(record)
            _push_operation_requirement!(requirements, (&), 2)
            _push_operation_requirement!(
                requirements, _potts_relationship_endpoint_kinds, 4
            )
        end
    end

    for root in roots
        record = source.records[Int(root.record)]
        _node_subgraph_has_state_binding(nodes, root.node) || continue
        if record.phase isa AcceptedCopy
            _push_operation_requirement!(
                requirements, _potts_proposal_bound_state_value, 1
            )
        elseif record.phase isa AfterMCS
            _push_operation_requirement!(
                requirements, _potts_iteration_bound_state_value, 1
            )
        end
    end

    for node in nodes
        node.operation === :draw && !isempty(node.operands) || continue
        family_node = nodes[Int(first(node.operands))]
        family_node.payload isa LiteralPayload || continue
        family = family_node.payload.value
        if family == 1
            _push_operation_requirement!(requirements, (>=), 2)
            _push_operation_requirement!(requirements, (<=), 2)
        elseif family == 2
            _push_operation_requirement!(requirements, (<), 2)
        elseif family == 3
            _push_operation_requirement!(requirements, (>), 2)
        end
    end

    sort!(requirements; by = item -> (
        String(operation_transfer(first(item), last(item)).identity),
        last(item),
    ))
    return Tuple((first(item), last(item)) for item in requirements)
end
