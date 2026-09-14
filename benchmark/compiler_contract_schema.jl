import TOML

function _compiler_call_count(value)
    value isa Expr || return 0
    here = value.head in (:call, :invoke, :foreigncall) ? 1 : 0
    return here + sum(_compiler_call_count, value.args; init = 0)
end

function _compiler_any_syntax_class(value)
    value isa Union{Core.GotoNode, Core.GotoIfNot, Core.ReturnNode} &&
        return "non_value_control"
    value isa Core.PhiNode && return "phi"
    value isa Core.PhiCNode && return "phi_c"
    value isa Core.PiNode && return "pi"
    value isa Core.UpsilonNode && return "upsilon"
    value isa Expr && value.head in (:call, :invoke, :foreigncall) &&
        return "call_expression"
    value isa Expr && value.head in (:new, :splatnew) &&
        return "allocation_expression"
    return "other"
end

function _compiler_payload_record(name, value, semantic_origin, field_origins)
    return Dict{String, Any}(
        "name" => name,
        "type" => string(typeof(value)),
        "summary_bytes" => Base.summarysize(value),
        "isbits" => isbitstype(typeof(value)),
        "semantic_origin" => semantic_origin,
        "field_origins" => field_origins,
    )
end

function _compiler_typed_boundary_record(
        measured, names, arguments, origins, field_origins;
        role, signature,
    )
    length(names) == length(arguments) == length(origins) ==
        length(field_origins) || error(
        "compiler-boundary payload provenance does not match its arguments",
    )
    typed_results = measured.value
    info, return_type = only(typed_results)
    any_indices = info.ssavaluetypes isa Vector ?
        findall(==(Any), info.ssavaluetypes) : Int[]
    any_syntax = Dict{String, Int}()
    for index in any_indices
        syntax = _compiler_any_syntax_class(info.code[index])
        any_syntax[syntax] = get(any_syntax, syntax, 0) + 1
    end
    payload = collect(map(
        _compiler_payload_record, names, arguments, origins, field_origins,
    ))
    return Dict{String, Any}(
        "role" => role,
        "signature" => signature,
        "measurement" => "optimized_code_typed_fallback",
        "typed_statements" => length(info.code),
        "typed_calls" => sum(_compiler_call_count, info.code; init = 0),
        "any_argument_slots" => info.slottypes === nothing ? -1 :
            count(==(Any), info.slottypes),
        "any_ssa_total" => length(any_indices),
        "any_ssa_syntax" => any_syntax,
        "return_type" => string(return_type),
        "return_is_concrete" => isconcretetype(return_type),
        "typed_method_matches" => length(typed_results),
        "analysis_seconds" => measured.time,
        "analysis_allocated_bytes" => measured.bytes,
        "aggregate_payload_summary_bytes" => Base.summarysize(arguments),
        "sum_argument_summary_bytes" => sum(
            item["summary_bytes"] for item in payload
        ),
        "payload" => payload,
    )
end

function _compiler_host_boundary_record(
        function_value, names, arguments, origins, field_origins;
        role, signature,
    )
    measured = @timed Base.code_typed(
        function_value, Tuple{map(typeof, arguments)...}; optimize = true,
    )
    return _compiler_typed_boundary_record(
        measured, names, arguments, origins, field_origins; role, signature,
    )
end

function emit_resolved_aggregate_compiler_report(report; io::IO = stdout)
    TOML.print(io, report; sorted = true)
    return nothing
end
