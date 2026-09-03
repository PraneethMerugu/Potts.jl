# Semantic ordering and capability derivation. This is not runtime scheduling;
# structural mtkcompile owns that later boundary.
function _semantic_phase_schedule(records)
    sorted = sort(
        collect(records);
        by = record -> (_phase_rank(record.phase), string(record.identity)),
    )
    scheduled = QualifiedStatement[]
    for record in sorted
        rank = _phase_rank(record.phase)
        lower = filter(
            previous -> previous.phase !== nothing &&
                        _phase_rank(previous.phase) < rank,
            scheduled,
        )
        dependency_rank = isempty(lower) ? nothing :
                          maximum(_phase_rank(previous.phase) for previous in lower)
        dependencies = dependency_rank === nothing ? () : Tuple(
            previous.identity
            for previous in lower
            if _phase_rank(previous.phase) == dependency_rank
        )
        push!(scheduled, _with_ordering_dependencies(record, dependencies))
    end
    return scheduled
end

function _validate_random_key_uniqueness!(diagnostics, records)
    seen = Dict{Tuple{Tuple, Symbol}, QualifiedStatementID}()
    for record in records
        for operation in record.random_operations
            operation.reserved && continue
            key = (record.identity.path, operation.identity)
            if haskey(seen, key)
                push!(diagnostics, PottsDiagnostic(
                    :duplicate_draw_key,
                    record.identity,
                    record.source isa SourceLocation ?
                    record.source.expression : string(record.identity),
                    record.identity.path,
                    "a namespace-local unique DrawKey",
                    "duplicates $(seen[key])",
                    (),
                    record.source,
                ))
            else
                seen[key] = record.identity
            end
        end
    end
    return nothing
end

function _completion_capabilities(records)
    sequential = all(
        admission -> admission.admitted,
        (
            only(filter(item -> item.engine === :sequential, record.engine_admission))
            for record in records
        ),
    )
    checkerboard_rejections = [
        (
            record.identity,
            admission.reason,
        )
        for record in records
        for admission in record.engine_admission
        if admission.engine === :checkerboard && !admission.admitted
    ]
    return (
        sequential = sequential,
        checkerboard = isempty(checkerboard_rejections),
        checkerboard_rejections,
        cpu = true,
    )
end

