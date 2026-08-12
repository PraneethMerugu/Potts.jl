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
        end
    elseif hasproperty(workspace, :records) && !isempty(workspace.records)
        throw(LocalWorkValidationError(
            "fast-only combination does not admit record workspace"
        ))
    end
    return invoke(
        _validate_workspace_spec,
        Tuple{Any, Tuple, Any},
        workspace,
        invoke(
            _centrally_owned_workspace_spec,
            Tuple{Any, Any},
            lowering,
            work,
        ),
        backend,
    )
end
