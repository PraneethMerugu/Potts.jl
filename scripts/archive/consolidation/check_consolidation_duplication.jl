using SHA
using TOML

const ROOT = normpath(joinpath(@__DIR__, ".."))
const REPORT_PATH = joinpath(
    ROOT, "design", "evidence", "consolidation-architecture", "duplication-v1.toml")
const MINIMUM_LINES = 16

sha256_hex(value) = bytes2hex(sha256(codeunits(value)))

function source_paths()
    paths = String[]
    for root in ("src", "ext", "lib", "test", "integration", "benchmark", "scripts")
        absolute = joinpath(ROOT, root)
        isdir(absolute) || continue
        for (directory, directories, files) in walkdir(absolute)
            filter!(name -> name ∉ (".git", "build", "results", "archive"), directories)
            for file in files
                endswith(file, ".jl") || continue
                push!(paths, relpath(joinpath(directory, file), ROOT))
            end
        end
    end
    sort!(unique!(paths))
end

function normalized_code_lines(path)
    result = Tuple{Int,String}[]
    block_comment = false
    for (line_number, raw) in enumerate(eachline(joinpath(ROOT, path)))
        line = raw
        if block_comment
            if occursin("=#", line)
                line = split(line, "=#"; limit=2)[end]
                block_comment = false
            else
                continue
            end
        end
        if occursin("#=", line)
            before, after = split(line, "#="; limit=2)
            line = before
            if occursin("=#", after)
                line *= split(after, "=#"; limit=2)[end]
            else
                block_comment = true
            end
        end
        line = replace(line, r"#.*$" => "")
        line = replace(strip(line), r"\s+" => " ")
        isempty(line) || push!(result, (line_number, line))
    end
    result
end

production(path) =
    startswith(path, "src/") ||
    occursin(r"^lib/[^/]+/(src|ext)/", path) ||
    startswith(path, "ext/")
test_source(path) =
    startswith(path, "test/") ||
    occursin(r"^lib/[^/]+/test/", path) ||
    startswith(path, "integration/")

function classification(paths)
    Set(paths) == Set((
        "scripts/check_consolidation_duplication.jl",
        "scripts/freeze_consolidation_baseline.jl",
    )) && return "deliberate_baseline_reproduction"
    any(path -> occursin("independent_custom", lowercase(path)), paths) &&
        return "deliberate_independent_adapter"
    any(path -> occursin(r"oracle|reference|specification", lowercase(path)), paths) &&
        return "deliberate_independent_oracle"
    any(path -> occursin(r"backend|device|kernel|metal|amdgpu|cuda|rocm", lowercase(path)), paths) &&
        return "backend_specific_realization"
    any(path -> occursin(r"legacy|checkpoint_v[0-9]", lowercase(path)), paths) &&
        return "compatibility_implementation"
    any(path -> occursin(r"merks|shirinifard|cnv|wang|wortel", lowercase(path)), paths) &&
        return "bounded_model_specialization"
    Set(paths) == Set(("src/PottsToolkit.jl", "src/authoring/Authoring.jl")) &&
        return "public_facade_reexport"
    any(test_source, paths) && any(production, paths) &&
        return "deliberate_test_oracle_literal"
    all(test_source, paths) && return "test_fixture_or_contract_candidate"
    all(path -> startswith(path, "scripts/"), paths) &&
        return "quality_tooling_candidate"
    all(production, paths) && return "accidental_production_duplication_candidate"
    return "conventional_or_cross_layer_boilerplate"
end

function build_report()
    paths = source_paths()
    windows = Dict{String,Vector{Tuple{String,Int,Vector{String}}}}()
    for path in paths
        lines = normalized_code_lines(path)
        length(lines) >= MINIMUM_LINES || continue
        for first in 1:(length(lines) - MINIMUM_LINES + 1)
            content = last.(lines[first:(first + MINIMUM_LINES - 1)])
            digest = sha256_hex(join(content, '\n'))
            push!(get!(windows, digest,
                Tuple{String,Int,Vector{String}}[]),
                (path, lines[first][1], content))
        end
    end

    clusters = Dict{String,Any}[]
    seen = Set{String}()
    for (digest, occurrences) in windows
        cluster_paths = sort!(unique(first.(occurrences)))
        length(cluster_paths) >= 2 || continue
        members = sort!(["$path:$line" for (path, line, _) in occurrences])
        key = join(members, '|')
        key in seen && continue
        push!(seen, key)
        kind = classification(cluster_paths)
        push!(clusters, Dict(
            "window_sha256" => digest,
            "normalized_line_count" => MINIMUM_LINES,
            "classification" => kind,
            "requires_resolution" => endswith(kind, "_candidate"),
            "paths" => cluster_paths,
            "occurrences" => members,
            "sample" => occurrences[1][3],
        ))
    end
    sort!(clusters; by = row -> (
        row["classification"], join(row["paths"], '|'), row["window_sha256"]))
    Dict(
        "schema_version" => "1.0.0",
        "evidence_id" => "semantic-preserving-consolidation-duplication-v1",
        "status" => "architecture-candidate",
        "detector" =>
            "exact 16-line windows after comment, blank-line, and whitespace normalization",
        "scanned_file_count" => length(paths),
        "exact_clone_cluster_count" => length(clusters),
        "resolution_candidate_count" =>
            count(row -> row["requires_resolution"], clusters),
        "exact_clone_clusters" => clusters,
    )
end

const CHECK_GENERATED_BASELINE =
    "--check-baseline" in ARGS || "--update" in ARGS
const current_report = build_report()

if "--update" in ARGS
    mkpath(dirname(REPORT_PATH))
    open(REPORT_PATH, "w") do io
        TOML.print(io, current_report; sorted=true)
    end
    println("wrote ", relpath(REPORT_PATH, ROOT))
end

failures = String[]
if CHECK_GENERATED_BASELINE && !isfile(REPORT_PATH)
    push!(failures, "missing duplication report; rerun with --update")
elseif CHECK_GENERATED_BASELINE
    actual = TOML.parsefile(REPORT_PATH)
    actual == current_report ||
        push!(failures, "duplication report is stale; rerun with --update")
end
candidate_count = get(current_report, "resolution_candidate_count", -1)
candidate_count == 0 ||
    push!(failures,
        "current sources contain $candidate_count unresolved duplicate candidate cluster(s)")

if isempty(failures)
    suffix = CHECK_GENERATED_BASELINE ? " The generated report is fresh." : ""
    println("All $(current_report["exact_clone_cluster_count"]) current exact clone clusters " *
            "are classified; no accidental production, test-fixture, or active-tooling " *
            "candidates remain.$suffix")
else
    foreach(message -> println(stderr, "ERROR: ", message), failures)
    error("consolidation duplication check failed with $(length(failures)) error(s)")
end
