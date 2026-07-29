#!/usr/bin/env julia

using TOML

const ROOT = let
    prefix = "--root="
    argument = findfirst(arg -> startswith(arg, prefix), ARGS)
    argument === nothing ?
        normpath(joinpath(@__DIR__, "..")) :
        abspath(ARGS[argument][nextind(ARGS[argument], lastindex(prefix)):end])
end

contract = TOML.parsefile(joinpath(
    ROOT, "spec/process-bigraph-phase17-documentation-quality-v1.toml"))
programs = filter(row -> haskey(row, "canonical_source"), contract["pages"])
budgets = contract["runtime_budgets_seconds"]

function execute_program(row)
    sandbox = Module(gensym(Symbol("Phase17Docs_", row["id"])))
    Base.include(sandbox, joinpath(ROOT, row["canonical_source"]))
    nothing
end

function program_budget(row)
    runtime = row["runtime"]
    runtime == "first-tutorial" &&
        return budgets["first_tutorial_warm_max"]
    runtime == "wortel-case-study" &&
        return budgets["wortel_case_study_warm_max"]
    runtime == "merks-case-study" &&
        return budgets["merks_case_study_warm_max"]
    budgets["ordinary_example_warm_max"]
end

# Precompile every concrete program path once. The qualification measurements
# below are warm by contract and deliberately retain JIT work outside timing.
for row in programs
    execute_program(row)
end
GC.gc()

measurements = Pair{String,Float64}[]
total = @elapsed for row in programs
    elapsed = @elapsed execute_program(row)
    push!(measurements, row["id"] => elapsed)
end

failures = String[]
for row in programs
    elapsed = last(only(filter(pair -> first(pair) == row["id"], measurements)))
    maximum = Float64(program_budget(row))
    elapsed <= maximum || push!(failures,
        "$(row["id"]) warm runtime $(round(elapsed; digits=3))s exceeds $(maximum)s")
end
total <= budgets["all_required_programs_warm_max"] || push!(failures,
    "all required programs warm runtime $(round(total; digits=3))s exceeds " *
    "$(budgets["all_required_programs_warm_max"])s")

if isempty(failures)
    println("ProcessBigraphs Phase 17 documentation runtime budgets passed:")
    for pair in measurements
        println("  ", rpad(first(pair), 30),
            round(last(pair); digits=3), " s")
    end
    println("  ", rpad("all-required-programs", 30),
        round(total; digits=3), " s")
else
    foreach(message -> println(stderr, "ERROR: ", message), failures)
    error("Phase 17 documentation runtime check failed with $(length(failures)) error(s)")
end
