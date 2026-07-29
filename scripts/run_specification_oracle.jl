using Pkg

const ROOT = normpath(joinpath(@__DIR__, ".."))
const ORACLE = joinpath(
    ROOT, "lib", "ProcessBigraphs", "test", "specification_oracle")
const FIXTURE = joinpath(ORACLE, "fixtures.toml")

isolated_command(project, script, args...) =
    `$(Base.julia_cmd()) --project=$(project) --startup-file=no $(script) $(args)`
stdlib_command(script, args...) =
    `$(Base.julia_cmd()) --startup-file=no $(script) $(args)`

mktempdir(prefix="process-bigraph-specification-oracle-") do directory
    environment = joinpath(directory, "production-environment")
    Pkg.activate(environment)
    Pkg.develop(path=joinpath(ROOT, "lib", "ProcessBigraphs"))
    Pkg.instantiate(; julia_version_strict=true)

    production = joinpath(directory, "production.toml")
    oracle = joinpath(directory, "oracle.toml")
    run(isolated_command(
        environment,
        joinpath(ORACLE, "production_driver.jl"),
        FIXTURE,
        production,
    ))

    stdlib = copy(ENV)
    stdlib["JULIA_LOAD_PATH"] = "@stdlib"
    run(setenv(stdlib_command(
        joinpath(ORACLE, "oracle_driver.jl"),
        FIXTURE,
        oracle,
    ), stdlib))
    run(setenv(stdlib_command(
        joinpath(ORACLE, "compare.jl"),
        production,
        oracle,
    ), stdlib))
    run(setenv(stdlib_command(
        joinpath(ORACLE, "runtests.jl"),
    ), stdlib))
    run(setenv(stdlib_command(
        joinpath(ORACLE, "boundary_check.jl"),
    ), stdlib))
end
