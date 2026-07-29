using Dates
using Pkg
using SHA
using TOML

const ROOT = normpath(joinpath(@__DIR__, ".."))
const SMOKE_SOURCE = joinpath(
    ROOT, "docs", "models", "tutorials", "install_and_verify.jl")

function platform_name()
    Sys.isapple() && return "macos"
    Sys.islinux() && return "linux"
    Sys.iswindows() && return "windows"
    return lowercase(string(Sys.KERNEL))
end

function parse_output(args)
    isempty(args) && return nothing
    length(args) == 2 && args[1] == "--output" ||
        error("usage: documentation_cpu_install_smoke.jl [--output PATH]")
    return abspath(args[2])
end

function source_digest()
    context = SHA2_256_CTX()
    for path in (
            joinpath(ROOT, "Project.toml"),
            joinpath(ROOT, "lib", "CorePotts", "Project.toml"),
            SMOKE_SOURCE)
        portable_path = replace(relpath(path, ROOT), '\\' => '/')
        update!(context, codeunits(portable_path))
        portable_source = replace(read(path, String), "\r\n" => "\n")
        update!(context, codeunits(portable_source))
    end
    return bytes2hex(digest!(context))
end

function run_smoke(args = ARGS)
    output = parse_output(args)
    started = now(UTC)
    temporary_project = mktempdir()
    Pkg.activate(temporary_project)
    Pkg.develop(path = joinpath(ROOT, "lib", "CorePotts"))
    Pkg.develop(path = ROOT)
    Pkg.instantiate(; julia_version_strict = true)

    sandbox = Module(:DocumentationCPUInstallSmoke)
    result = Base.include(sandbox, SMOKE_SOURCE)
    result.model_valid || error("documentation model validation smoke failed")
    result.backend_qualified || error("documentation CPU preflight smoke failed")

    evidence = Dict(
        "schema_version" => "1.0.0",
        "status" => "passed",
        "platform" => platform_name(),
        "kernel" => string(Sys.KERNEL),
        "architecture" => string(Sys.ARCH),
        "julia_version" => string(VERSION),
        "started_utc" => string(started),
        "completed_utc" => string(now(UTC)),
        "source_digest" => source_digest(),
        "smoke_source" => replace(relpath(SMOKE_SOURCE, ROOT), '\\' => '/'),
        "lattice" => collect(result.lattice),
    )

    if output !== nothing
        mkpath(dirname(output))
        open(output, "w") do io
            TOML.print(io, evidence; sorted = true)
        end
    end
    println("Documentation CPU install smoke passed on $(evidence["platform"])")
    return evidence
end

run_smoke()
