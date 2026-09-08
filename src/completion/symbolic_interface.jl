# Completed symbolic queries project the qualified source authority directly.
# Recursing over completed children would namespace their context a second time.
function _completed_source_values(system::PottsSystem, kind::Symbol)
    return Any[
        _qualified_source_reference(reference)
            for reference in _completion_data(system).source_graph.references
            if reference.source == 0 && reference.kind === kind
    ]
end

function ModelingToolkitBase.unknowns(system::PottsSystem)
    ModelingToolkitBase.iscomplete(system) || return invoke(
        ModelingToolkitBase.unknowns, Tuple{ModelingToolkitBase.AbstractSystem}, system
    )
    return _completed_source_values(system, :variable)
end

function ModelingToolkitBase.parameters(system::PottsSystem; initial_parameters = false)
    ModelingToolkitBase.iscomplete(system) || return invoke(
        ModelingToolkitBase.parameters, Tuple{ModelingToolkitBase.AbstractSystem}, system;
        initial_parameters,
    )
    values = unique(_completed_source_values(system, :parameter))
    initial_parameters || filter!(value -> !ModelingToolkitBase.isinitial(value), values)
    return values
end

function ModelingToolkitBase.inputs(system::PottsSystem)
    ModelingToolkitBase.iscomplete(system) || return _potts_inputs(system)
    return unique(_completed_source_values(system, :input))
end

function ModelingToolkitBase.outputs(system::PottsSystem)
    ModelingToolkitBase.iscomplete(system) || return _potts_outputs(system)
    return unique(_completed_source_values(system, :output))
end

function ModelingToolkitBase.equations(system::PottsSystem)
    ModelingToolkitBase.iscomplete(system) || return invoke(
        ModelingToolkitBase.equations, Tuple{ModelingToolkitBase.AbstractSystem}, system
    )
    return _completed_source_values(system, :equation)
end

function ModelingToolkitBase.observed(system::PottsSystem)
    ModelingToolkitBase.iscomplete(system) || return invoke(
        ModelingToolkitBase.observed, Tuple{ModelingToolkitBase.AbstractSystem}, system
    )
    return _completed_source_values(system, :observation)
end

function ModelingToolkitBase.initial_conditions(system::PottsSystem)
    ModelingToolkitBase.iscomplete(system) || return invoke(
        ModelingToolkitBase.initial_conditions, Tuple{ModelingToolkitBase.AbstractSystem}, system
    )
    result = Dict{Any, Any}()
    for (key, value) in _completed_source_values(system, :initial_condition)
        # Match MTK's parent-first default precedence in source inventory order.
        get!(result, key, value)
    end
    return result
end
