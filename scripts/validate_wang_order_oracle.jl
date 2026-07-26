#!/usr/bin/env julia

function validate_wang_order_trace(path::AbstractString)
    lines = readlines(path)
    errors = String[]
    isempty(lines) && return ["trace is empty"]
    lines[1] == "mcs,python_code,field_before,field_after" ||
        push!(errors, "unexpected trace header")
    length(lines) == 12 ||
        push!(errors, "expected one header plus 11 MCS rows, found $(length(lines)) lines")

    for (row_index, line) in enumerate(Iterators.drop(lines, 1))
        columns = split(line, ',')
        length(columns) == 4 || begin
            push!(errors, "row $row_index has $(length(columns)) columns")
            continue
        end
        mcs = tryparse(Int, columns[1])
        code = tryparse(Int, columns[2])
        field_before = tryparse(Float64, columns[3])
        field_after = tryparse(Float64, columns[4])
        any(isnothing, (mcs, code, field_before, field_after)) && begin
            push!(errors, "row $row_index contains an unparsable value")
            continue
        end

        mcs == row_index - 1 ||
            push!(errors, "row $row_index has MCS $mcs, expected $(row_index - 1)")
        expected_code = mcs % 10 == 0 ? 1234 : 123
        code == expected_code ||
            push!(errors, "MCS $mcs has Python sentinel $code, expected $expected_code")
        field_after == 7.0 ||
            push!(errors, "MCS $mcs normal Python observed field $field_after, expected 7")
        if mcs > 0
            field_before == 7.0 ||
                push!(errors, "MCS $mcs pre-MCS Python observed prior field $field_before, expected 7")
        end
    end
    return errors
end

if abspath(PROGRAM_FILE) == @__FILE__
    length(ARGS) == 1 ||
        error("usage: validate_wang_order_oracle.jl TRACE.csv")
    errors = validate_wang_order_trace(only(ARGS))
    isempty(errors) || error(join(errors, '\n'))
    println("Wang CC3D 4.2.5 order trace: PASS")
end
