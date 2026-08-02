# Field, history, and other after-MCS descriptor lowering.

function _field_stage_descriptor(
        ir::AnalyzedTermIR,
        record_index::Integer,
        manifest::ParameterManifest,
        ::Type{T},
        state_handles,
        slot::Integer,
    ) where {T <: AbstractFloat}
    record = ir.source.records[record_index]
    variable = _state_record_variable(record)
    process_index = findfirst(eachindex(ir.source.records)) do index
        candidate = ir.source.records[index]
        candidate.kind === :EquationProcess || return false
        arguments = first(candidate.normalized_payload)
        any(write -> isequal(write, variable), arguments.writes)
    end
    process_index === nothing && return nothing
    process = ir.source.records[process_index]
    solver = get(_record_options(process), :solver, nothing)
    return numerical_field_stage_descriptor(
        solver,
        ir,
        record_index,
        process_index,
        manifest,
        T,
        state_handles,
        slot,
    )
end
