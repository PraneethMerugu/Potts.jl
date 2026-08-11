# Caller-owned workspace validation for the generic buffered mechanism.

function _deterministic_workspace(workspace)
    hasproperty(workspace, :records) || throw(LocalWorkValidationError(
        "deterministic combination requires a named records workspace"
    ))
    workspace.records isa NamedTuple || throw(LocalWorkValidationError(
        "deterministic records workspace must be a named tuple"
    ))
    return workspace.records
end

function _validate_workspace(
        lowering::_BufferedCombinedLowering, work, workspace, backend
    )
    deterministic_names = keys(lowering.segments)
    if lowering.has_deterministic
        records = invoke(
            _deterministic_workspace, Tuple{Any}, workspace
        )
        keys(records) == deterministic_names || throw(
            LocalWorkValidationError(
                "records workspace names must exactly match deterministic ports"
            )
        )
        for name in deterministic_names
            output = getproperty(work.outputs, name)
            port = getproperty(records, name)
            expected_keys = output isa _GenericResolvedOutput ?
                (:ranks, :values, :valid) : (:values, :valid)
            port isa NamedTuple && keys(port) == expected_keys ||
                throw(LocalWorkValidationError(
                    "record port $name has the wrong named arrays"
                ))
            capacity = invoke(
                _checked_int_product,
                Tuple{Integer, Integer, Any},
                lowering.item_count,
                typeof(output).parameters[2],
                Symbol(name, :_record_capacity),
            )
            eltype(port.values) === output.value_type &&
                ndims(port.values) == 1 && length(port.values) == capacity ||
                throw(LocalWorkValidationError(
                    "record values for $name have the wrong type or capacity"
                ))
            eltype(port.valid) === Bool && ndims(port.valid) == 1 &&
                length(port.valid) == capacity || throw(
                    LocalWorkValidationError(
                        "record validity for $name has the wrong type or capacity"
                    )
                )
            invoke(
                _validate_array_backend,
                Tuple{Any, Any, Any}, port.values, backend,
                Symbol(name, :_record_values),
            )
            invoke(
                _validate_array_backend,
                Tuple{Any, Any, Any}, port.valid, backend,
                Symbol(name, :_record_valid),
            )
            Base.mightalias(port.values, port.valid) && throw(
                LocalWorkValidationError(
                    "record values and validity for $name must be disjoint"
                )
            )
            if output isa _GenericResolvedOutput
                eltype(port.ranks) === output.rank.type &&
                    ndims(port.ranks) == 1 &&
                    length(port.ranks) == capacity || throw(
                        LocalWorkValidationError(
                            "record ranks for $name have the wrong type or capacity"
                        )
                    )
                invoke(
                    _validate_array_backend,
                    Tuple{Any, Any, Any}, port.ranks, backend,
                    Symbol(name, :_record_ranks),
                )
                (Base.mightalias(port.ranks, port.values) ||
                    Base.mightalias(port.ranks, port.valid)) && throw(
                        LocalWorkValidationError(
                            "resolved record arrays for $name must be disjoint"
                        )
                    )
            end
        end
    elseif hasproperty(workspace, :records) && !isempty(workspace.records)
        throw(LocalWorkValidationError(
            "fast-only combination does not admit record workspace"
        ))
    end
    return nothing
end

function _workspace_arrays(
        lowering::_BufferedCombinedLowering, work, workspace
    )
    lowering.has_deterministic || return ()
    records = invoke(_deterministic_workspace, Tuple{Any}, workspace)
    result = Pair{Symbol, Any}[]
    for name in keys(records)
        port = getproperty(records, name)
        push!(result, Symbol(name, :_record_values) => port.values)
        push!(result, Symbol(name, :_record_valid) => port.valid)
        hasproperty(port, :ranks) && push!(
            result, Symbol(name, :_record_ranks) => port.ranks
        )
    end
    return Tuple(result)
end
