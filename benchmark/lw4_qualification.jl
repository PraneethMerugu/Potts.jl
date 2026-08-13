using Dates
using Random
using SHA
using Serialization
using Statistics
using TOML

const ROOT = normpath(joinpath(@__DIR__, ".."))
const DRIVER = relpath(@__FILE__, ROOT)
const HISTORICAL_SAMPLES = 1_000
const NORMAL_SAMPLES = 1_000
const CONFIRMATION_SAMPLES = 2_000
const BOOTSTRAP_SAMPLES = 10_000
const THRESHOLD = 1.05
const REVIEW_ROLES = (
    "scientific-api", "julia-api", "gpu-backend",
    "numerical-determinism", "external-extension",
)
const FREEZE_COMMAND_NAMES = (
    "standalone", "corepotts", "root", "cpu-witnesses",
    "cpu-performance", "metal",
)
const RESULT_FILES = (
    "results/cpu-witnesses.jls",
    "results/cpu-performance.jls",
    "results/metal.jls",
)
const TOOL_SELF_TESTS = (
    "bootstrap reconstruction", "bundle tamper rejection",
    "outer Julia flag canonicalization",
    "fixed scientific comparison policy",
    "review rejection", "exact ledger/schema/inventory rejection",
    "forbidden profile rejection", "minimal validate/seal path",
    "post-seal review drift rejection", "tool-record tamper rejection",
    "revalidation-record tamper rejection",
)
const PROJECT_FILES = (
    "Project.toml", "Manifest.toml",
    "lib/LocalWorksets/Project.toml", "lib/LocalWorksets/Manifest.toml",
    "lib/CorePotts/Project.toml", "lib/CorePotts/Manifest.toml",
    "test/localworksets_witnesses/Project.toml",
    "test/localworksets_witnesses/Manifest.toml",
    "benchmark/backends/metal/Project.toml",
    "benchmark/backends/metal/Manifest.toml",
)
const COMMITTED_PROJECT_FILES = Set((
    "Project.toml",
    "lib/LocalWorksets/Project.toml",
    "lib/CorePotts/Project.toml",
    "test/localworksets_witnesses/Project.toml",
    "test/localworksets_witnesses/Manifest.toml",
    "benchmark/backends/metal/Project.toml",
    "benchmark/backends/metal/Manifest.toml",
))
const WORKLOAD_PATHS = (
    "test/localworksets_witnesses",
    "benchmark/backends/metal",
    "benchmark/src/lw3_localworksets_parity.jl",
    "lib/LocalWorksets/test",
    "lib/CorePotts/test",
    "test",
)

_hex(path) = bytes2hex(open(SHA.sha256, path))
_git(args...) = readchomp(Cmd(`git $args`; dir = ROOT))

function _argument(prefix)
    index = findfirst(startswith(prefix), ARGS)
    index === nothing && return nothing
    return split(ARGS[index], "="; limit = 2)[2]
end

_arguments(prefix) = [split(arg, "="; limit = 2)[2] for arg in ARGS if startswith(arg, prefix)]

function _only_mode()
    modes = String[]
    for (name, prefix) in (
        ("development", "--development"), ("check", "--check"),
        ("tool-self-test", "--tool-self-test="),
        ("tool-record", "--validate-tool-record="),
        ("revalidation-record", "--validate-revalidation-record="),
        ("freeze", "--freeze="), ("validate", "--validate="),
        ("revalidate", "--revalidate="), ("seal", "--seal="),
        ("verify-seal", "--verify-seal="), ("verify-final", "--verify-final="),
        ("collect-subsamples", "--collect-subsamples="),
        ("subsample", "--subsample="),
    )
        any(arg -> arg == prefix || startswith(arg, prefix), ARGS) && push!(modes, name)
    end
    length(modes) == 1 || error("choose exactly one workflow mode; found $(join(modes, ", "))")
    return only(modes)
end

function _stable_seed(parts...)
    digest = SHA.sha256(join(string.(parts), '\x1f'))
    seed = zero(UInt64)
    for byte in @view digest[1:8]
        seed = (seed << 8) | UInt64(byte)
    end
    return seed
end

function _command_string(command::Cmd)
    return join(Base.shell_escape.(command.exec), " ")
end

function _canonical_julia_command(command::Cmd = Base.julia_cmd())
    arguments = filter(command.exec) do argument
        !startswith(argument, "--startup-file=")
    end
    return Cmd(arguments)
end

function _recorded_command(command::Cmd, environment)
    prefix = join((string(key, "=", Base.shell_escape(value)) for
                   (key, value) in sort!(collect(environment))), " ")
    command = _command_string(command)
    return isempty(prefix) ? command : string(prefix, " ", command)
end

function _run!(name, command; log, environment = Dict{String,String}())
    mkpath(dirname(log))
    effective = isempty(environment) ? command : addenv(command, environment)
    started = now(UTC)
    start_ns = time_ns()
    process = open(log, "w") do io
        run(pipeline(ignorestatus(effective), stdout = io, stderr = io))
    end
    return (
        name,
        exit_code = process.exitcode,
        started_utc = string(started),
        finished_utc = string(now(UTC)),
        elapsed_seconds = (time_ns() - start_ns) / 1.0e9,
        log,
        command = _recorded_command(command, environment),
    )
end

function _write_commands(path, rows, root)
    open(path, "w") do io
        println(io, "name\texit_code\telapsed_seconds\tstarted_utc\tfinished_utc\tlog\tcommand")
        for row in rows
            println(io, join((
                row.name, row.exit_code, row.elapsed_seconds,
                row.started_utc, row.finished_utc,
                relpath(row.log, root), row.command,
            ), '\t'))
        end
    end
end

function _read_commands(bundle)
    lines = readlines(joinpath(bundle, "commands.tsv"))
    isempty(lines) && error("empty command ledger")
    lines[1] == "name\texit_code\telapsed_seconds\tstarted_utc\tfinished_utc\tlog\tcommand" ||
        error("unexpected command-ledger schema")
    rows = NamedTuple[]
    for line in lines[2:end]
        fields = split(line, '\t'; keepempty = true)
        length(fields) == 7 || error("malformed command row")
        push!(rows, (
            name = fields[1],
            exit_code = something(tryparse(Int, fields[2]), -1),
            elapsed_seconds = something(tryparse(Float64, fields[3]), NaN),
            started_utc = fields[4], finished_utc = fields[5],
            log = fields[6], command = fields[7],
        ))
    end
    return rows
end

function _inside_bundle(bundle, relative; kind = "artifact")
    isempty(relative) && error("empty $kind path")
    isabspath(relative) && error("absolute $kind path")
    normpath(relative) == relative || error("noncanonical $kind path: $relative")
    startswith(relative, "..") && error("escaping $kind path: $relative")
    path = joinpath(bundle, relative)
    isfile(path) || error("missing $kind: $relative")
    islink(path) && error("symlinked $kind is forbidden: $relative")
    root = realpath(bundle)
    resolved = realpath(path)
    startswith(resolved, root * Base.Filesystem.path_separator) ||
        error("escaping $kind path: $relative")
    return path
end

function _expected_artifacts()
    return Set(vcat(
        ["identity.toml", "commands.tsv", "summary.toml", "README.txt"],
        ["logs/$name.log" for name in FREEZE_COMMAND_NAMES],
        collect(RESULT_FILES),
        ["environment/$path" for path in PROJECT_FILES],
    ))
end

function _validate_artifact_inventory(bundle)
    actual = Set(relpath(path, bundle) for path in _artifact_files(bundle))
    actual == _expected_artifacts() || error(
        "unexpected Freeze artifact inventory; missing=$(collect(setdiff(_expected_artifacts(), actual))) " *
        "extra=$(collect(setdiff(actual, _expected_artifacts())))"
    )
    return nothing
end

_ishex(value, length_) = value isa AbstractString &&
    ncodeunits(value) == length_ && all(isxdigit, value)

function _validate_identity(identity, bundle)
    expected = Set((
        "schema_version", "generated_utc", "product_commit", "product_tree",
        "qualification_tool_sha256", "workload_sha256", "workload_git_objects",
        "profile", "microbenchmark_samples", "bootstrap_samples", "threshold",
        "julia", "kernelabstractions", "kernel", "architecture", "machine",
        "cpu", "threads", "project_manifest_sha256",
    ))
    Set(keys(identity)) == expected || error("unexpected identity schema")
    identity["schema_version"] == 1 || error("wrong identity schema version")
    profile = identity["profile"]
    samples = identity["microbenchmark_samples"]
    (profile == "normal" && samples == NORMAL_SAMPLES) ||
        (profile == "confirmation" && samples == CONFIRMATION_SAMPLES) ||
        error("forbidden Freeze profile/sample combination")
    identity["bootstrap_samples"] == BOOTSTRAP_SAMPLES ||
        error("wrong bootstrap sample count")
    identity["threshold"] == THRESHOLD || error("wrong noninferiority threshold")
    _ishex(identity["product_commit"], 40) || error("invalid product commit")
    _ishex(identity["product_tree"], 40) || error("invalid product tree")
    _ishex(identity["qualification_tool_sha256"], 64) || error("invalid tool identity")
    _ishex(identity["workload_sha256"], 64) || error("invalid workload identity")
    !isempty(identity["generated_utc"]) || error("missing generation time")
    identity["threads"] isa Integer && identity["threads"] > 0 ||
        error("invalid thread count")
    for key in ("julia", "kernelabstractions", "kernel", "architecture", "machine", "cpu")
        identity[key] isa AbstractString && !isempty(identity[key]) ||
            error("missing identity field: $key")
    end
    commit = identity["product_commit"]
    commit_object = string(commit, "^{commit}")
    success(Cmd(`git cat-file -e $commit_object`; dir = ROOT)) ||
        error("recorded product commit is unavailable")
    _git("show", "-s", "--format=%T", commit) == identity["product_tree"] ||
        error("product commit/tree mismatch")
    rows = identity["workload_git_objects"]
    length(rows) == length(WORKLOAD_PATHS) || error("wrong workload object count")
    for (path, row) in zip(WORKLOAD_PATHS, rows)
        startswith(row, "$path=") || error("wrong workload object order")
        recorded = last(split(row, "="; limit = 2))
        _ishex(recorded, 40) || error("invalid workload object")
        recorded == _git("rev-parse", "$commit:$path") ||
            error("workload object does not belong to recorded product: $path")
    end
    bytes2hex(SHA.sha256(join(rows, '\n'))) == identity["workload_sha256"] ||
        error("workload digest does not reconstruct")
    manifests = identity["project_manifest_sha256"]
    Set(keys(manifests)) == Set(PROJECT_FILES) || error("wrong project/manifest inventory")
    for path in PROJECT_FILES
        recorded = manifests[path]
        _ishex(recorded, 64) || error("invalid project/manifest digest: $path")
        snapshot = _inside_bundle(
            bundle, "environment/$path"; kind = "environment snapshot"
        )
        recorded == _hex(snapshot) ||
            error("project/manifest digest disagrees with environment snapshot: $path")
        if path in COMMITTED_PROJECT_FILES
            recorded == _git_blob_sha256(commit, path) ||
                error("project/manifest digest does not belong to recorded product: $path")
        end
    end
    identity["kernelabstractions"] == _manifest_version_file(
        joinpath(bundle, "environment", "Manifest.toml"), "KernelAbstractions"
    ) || error("KernelAbstractions identity disagrees with environment snapshot")
    return samples
end

function _bootstrap_upper(direct, candidate; samples = BOOTSTRAP_SAMPLES, seed)
    length(direct) == length(candidate) || error("unpaired samples")
    isempty(direct) && error("empty samples")
    rng = Xoshiro(UInt64(seed))
    indices = Vector{Int}(undef, length(direct))
    ratios = Vector{Float64}(undef, samples)
    for index in eachindex(ratios)
        rand!(rng, indices, eachindex(direct))
        ratios[index] = median(@view candidate[indices]) /
            median(@view direct[indices])
    end
    return quantile(ratios, 0.95)
end

function _validate_performance(report, witness, samples)
    report.witness == witness || error("unexpected performance witness")
    report.samples == samples || error("unexpected performance sample count")
    report.threshold == THRESHOLD || error("performance threshold changed")
    for field in (
        :sample_order_candidate_first, :direct_seconds, :candidate_seconds,
        :direct_allocated_byte_samples, :candidate_allocated_byte_samples,
        :direct_allocation_count_samples, :candidate_allocation_count_samples,
    )
        length(getproperty(report, field)) == samples ||
            error("invalid raw sample length: $field")
    end
    all(isfinite, report.direct_seconds) && all(>(0), report.direct_seconds) ||
        error("invalid direct timings")
    all(isfinite, report.candidate_seconds) &&
        all(>(0), report.candidate_seconds) || error("invalid candidate timings")
    direct_median = median(report.direct_seconds)
    candidate_median = median(report.candidate_seconds)
    report.direct_median == direct_median || error("wrong direct median")
    report.candidate_median == candidate_median || error("wrong candidate median")
    report.ratio == candidate_median / direct_median || error("wrong ratio")
    upper = _bootstrap_upper(
        report.direct_seconds, report.candidate_seconds;
        seed = UInt64(0x6c77346270657266),
    )
    report.upper95 == upper || error("wrong performance confidence bound")
    report.passed === (upper <= THRESHOLD) || error("wrong performance decision")
    report.passed || error("performance noninferiority failed")
    report.direct_submitted == report.direct_drained || error("direct tail not drained")
    report.candidate_submitted == report.candidate_drained ||
        error("candidate tail not drained")
    report.direct_waits > 0 && report.candidate_waits > 0 ||
        error("missing wait accounting")
    report.candidate_workspace_bytes >= 0 &&
        report.candidate_topology_transfer_bytes >= 0 ||
        error("invalid memory/transfer accounting")
    return (ratio = report.ratio, upper95 = upper, samples)
end

function _validate_cross_domain(reports)
    length(reports) == 5 || error("missing cross-domain witnesses")
    for report in reports
        if hasproperty(report, :comparison)
            comparison = report.comparison
            report.name == :lattice_spring ||
                error("unexpected scientific comparison report: $(report.name)")
            keys(comparison) == (:edge_state, :force, :fracture) ||
                error("invalid scientific comparison schema: $(report.name)")
            comparison.edge_state == (policy = :exact,) ||
                error("edge-state comparison must be exact: $(report.name)")
            comparison.fracture == (policy = :exact,) ||
                error("fracture comparison must be exact: $(report.name)")
            keys(comparison.force) ==
                (:policy, :rtol, :maximum_absolute_error) ||
                error("invalid force comparison schema: $(report.name)")
            report.result.edge_state == report.reference.edge_state ||
                error("scientific edge-state mismatch: $(report.name)")
            report.result.fracture == report.reference.fracture ||
                error("scientific fracture mismatch: $(report.name)")
            if report.force_mode == :deterministic
                comparison.force.policy == :exact &&
                    comparison.force.rtol == Float32(0) ||
                    error("deterministic force comparison must be exact")
                report.result.force == report.reference.force ||
                    error("scientific force mismatch: $(report.name)")
            elseif report.force_mode == :fast
                tolerance = 8eps(Float32)
                comparison.force.policy == :rtol &&
                    comparison.force.rtol == tolerance ||
                    error("fast force comparison has the wrong fixed tolerance")
                all(isapprox.(
                    report.result.force, report.reference.force; rtol = tolerance,
                )) || error("scientific force tolerance failed: $(report.name)")
            else
                error("unknown spring force mode: $(report.force_mode)")
            end
            error_ = maximum(abs.(report.result.force .- report.reference.force))
            error_ == comparison.force.maximum_absolute_error ||
                error("scientific force error does not reconstruct: $(report.name)")
        elseif hasproperty(report, :result)
            report.result == report.reference ||
                error("scientific witness mismatch: $(report.name)")
        else
            error("scientific witness has no reconstructible result: $(report.name)")
        end
        report.launches > 0 && report.waits > 0 || error("missing launch/wait facts")
        report.workspace_bytes >= 0 && report.transfer_bytes >= 0 ||
            error("invalid witness memory facts")
        report.invalid_rejected || error("invalid witness input was accepted")
    end
    return nothing
end

function _validate_results(bundle, samples)
    cpu_witnesses = deserialize(joinpath(bundle, "results", "cpu-witnesses.jls"))
    _validate_cross_domain(cpu_witnesses)
    cpu = deserialize(joinpath(bundle, "results", "cpu-performance.jls"))
    cpu_summary = (
        d2q9 = _validate_performance(cpu.d2q9, :d2q9_direct, samples),
        zbuffer = _validate_performance(cpu.zbuffer, :zbuffer_buffered, samples),
    )
    metal = deserialize(joinpath(bundle, "results", "metal.jls"))
    occursin("Apple M1 Pro", metal.environment.metal) ||
        error("real qualified Metal device is not identified")
    occursin("KernelAbstractions: 0.9.42", metal.environment.metal) ||
        error("KernelAbstractions identity is absent")
    _validate_cross_domain(Tuple(values(metal.cross_domain)))
    metal_summary = (
        d2q9 = _validate_performance(
            metal.d2q9_performance, :d2q9_direct, samples
        ),
        zbuffer = _validate_performance(
            metal.zbuffer_performance, :zbuffer_buffered, samples
        ),
    )
    facts = metal.localworksets
    facts.backend == :metal && facts.event_scope == :backend_implicit_order_tail ||
        error("wrong Metal/ordering evidence")
    metal.localworksets_failure.poisoned === true || error("failure did not poison")
    metal.shared_failure.good_poisoned === true &&
        metal.shared_failure.bad_poisoned === true || error("shared failure scope is wrong")
    checkerboard = metal.checkerboard
    checkerboard.submitted_mcs == checkerboard.committed_mcs == 12 &&
        checkerboard.synchronizations == 1 || error("checkerboard queue contract failed")
    metal.checkerboard_failure.expected_failure_commit == 0 &&
        metal.checkerboard_failure.provider_poisoned === true ||
        error("checkerboard failure contract failed")
    parity = metal.lw3_parity
    parity.measured_batches == 50 && parity.bootstrap_samples == 10_000 ||
        error("CorePotts parity workload changed")
    parity.paired_bootstrap_upper_95 == _bootstrap_upper(
        parity.direct_seconds, parity.candidate_seconds;
        seed = parity.bootstrap_seed,
    ) || error("CorePotts parity bound does not reconstruct")
    parity.paired_bootstrap_upper_95 <= parity.threshold == THRESHOLD ||
        error("CorePotts parity failed")
    parity.localworksets_submitted == parity.localworksets_drained == 600 &&
        parity.localworksets_waits == 60 || error("CorePotts tail accounting failed")
    parity.localworksets_algorithmic_workspace_bytes == 32 &&
        parity.localworksets_topology_transfer_bytes == 0 &&
        parity.localworksets_poisoned === false || error("CorePotts memory/lifetime facts failed")
    return (
        cpu = cpu_summary,
        metal = metal_summary,
        corepotts = (
            ratio = parity.median_ratio,
            upper95 = parity.paired_bootstrap_upper_95,
            samples = parity.measured_batches,
        ),
        checkerboard = (
            submitted = checkerboard.submitted_mcs,
            committed = checkerboard.committed_mcs,
            synchronizations = checkerboard.synchronizations,
        ),
    )
end

function _validate_result_environment(bundle, identity)
    metal = deserialize(joinpath(bundle, "results", "metal.jls"))
    environment = metal.environment
    string(environment.julia) == identity["julia"] ||
        error("raw Julia identity disagrees with Freeze identity")
    string(environment.kernel) == identity["kernel"] ||
        error("raw kernel identity disagrees with Freeze identity")
    string(environment.architecture) == identity["architecture"] ||
        error("raw architecture identity disagrees with Freeze identity")
    string(environment.machine) == identity["machine"] ||
        error("raw machine identity disagrees with Freeze identity")
    occursin(
        "KernelAbstractions: $(identity["kernelabstractions"])",
        environment.metal,
    ) || error("raw KernelAbstractions identity disagrees with Freeze identity")
    occursin("Apple M1 Pro", environment.metal) ||
        error("raw qualified Metal device identity is absent")
    return nothing
end

function _tree_identity(path)
    return _git("rev-parse", "HEAD:$path")
end

function _git_blob(commit, path)
    specification = string(commit, ":", path)
    return read(Cmd(`git show $specification`; dir = ROOT))
end

_git_blob_sha256(commit, path) = bytes2hex(SHA.sha256(_git_blob(commit, path)))

function _manifest_version_file(path, name)
    manifest = TOML.parsefile(path)
    entries = manifest["deps"][name]
    entry = entries isa AbstractVector ? only(entries) : entries
    return entry["version"]
end

function _copy_environment_files(bundle)
    for path in PROJECT_FILES
        destination = joinpath(bundle, "environment", path)
        mkpath(dirname(destination))
        cp(joinpath(ROOT, path), destination; force = false)
    end
    return nothing
end

function _identity(profile, samples)
    product_commit = _git("rev-parse", "HEAD")
    workload_rows = [string(path, "=", _tree_identity(path)) for path in WORKLOAD_PATHS]
    workload_digest = bytes2hex(SHA.sha256(join(workload_rows, '\n')))
    return Dict(
        "schema_version" => 1,
        "generated_utc" => string(now(UTC)),
        "product_commit" => product_commit,
        "product_tree" => _git("rev-parse", "HEAD^{tree}"),
        "qualification_tool_sha256" => _hex(joinpath(ROOT, DRIVER)),
        "workload_sha256" => workload_digest,
        "workload_git_objects" => workload_rows,
        "profile" => profile,
        "microbenchmark_samples" => samples,
        "bootstrap_samples" => BOOTSTRAP_SAMPLES,
        "threshold" => THRESHOLD,
        "julia" => string(VERSION),
        "kernelabstractions" => _manifest_version_file(
            joinpath(ROOT, "Manifest.toml"), "KernelAbstractions"
        ),
        "kernel" => string(Sys.KERNEL),
        "architecture" => string(Sys.ARCH),
        "machine" => Sys.MACHINE,
        "cpu" => Sys.CPU_NAME,
        "threads" => Threads.nthreads(),
        "project_manifest_sha256" => Dict(
            path => _hex(joinpath(ROOT, path)) for path in PROJECT_FILES
        ),
    )
end

function _require_clean_candidate()
    isempty(_git("status", "--porcelain", "--untracked-files=all")) ||
        error("Freeze requires a clean committed product candidate")
end

function _require_unchanged_candidate(bundle)
    success(Cmd(`git diff --quiet`; dir = ROOT)) ||
        error("tracked product files changed during Freeze")
    success(Cmd(`git diff --cached --quiet`; dir = ROOT)) ||
        error("the Git index changed during Freeze")
    untracked = readlines(Cmd(
        `git ls-files --others --exclude-standard`; dir = ROOT
    ))
    bundle_relative = relpath(bundle, ROOT)
    outside = filter(untracked) do path
        path != bundle_relative && !startswith(path, bundle_relative * "/")
    end
    isempty(outside) || error("untracked files appeared during Freeze: $outside")
    return nothing
end

function _freeze_commands(bundle, samples)
    julia = _canonical_julia_command()
    result(name) = joinpath(bundle, "results", "$name.jls")
    perf_env = Dict("LW4_PERF_SAMPLES" => string(samples))
    return (
        ("standalone", `$julia --startup-file=no --project=lib/LocalWorksets -e 'using Pkg; Pkg.test()'`, Dict{String,String}()),
        ("corepotts", `$julia --startup-file=no --project=lib/CorePotts -e 'using Pkg; Pkg.test()'`, Dict{String,String}()),
        ("root", `$julia --startup-file=no --project=. -e 'using Pkg; Pkg.test()'`, Dict{String,String}()),
        ("cpu-witnesses", `$julia --startup-file=no --project=test/localworksets_witnesses test/localworksets_witnesses/runtests.jl`, Dict("LW4_MACHINE_RESULTS" => result("cpu-witnesses"))),
        ("cpu-performance", `$julia --startup-file=no --project=test/localworksets_witnesses test/localworksets_witnesses/performance.jl`, merge(perf_env, Dict("LW4_MACHINE_RESULTS" => result("cpu-performance")))),
        ("metal", `$julia --startup-file=no --project=benchmark/backends/metal benchmark/backends/metal/runtests.jl`, merge(perf_env, Dict("LW4_MACHINE_RESULTS" => result("metal")))),
    )
end

function _check()
    julia = _canonical_julia_command()
    commands = (
        ("standalone", `$julia --startup-file=no --project=lib/LocalWorksets -e 'using Pkg; Pkg.test()'`),
        ("corepotts", `$julia --startup-file=no --project=lib/CorePotts -e 'using Pkg; Pkg.test()'`),
        ("cpu-witnesses", `$julia --startup-file=no --project=test/localworksets_witnesses test/localworksets_witnesses/runtests.jl`),
        ("metal-witnesses", `$julia --startup-file=no --project=benchmark/backends/metal benchmark/backends/metal/lw4_check.jl`),
    )
    for (name, command) in commands
        println("[LW-4 Check] $name")
        success(command) || error("Check failed: $name")
    end
    println("LW-4 Check passed")
end

function _development()
    Base.isinteractive() || error(
        "Development is an interactive workflow; add -i to the documented command"
    )
    try
        @eval using Revise
    catch
        error("Install Revise.jl in your developer environment, then rerun")
    end
    println("LW-4 Development session ready with Revise.")
    println("Use Pkg.test for the affected package or run --check in a fresh process before handoff.")
end

function _artifact_files(bundle)
    files = String[]
    for (directory, directories, names) in walkdir(bundle)
        filter!(name -> name != "review", directories)
        for name in names
            name in ("bundle-digest.txt", "SEALED") && continue
            push!(files, joinpath(directory, name))
        end
    end
    sort!(files)
    return files
end

function _bundle_digest(bundle)
    rows = [string(_hex(path), "  ", relpath(path, bundle)) for path in
            _artifact_files(bundle)]
    return bytes2hex(SHA.sha256(join(rows, '\n')))
end

function _verify_bundle_digest(bundle)
    expected = strip(read(joinpath(bundle, "bundle-digest.txt"), String))
    actual = _bundle_digest(bundle)
    expected == actual || error("freeze artifact digest mismatch")
    return actual
end

function _summary_data(summary, rows)
    section(value) = Dict(string(key) => item for (key, item) in pairs(value))
    return Dict(
        "schema_version" => 1,
        "all_commands_passed" => all(row -> row.exit_code == 0, rows),
        "command_seconds" => Dict(row.name => row.elapsed_seconds for row in rows),
        "cpu_d2q9" => section(summary.cpu.d2q9),
        "cpu_zbuffer" => section(summary.cpu.zbuffer),
        "metal_d2q9" => section(summary.metal.d2q9),
        "metal_zbuffer" => section(summary.metal.zbuffer),
        "corepotts" => section(summary.corepotts),
        "checkerboard" => section(summary.checkerboard),
    )
end

function _write_summary(path, summary, rows)
    open(path, "w") do io
        TOML.print(io, _summary_data(summary, rows))
    end
end

function _freeze(bundle; confirmation = false)
    _require_clean_candidate()
    ispath(bundle) && error("freeze output already exists: $bundle")
    samples = confirmation ? CONFIRMATION_SAMPLES : NORMAL_SAMPLES
    profile = confirmation ? "confirmation" : "normal"
    mkpath(joinpath(bundle, "logs")); mkpath(joinpath(bundle, "results"))
    _copy_environment_files(bundle)
    identity = _identity(profile, samples)
    open(joinpath(bundle, "identity.toml"), "w") do io
        TOML.print(io, identity)
    end
    rows = NamedTuple[]
    for (name, command, environment) in _freeze_commands(bundle, samples)
        row = _run!(name, command;
            log = joinpath(bundle, "logs", "$name.log"), environment)
        push!(rows, row)
        _write_commands(joinpath(bundle, "commands.tsv"), rows, bundle)
        row.exit_code == 0 || error("Freeze failed: $name")
    end
    _git("rev-parse", "HEAD") == identity["product_commit"] ||
        error("product commit changed during Freeze")
    _require_unchanged_candidate(bundle)
    summary = _validate_results(bundle, samples)
    _write_summary(joinpath(bundle, "summary.toml"), summary, rows)
    open(joinpath(bundle, "README.txt"), "w") do io
        println(io, "LW-4 conventional Julia Freeze artifact")
        println(io, "Product: ", identity["product_commit"])
        println(io, "Profile: ", profile, " (", samples, " paired microbenchmark samples)")
        println(io, "Review records bind to bundle-digest.txt; Git owns their integrity.")
    end
    open(joinpath(bundle, "bundle-digest.txt"), "w") do io
        println(io, _bundle_digest(bundle))
    end
    println("LW-4 Freeze passed: $bundle")
    return bundle
end

function _validate_command_ledger(bundle, identity, rows)
    length(rows) == length(FREEZE_COMMAND_NAMES) ||
        error("Freeze must contain exactly six product commands")
    expected = _freeze_commands(bundle, identity["microbenchmark_samples"])
    for (row, (name, command, environment)) in zip(rows, expected)
        row.name == name || error("wrong or duplicate Freeze command: $(row.name)")
        row.command == _recorded_command(command, environment) ||
            error("altered Freeze command/environment: $name")
        row.log == "logs/$name.log" || error("wrong Freeze log path: $name")
        log = _inside_bundle(bundle, row.log; kind = "Freeze log")
        filesize(log) > 0 || error("empty Freeze log: $name")
        row.exit_code == 0 || error("nonzero Freeze command: $name")
        isfinite(row.elapsed_seconds) && row.elapsed_seconds >= 0 ||
            error("invalid command duration: $name")
        !isempty(row.started_utc) && !isempty(row.finished_utc) ||
            error("missing command timestamps: $name")
    end
    return nothing
end

function _validate(bundle;
        results_validator = _validate_results,
        environment_validator = _validate_result_environment,
    )
    digest = _verify_bundle_digest(bundle)
    _validate_artifact_inventory(bundle)
    identity = TOML.parsefile(joinpath(bundle, "identity.toml"))
    samples = _validate_identity(identity, bundle)
    rows = _read_commands(bundle)
    _validate_command_ledger(bundle, identity, rows)
    summary = results_validator(bundle, samples)
    environment_validator(bundle, identity)
    recorded = TOML.parsefile(joinpath(bundle, "summary.toml"))
    recorded == _summary_data(summary, rows) ||
        error("summary.toml does not reconstruct from raw results")
    return (digest, identity)
end

function _validate_review(review, decisions, digest, identity)
    Set(keys(decisions)) == Set((
        "schema_version", "product_commit", "evidence_digest", "chair", "roles"
    )) || error("unexpected review-decision schema")
    decisions["schema_version"] == 1 || error("wrong review schema")
    decisions["product_commit"] == identity["product_commit"] ||
        error("review is bound to another product")
    decisions["evidence_digest"] == digest || error("review is bound to other evidence")
    roles = decisions["roles"]
    Set(keys(roles)) == Set(REVIEW_ROLES) || error("missing specialty decisions")
    for role in REVIEW_ROLES
        isfile(joinpath(review, "$role.md")) || error("missing reviewer memo: $role")
        decision = roles[role]
        decision["disposition"] == "pass" && decision["p0"] == 0 &&
            decision["p1"] == 0 || error("blocking specialty decision: $role")
    end
    isfile(joinpath(review, "chair.md")) || error("missing chair memo")
    chair = decisions["chair"]
    chair["disposition"] == "freeze" && chair["p0"] == 0 && chair["p1"] == 0 ||
        error("chair did not freeze")
    return nothing
end

function _review_digest(review)
    files = sort!(filter(isfile, readdir(review; join = true)))
    isempty(files) && error("empty review record")
    rows = [string(_hex(path), "  ", basename(path)) for path in files]
    return bytes2hex(SHA.sha256(join(rows, '\n')))
end

function _seal(bundle;
        results_validator = _validate_results,
        environment_validator = _validate_result_environment,
    )
    digest, identity = _validate(bundle; results_validator, environment_validator)
    review = joinpath(bundle, "review")
    decisions = TOML.parsefile(joinpath(review, "decisions.toml"))
    _validate_review(review, decisions, digest, identity)
    isfile(joinpath(bundle, "SEALED")) && error("bundle is already sealed")
    open(joinpath(bundle, "SEALED"), "w") do io
        TOML.print(io, Dict(
            "sealed_utc" => string(now(UTC)),
            "product_commit" => identity["product_commit"],
            "evidence_digest" => digest,
            "review_digest" => _review_digest(review),
            "review_model" => "independent_memos_plus_single_chair_red_team",
        ))
    end
    println("LW-4 Freeze sealed: $bundle")
end


function _verify_seal(bundle;
        results_validator = _validate_results,
        environment_validator = _validate_result_environment,
    )
    digest, identity = _validate(bundle; results_validator, environment_validator)
    review = joinpath(bundle, "review")
    decisions = TOML.parsefile(joinpath(review, "decisions.toml"))
    _validate_review(review, decisions, digest, identity)
    seal = TOML.parsefile(joinpath(bundle, "SEALED"))
    Set(keys(seal)) == Set((
        "sealed_utc", "product_commit", "evidence_digest", "review_digest",
        "review_model",
    )) || error("unexpected seal schema")
    seal["product_commit"] == identity["product_commit"] ||
        error("seal product binding changed")
    seal["evidence_digest"] == digest || error("seal evidence binding changed")
    seal["review_digest"] == _review_digest(review) ||
        error("review records changed after sealing")
    seal["review_model"] == "independent_memos_plus_single_chair_red_team" ||
        error("wrong review model")
    !isempty(seal["sealed_utc"]) || error("missing seal time")
    println("LW-4 seal verified: $bundle")
    return (digest, identity, seal)
end

function _verify_final(bundle)
    _verify_seal(bundle)
    relative = relpath(bundle, ROOT)
    startswith(relative, "..") && error("final Freeze artifact must be inside the repository")
    isempty(readlines(Cmd(`git status --porcelain -- $relative`; dir = ROOT))) ||
        error("final evidence/review/seal state is not committed cleanly")
    for (directory, _, names) in walkdir(bundle)
        for name in names
            path = relpath(joinpath(directory, name), ROOT)
            success(Cmd(`git ls-files --error-unmatch $path`; dir = ROOT)) ||
                error("uncommitted final artifact file: $path")
        end
    end
    println("LW-4 final Git record verified: $bundle")
end

function _write_validation_record(path, bundle, disposition, detail, digest = "")
    data = Dict(
        "schema_version" => 1,
        "validated_utc" => string(now(UTC)),
        "artifact" => abspath(bundle),
        "artifact_digest" => digest,
        "validator_sha256" => _hex(joinpath(ROOT, DRIVER)),
        "julia" => string(VERSION),
        "disposition" => disposition,
        "detail" => detail,
    )
    mkpath(dirname(path))
    open(path, "w") do io
        TOML.print(io, data)
    end
end

_valid_timestamp(value) = value isa AbstractString &&
    !isempty(value) && tryparse(DateTime, value) !== nothing

function _validate_revalidation_record(path)
    data = TOML.parsefile(path)
    Set(keys(data)) == Set((
        "schema_version", "validated_utc", "artifact", "artifact_digest",
        "validator_sha256", "julia", "disposition", "detail",
    )) || error("unexpected revalidation-record schema")
    data["schema_version"] == 1 || error("wrong revalidation-record schema")
    _valid_timestamp(data["validated_utc"]) || error("invalid revalidation time")
    isdir(data["artifact"]) || error("revalidated artifact is unavailable")
    _ishex(data["artifact_digest"], 64) || error("invalid revalidated artifact digest")
    data["artifact_digest"] == _verify_bundle_digest(data["artifact"]) ||
        error("revalidation record is bound to different raw evidence")
    data["validator_sha256"] == _hex(joinpath(ROOT, DRIVER)) ||
        error("revalidation record is stale")
    data["julia"] == string(VERSION) || error("wrong revalidation Julia identity")
    data["disposition"] == "pass" || error("raw evidence did not revalidate")
    data["detail"] == "raw evidence reconstructed" ||
        error("unexpected revalidation disposition detail")
    println("LW-4 evidence-revalidation record verified: $path")
end

function _revalidate(bundle, record)
    digest = ""
    try
        digest, _ = _validate(bundle)
        _write_validation_record(record, bundle, "pass", "raw evidence reconstructed", digest)
        _validate_revalidation_record(record)
        println("LW-4 evidence revalidated: $record")
    catch exception
        _write_validation_record(record, bundle, "fail", sprint(showerror, exception), digest)
        rethrow()
    end
end

function _source_digest(bundle, cpu_path, metal_path)
    identity_files = filter(isfile, (
        joinpath(bundle, "identity.toml"),
        joinpath(bundle, "candidate-verification.toml"),
        joinpath(bundle, "environment.toml"),
    ))
    rows = [string(_hex(path), "  ", relpath(path, bundle)) for path in
            vcat([cpu_path, metal_path], collect(identity_files))]
    return bytes2hex(SHA.sha256(join(sort!(rows), '\n')))
end

function _collect_subsamples(output, bundles)
    length(bundles) == 5 || error("sample analysis requires exactly five source bundles")
    sources = NamedTuple[]
    for bundle in bundles
        cpu_path = joinpath(bundle, "results", "cpu-performance.jls")
        metal_path = joinpath(bundle, "results", "metal.jls")
        isfile(cpu_path) && isfile(metal_path) || error("missing source performance result: $bundle")
        cpu = deserialize(cpu_path)
        metal = deserialize(metal_path)
        reports = (
            cpu_d2q9 = cpu.d2q9,
            cpu_zbuffer = cpu.zbuffer,
            metal_d2q9 = metal.d2q9_performance,
            metal_zbuffer = metal.zbuffer_performance,
        )
        all(report -> length(report.direct_seconds) == HISTORICAL_SAMPLES &&
            length(report.candidate_seconds) == HISTORICAL_SAMPLES, values(reports)) ||
            error("source bundle is not a 1,000-pair baseline: $bundle")
        push!(sources, (
            source_name = basename(bundle),
            source_digest = _source_digest(bundle, cpu_path, metal_path),
            cpu_result_sha256 = _hex(cpu_path),
            metal_result_sha256 = _hex(metal_path),
            reports,
        ))
    end
    length(unique(source.source_digest for source in sources)) == 5 ||
        error("sample-analysis sources must be distinct")
    mkpath(dirname(output))
    serialize(output, (
        schema_version = 1,
        generated_utc = string(now(UTC)),
        sources = Tuple(sources),
    ))
    println("LW-4 subsampling inputs collected: $output sha256=$(_hex(output))")
end

function _subsample(input, output)
    collection = deserialize(input)
    collection.schema_version == 1 || error("wrong subsampling-input schema")
    length(collection.sources) == 5 || error("wrong subsampling source count")
    counts = (50, 100, 200, 500, 1_000)
    repeats = 100
    # This is an offline sample-size sensitivity study, not the final Freeze
    # decision (which retains 10,000 resamples). The work is deterministic and
    # embarrassingly parallel, so `julia -t auto` is appropriate here.
    bootstrap_samples = 2_000
    labels = (:cpu_d2q9, :cpu_zbuffer, :metal_d2q9, :metal_zbuffer)
    table = Dict{String,Any}()
    for count_ in counts
        count_data = Dict{String,Any}()
        for label in labels
            jobs = length(collection.sources) * repeats
            uppers = Vector{Float64}(undef, jobs)
            Threads.@threads for job in 1:jobs
                source_index = (job - 1) ÷ repeats + 1
                repetition = (job - 1) % repeats + 1
                source = collection.sources[source_index]
                report = getproperty(source.reports, label)
                rng = Xoshiro(_stable_seed(
                    "subset", source.source_digest, label, count_, repetition,
                ))
                indices = randperm(rng, length(report.direct_seconds))[1:count_]
                uppers[job] = _bootstrap_upper(
                    report.direct_seconds[indices], report.candidate_seconds[indices];
                    samples = bootstrap_samples,
                    seed = _stable_seed(
                        "bootstrap", source.source_digest, label, count_, repetition,
                    ),
                )
            end
            count_data[string(label)] = Dict(
                "decisions" => length(uppers),
                "failures" => count(>(THRESHOLD), uppers),
                "p95_upper" => quantile(uppers, 0.95),
                "worst_upper" => maximum(uppers),
            )
        end
        table[string(count_)] = count_data
    end
    source_rows = [Dict(
        "name" => source.source_name,
        "source_digest" => source.source_digest,
        "cpu_result_sha256" => source.cpu_result_sha256,
        "metal_result_sha256" => source.metal_result_sha256,
    ) for source in collection.sources]
    data = Dict(
        "schema_version" => 1,
        "input" => relpath(input, ROOT),
        "input_sha256" => _hex(input),
        "threshold" => THRESHOLD,
        "subset_method" => "SHA-256-seeded without-replacement permutations",
        "bootstrap_method" => "paired SHA-256-seeded resampling; median ratio upper 95th percentile",
        "subsets_per_source" => repeats,
        "bootstrap_samples_per_subset" => bootstrap_samples,
        "sources" => source_rows,
        "counts" => table,
    )
    mkpath(dirname(output))
    open(output, "w") do io
        TOML.print(io, data)
    end
    println("LW-4 subsampling analysis written: $output")
end

function _rejected(f)
    return try
        f()
        false
    catch
        true
    end
end

function _synthetic_identity(samples = NORMAL_SAMPLES)
    profile = samples == NORMAL_SAMPLES ? "normal" : "confirmation"
    return _identity(profile, samples)
end

function _synthetic_summary()
    perf = (ratio = 1.0, upper95 = 1.0, samples = NORMAL_SAMPLES)
    return (
        cpu = (d2q9 = perf, zbuffer = perf),
        metal = (d2q9 = perf, zbuffer = perf),
        corepotts = (ratio = 1.0, upper95 = 1.0, samples = 50),
        checkerboard = (submitted = 12, committed = 12, synchronizations = 1),
    )
end

function _synthetic_bundle(directory)
    mkpath(joinpath(directory, "logs")); mkpath(joinpath(directory, "results"))
    _copy_environment_files(directory)
    identity = _synthetic_identity()
    open(joinpath(directory, "identity.toml"), "w") do io
        TOML.print(io, identity)
    end
    rows = NamedTuple[]
    for (name, command, environment) in _freeze_commands(directory, NORMAL_SAMPLES)
        log = joinpath(directory, "logs", "$name.log")
        write(log, "synthetic tool test\n")
        push!(rows, (
            name, exit_code = 0, elapsed_seconds = 0.01,
            started_utc = string(now(UTC)), finished_utc = string(now(UTC)),
            log, command = _recorded_command(command, environment),
        ))
    end
    for path in RESULT_FILES
        serialize(joinpath(directory, path), :synthetic)
    end
    _write_commands(joinpath(directory, "commands.tsv"), rows, directory)
    _write_summary(joinpath(directory, "summary.toml"), _synthetic_summary(), rows)
    write(joinpath(directory, "README.txt"), "synthetic tool validation artifact\n")
    write(joinpath(directory, "bundle-digest.txt"), _bundle_digest(directory) * "\n")
    return rows
end

function _restore_digest(directory)
    write(joinpath(directory, "bundle-digest.txt"), _bundle_digest(directory) * "\n")
end

function _tool_self_test(record)
    @assert _bootstrap_upper(fill(1.0, 20), fill(1.01, 20);
        samples = 100, seed = 1) ≈ 1.01
    base = Cmd(["julia", "-g1"])
    inherited = Cmd([
        "julia", "--startup-file=yes", "--startup-file=no", "-g1",
    ])
    _canonical_julia_command(base).exec ==
        _canonical_julia_command(inherited).exec ||
        error("Julia child command depends on inherited startup-file flags")
    _canonical_julia_command(Cmd(["julia", "--check-bounds=yes"])).exec !=
        _canonical_julia_command(base).exec ||
        error("material Julia flags were canonicalized away")
    common_report = (
        result = Int32(1), reference = Int32(1), launches = 1, waits = 1,
        workspace_bytes = 0, transfer_bytes = 0, invalid_rejected = true,
    )
    spring_result = (
        edge_state = UInt32[1], force = Float32[2], fracture = UInt32[0],
    )
    spring_report = merge(common_report, (
        name = :lattice_spring,
        force_mode = :deterministic,
        result = spring_result,
        reference = spring_result,
        comparison = (
            edge_state = (policy = :exact,),
            force = (
                policy = :exact,
                rtol = Float32(0),
                maximum_absolute_error = Float32(0),
            ),
            fracture = (policy = :exact,),
        ),
    ))
    reports = (
        merge(common_report, (name = :one,)),
        spring_report,
        merge(common_report, (name = :three,)),
        merge(common_report, (name = :four,)),
        merge(common_report, (name = :five,)),
    )
    _validate_cross_domain(reports)
    altered_force = merge(spring_result, (force = Float32[102],))
    permissive = merge(spring_report, (
        result = altered_force,
        comparison = merge(spring_report.comparison, (
            force = (
                policy = :rtol,
                rtol = Float32(1e6),
                maximum_absolute_error = Float32(100),
            ),
        )),
    ))
    altered_reports = ntuple(
        index -> index == 2 ? permissive : reports[index], length(reports)
    )
    @assert _rejected(() -> _validate_cross_domain(altered_reports))
    mktempdir() do directory
        mkpath(joinpath(directory, "logs"))
        write(joinpath(directory, "identity.toml"), "x = 1\n")
        write(joinpath(directory, "logs", "one.log"), "ok\n")
        write(joinpath(directory, "bundle-digest.txt"), _bundle_digest(directory) * "\n")
        @assert _verify_bundle_digest(directory) ==
            strip(read(joinpath(directory, "bundle-digest.txt"), String))
        write(joinpath(directory, "logs", "one.log"), "changed\n")
        @assert _rejected(() -> _verify_bundle_digest(directory))
    end
    mktempdir() do directory
        for role in REVIEW_ROLES
            write(joinpath(directory, "$role.md"), "independent memo\n")
        end
        write(joinpath(directory, "chair.md"), "chair red team\n")
        identity = Dict("product_commit" => "product")
        roles = Dict(role => Dict(
            "disposition" => "pass", "p0" => 0, "p1" => 0
        ) for role in REVIEW_ROLES)
        decisions = Dict(
            "schema_version" => 1,
            "product_commit" => "product",
            "evidence_digest" => "evidence",
            "roles" => roles,
            "chair" => Dict("disposition" => "freeze", "p0" => 0, "p1" => 0),
        )
        _validate_review(directory, decisions, "evidence", identity)
        roles["gpu-backend"]["p1"] = 1
        @assert _rejected(() -> _validate_review(directory, decisions, "evidence", identity))
        roles["gpu-backend"]["p1"] = 0
        decisions["evidence_digest"] = "forged"
        @assert _rejected(() -> _validate_review(directory, decisions, "evidence", identity))
    end
    mktempdir() do directory
        rows = _synthetic_bundle(directory)
        validator = (_, _) -> _synthetic_summary()
        environment_validator = (_, _) -> nothing
        _validate(directory; results_validator = validator, environment_validator)

        identity_path = joinpath(directory, "identity.toml")
        truthful_identity = TOML.parsefile(identity_path)
        identity = deepcopy(truthful_identity)
        identity["workload_git_objects"][1] = string(WORKLOAD_PATHS[1], "=", repeat("a", 40))
        identity["workload_sha256"] = bytes2hex(SHA.sha256(join(
            identity["workload_git_objects"], '\n'
        )))
        open(identity_path, "w") do io; TOML.print(io, identity); end
        _restore_digest(directory)
        @assert _rejected(() -> _validate(
            directory; results_validator = validator, environment_validator
        ))
        identity = deepcopy(truthful_identity)
        identity["project_manifest_sha256"][PROJECT_FILES[1]] = repeat("c", 64)
        open(identity_path, "w") do io; TOML.print(io, identity); end
        _restore_digest(directory)
        @assert _rejected(() -> _validate(
            directory; results_validator = validator, environment_validator
        ))
        open(identity_path, "w") do io; TOML.print(io, truthful_identity); end
        _restore_digest(directory)

        metal_path = joinpath(directory, "results", "metal.jls")
        environment = (
            julia = truthful_identity["julia"],
            kernel = truthful_identity["kernel"],
            architecture = truthful_identity["architecture"],
            machine = truthful_identity["machine"],
            metal = "KernelAbstractions: $(truthful_identity["kernelabstractions"])\nApple M1 Pro",
        )
        serialize(metal_path, (; environment))
        _validate_result_environment(directory, truthful_identity)
        serialize(metal_path, (; environment = merge(environment, (julia = "bogus",))))
        @assert _rejected(() -> _validate_result_environment(directory, truthful_identity))
        serialize(metal_path, :synthetic)
        _restore_digest(directory)

        ledger = joinpath(directory, "commands.tsv")
        original_ledger = read(ledger, String)
        rows[2] = merge(rows[2], (name = rows[1].name,))
        _write_commands(ledger, rows, directory); _restore_digest(directory)
        @assert _rejected(() -> _validate(
            directory; results_validator = validator, environment_validator
        ))
        write(ledger, original_ledger)

        altered = replace(original_ledger, "Pkg.test()" => "Pkg.status()"; count = 1)
        write(ledger, altered); _restore_digest(directory)
        @assert _rejected(() -> _validate(
            directory; results_validator = validator, environment_validator
        ))
        write(ledger, replace(original_ledger, "logs/standalone.log" => "../escape.log"))
        _restore_digest(directory)
        @assert _rejected(() -> _validate(
            directory; results_validator = validator, environment_validator
        ))
        write(ledger, original_ledger)

        write(joinpath(directory, "summary.toml"), "schema_version = 1\nall_commands_passed = false\n")
        _restore_digest(directory)
        @assert _rejected(() -> _validate(
            directory; results_validator = validator, environment_validator
        ))
        _write_summary(joinpath(directory, "summary.toml"), _synthetic_summary(), _read_commands(directory))

        write(joinpath(directory, "unexpected.txt"), "no\n"); _restore_digest(directory)
        @assert _rejected(() -> _validate(
            directory; results_validator = validator, environment_validator
        ))
        rm(joinpath(directory, "unexpected.txt"))

        identity = TOML.parsefile(identity_path)
        identity["profile"] = "normal"; identity["microbenchmark_samples"] = 200
        open(identity_path, "w") do io; TOML.print(io, identity); end
        _restore_digest(directory)
        @assert _rejected(() -> _validate(
            directory; results_validator = validator, environment_validator
        ))
        identity = _synthetic_identity()
        open(identity_path, "w") do io; TOML.print(io, identity); end
        _restore_digest(directory)

        review = joinpath(directory, "review"); mkpath(review)
        for role in REVIEW_ROLES
            write(joinpath(review, "$role.md"), "independent memo\n")
        end
        write(joinpath(review, "chair.md"), "chair red team\n")
        roles = Dict(role => Dict("disposition" => "pass", "p0" => 0, "p1" => 0)
                     for role in REVIEW_ROLES)
        decisions = Dict(
            "schema_version" => 1, "product_commit" => identity["product_commit"],
            "evidence_digest" => strip(read(joinpath(directory, "bundle-digest.txt"), String)),
            "roles" => roles,
            "chair" => Dict("disposition" => "freeze", "p0" => 0, "p1" => 0),
        )
        open(joinpath(review, "decisions.toml"), "w") do io; TOML.print(io, decisions); end
        _seal(directory; results_validator = validator, environment_validator)
        _verify_seal(directory; results_validator = validator, environment_validator)
        roles["gpu-backend"]["p1"] = 1
        open(joinpath(review, "decisions.toml"), "w") do io; TOML.print(io, decisions); end
        @assert _rejected(() -> _verify_seal(
            directory; results_validator = validator, environment_validator
        ))
    end
    mktempdir() do directory
        tool_record = joinpath(directory, "tool.toml")
        tool_data = Dict(
            "schema_version" => 1, "validated_utc" => string(now(UTC)),
            "qualification_tool_sha256" => _hex(joinpath(ROOT, DRIVER)),
            "julia" => string(VERSION), "disposition" => "pass",
            "tests" => collect(TOOL_SELF_TESTS),
        )
        open(tool_record, "w") do io; TOML.print(io, tool_data); end
        _validate_tool_record(tool_record)
        for (key, value) in (
            "validated_utc" => "", "julia" => "bogus", "tests" => String[],
        )
            altered = deepcopy(tool_data); altered[key] = value
            open(tool_record, "w") do io; TOML.print(io, altered); end
            @assert _rejected(() -> _validate_tool_record(tool_record))
        end

        artifact = joinpath(directory, "artifact"); mkpath(artifact)
        write(joinpath(artifact, "bundle-digest.txt"), _bundle_digest(artifact) * "\n")
        revalidation_record = joinpath(directory, "revalidation.toml")
        revalidation_data = Dict(
            "schema_version" => 1, "validated_utc" => string(now(UTC)),
            "artifact" => artifact,
            "artifact_digest" => strip(read(joinpath(artifact, "bundle-digest.txt"), String)),
            "validator_sha256" => _hex(joinpath(ROOT, DRIVER)),
            "julia" => string(VERSION), "disposition" => "pass",
            "detail" => "raw evidence reconstructed",
        )
        open(revalidation_record, "w") do io; TOML.print(io, revalidation_data); end
        _validate_revalidation_record(revalidation_record)
        for (key, value) in (
            "validated_utc" => "", "artifact_digest" => "bad",
            "julia" => "bogus", "detail" => "informal judgment",
        )
            altered = deepcopy(revalidation_data); altered[key] = value
            open(revalidation_record, "w") do io; TOML.print(io, altered); end
            @assert _rejected(() -> _validate_revalidation_record(revalidation_record))
        end
    end
    data = Dict(
        "schema_version" => 1,
        "validated_utc" => string(now(UTC)),
        "qualification_tool_sha256" => _hex(joinpath(ROOT, DRIVER)),
        "julia" => string(VERSION),
        "disposition" => "pass",
        "tests" => collect(TOOL_SELF_TESTS),
    )
    mkpath(dirname(record))
    open(record, "w") do io; TOML.print(io, data); end
    println("LW-4 qualification-tool self-test passed; record=$record")
end

function _validate_tool_record(path)
    data = TOML.parsefile(path)
    Set(keys(data)) == Set((
        "schema_version", "validated_utc", "qualification_tool_sha256",
        "julia", "disposition", "tests",
    )) || error("unexpected tool-validation schema")
    data["schema_version"] == 1 && data["disposition"] == "pass" ||
        error("qualification tool did not pass")
    _valid_timestamp(data["validated_utc"]) || error("invalid tool-validation time")
    data["qualification_tool_sha256"] == _hex(joinpath(ROOT, DRIVER)) ||
        error("tool-validation record is stale")
    data["julia"] == string(VERSION) || error("wrong tool-validation Julia identity")
    data["tests"] == collect(TOOL_SELF_TESTS) ||
        error("tool-validation coverage is incomplete")
    println("LW-4 qualification-tool record verified: $path")
end

function _usage()
    error("""
    Choose one workflow:
      julia --project=. -i benchmark/lw4_qualification.jl --development
      julia --project=. benchmark/lw4_qualification.jl --check
      julia --project=. benchmark/lw4_qualification.jl --freeze=PATH [--confirmation]
      julia --project=. benchmark/lw4_qualification.jl --validate=PATH
      julia --project=. benchmark/lw4_qualification.jl --revalidate=PATH --record=FILE
      julia --project=. benchmark/lw4_qualification.jl --seal=PATH
      julia --project=. benchmark/lw4_qualification.jl --verify-seal=PATH
      julia --project=. benchmark/lw4_qualification.jl --verify-final=PATH
    Tool-only: --tool-self-test=RECORD and --validate-tool-record=RECORD.
    Raw-evidence records: --validate-revalidation-record=RECORD.
    Offline analysis:
      --collect-subsamples=INPUT.jls --source-bundle=PATH (exactly five times)
      --subsample=INPUT.jls --output=RESULT.toml
    """)
end

if abspath(PROGRAM_FILE) == (@__FILE__)
    mode = _only_mode()
    if mode == "development"
        _development()
    elseif mode == "check"
        _check()
    elseif mode == "tool-self-test"
        _tool_self_test(abspath(ROOT, _argument("--tool-self-test=")))
    elseif mode == "tool-record"
        _validate_tool_record(abspath(ROOT, _argument("--validate-tool-record=")))
    elseif mode == "revalidation-record"
        _validate_revalidation_record(abspath(
            ROOT, _argument("--validate-revalidation-record=")
        ))
    elseif mode == "freeze"
        path = _argument("--freeze=")
        _freeze(abspath(ROOT, path); confirmation = "--confirmation" in ARGS)
    elseif mode == "validate"
        path = _argument("--validate=")
        println(_validate(abspath(ROOT, path)))
    elseif mode == "revalidate"
        path = _argument("--revalidate=")
        record = _argument("--record=")
        record === nothing && error("--revalidate requires --record=FILE")
        _revalidate(abspath(ROOT, path), abspath(ROOT, record))
    elseif mode == "seal"
        path = _argument("--seal=")
        _seal(abspath(ROOT, path))
    elseif mode == "verify-seal"
        _verify_seal(abspath(ROOT, _argument("--verify-seal=")))
    elseif mode == "verify-final"
        _verify_final(abspath(ROOT, _argument("--verify-final=")))
    elseif mode == "collect-subsamples"
        sources = abspath.(ROOT, _arguments("--source-bundle="))
        _collect_subsamples(
            abspath(ROOT, _argument("--collect-subsamples=")), sources,
        )
    elseif mode == "subsample"
        output = _argument("--output=")
        output === nothing && error("--subsample requires --output=FILE")
        _subsample(
            abspath(ROOT, _argument("--subsample=")), abspath(ROOT, output),
        )
    else
        _usage()
    end
end
