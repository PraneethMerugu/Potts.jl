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
    evolution = get(_record_options(record), :evolution, nothing)
    evolution === nothing && return nothing
    return numerical_field_stage_descriptor(
        evolution,
        ir,
        record_index,
        manifest,
        T,
        state_handles,
        slot,
    )
end
