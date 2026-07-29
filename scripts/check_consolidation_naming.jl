using SHA
using TOML

const ROOT = normpath(joinpath(@__DIR__, ".."))
const POLICY_PATH = joinpath(ROOT, "spec", "consolidation-naming-v1.toml")
const POLICY = TOML.parsefile(POLICY_PATH)
const HISTORICAL_LIVING_CONSUMERS =
    Set(String.(POLICY["historical"]["living_consumers"]))
const QUALIFICATION_LIVING_CONSUMERS =
    Set(String.(POLICY["qualification"]["living_milestone_consumers"]))
const INDEX_PATH = normpath(joinpath(
    dirname(POLICY_PATH), POLICY["historical"]["index"]))
const MILESTONE = r"(?i)\bphase[\s_.-]*[0-9]+[a-z0-9_.-]*"
const GENERATED_OUTPUT_PREFIXES = (
    "benchmark/results/",
    "lib/ProcessBigraphs/docs/browser/artifacts/",
    "lib/ProcessBigraphs/docs/build/",
)

relative(path) = relpath(path, ROOT)
sha256_file(path) = open(bytes2hex ∘ sha256, path)
generated_output(path) =
    any(prefix -> startswith(relative(path), prefix), GENERATED_OUTPUT_PREFIXES)

function repository_files(root)
    files = String[]
    isdir(root) || return files
    for (directory, _, names) in walkdir(root)
        append!(files, joinpath.(directory, names))
    end
    sort!(files)
end

function historical_files()
    candidates = String[]
    for directory in (
        joinpath(ROOT, "design", "audits"),
        joinpath(ROOT, "design", "evidence"),
        joinpath(ROOT, "spec"),
        joinpath(ROOT, "scripts", "archive"),
    )
        append!(candidates, repository_files(directory))
    end
    filter!(candidates) do path
        name = lowercase(relative(path))
        startswith(name, "scripts/archive/") ||
            occursin(r"phase[-_ ]?[0-9]+", name) ||
            occursin("process-bigraph-pb0", name)
    end
    unique!(sort!(candidates))
end

function historical_index()
    artifacts = Dict{String,Any}[]
    for path in historical_files()
        rel = relative(path)
        category =
            startswith(rel, "scripts/archive/") ? "checker_source_record" :
            startswith(rel, "design/evidence/") ? "qualified_evidence" :
            startswith(rel, "design/audits/") ? "historical_audit" :
            "historical_specification"
        push!(artifacts, Dict(
            "path" => rel,
            "sha256" => sha256_file(path),
            "bytes" => filesize(path),
            "category" => category,
            "reproduction" => startswith(rel, "scripts/archive/") ?
                "checkout_baseline_commit_for_original_path" :
                "immutable_current_tree_artifact",
        ))
    end
    Dict(
        "schema_version" => "1.0.0",
        "baseline_commit" => POLICY["historical"]["baseline_commit"],
        "baseline_ci_run" => POLICY["historical"]["baseline_ci_run"],
        "artifact_count" => length(artifacts),
        "artifacts" => artifacts,
    )
end

function write_index()
    mkpath(dirname(INDEX_PATH))
    open(INDEX_PATH, "w") do io
        TOML.print(io, historical_index(); sorted=true)
    end
    println("wrote ", relative(INDEX_PATH))
end

function check_index!(failures)
    isfile(INDEX_PATH) || begin
        push!(failures, "missing historical artifact index: $(relative(INDEX_PATH))")
        return
    end
    expected = historical_index()
    actual = TOML.parsefile(INDEX_PATH)
    actual == expected ||
        push!(failures, "historical artifact index is stale; rerun with --update")
end

function check_active_paths!(failures)
    roots = (
        "src",
        "lib/ProcessBigraphs/src",
        "lib/ProcessBigraphs/test",
        "lib/ProcessBigraphs/docs",
        "lib/CorePotts/src",
        "lib/CorePotts/test",
        "lib/MakiePotts/src",
        "lib/MakiePotts/test",
        "test",
        "integration",
        "benchmark",
        ".github/workflows",
        "scripts",
    )
    for root in roots, path in repository_files(joinpath(ROOT, root))
        generated_output(path) && continue
        rel = relative(path)
        startswith(rel, "scripts/archive/") && continue
        occursin(MILESTONE, basename(path)) &&
            push!(failures, "milestone-coded active path: $rel")
    end
end

function allowed_source_occurrence(path, line)
    rel = relative(path)
    endswith(rel, "compatibility.jl") && return true
    rel in (
        "lib/CorePotts/src/CorePotts.jl",
        "src/PottsToolkit.jl",
    ) && return true
    tokens = String[row["token"] for row in POLICY["legacy_protocol_tokens"]]
    any(token -> occursin(token, line), tokens)
end

function allowed_living_occurrence(path, line)
    allowed_source_occurrence(path, line) && return true
    rel = relative(path)
    rel in HISTORICAL_LIVING_CONSUMERS && return true
    rel in QUALIFICATION_LIVING_CONSUMERS && return true
    rel in (
        "lib/CorePotts/test/test_contract_versions.jl",
        "lib/ProcessBigraphs/test/contracts/test_internal_beta_contract.jl",
        "test/test_contract_versions.jl",
        "test/test_documentation_quality_checker.jl",
        "scripts/capture_consolidation_identity_fixtures.jl",
        "scripts/freeze_consolidation_baseline.jl",
    ) && return true
    occursin(r"(?:design|spec)/\S*phase[-_0-9a-z.]*"i, line) &&
        return true
    occursin(r"(?:test|benchmark)/\S*phase[-_0-9a-z.]*"i, line) &&
        rel in (
            "scripts/capture_consolidation_identity_fixtures.jl",
            "scripts/freeze_consolidation_baseline.jl",
        ) && return true
    return false
end

function check_living_content!(failures)
    roots = (
        "src",
        "lib/ProcessBigraphs/src",
        "lib/ProcessBigraphs/test",
        "lib/ProcessBigraphs/docs",
        "lib/CorePotts/src",
        "lib/CorePotts/test",
        "lib/MakiePotts/src",
        "lib/MakiePotts/test",
        "test",
        "integration",
        "benchmark",
        ".github/workflows",
        "scripts",
    )
    for root in roots, path in repository_files(joinpath(ROOT, root))
        generated_output(path) && continue
        rel = relative(path)
        startswith(rel, "scripts/archive/") && continue
        any(extension -> endswith(path, extension),
            (".jl", ".md", ".toml", ".yml", ".yaml")) || continue
        for (number, line) in enumerate(eachline(path))
            occursin(MILESTONE, line) || continue
            allowed_living_occurrence(path, line) && continue
            push!(failures,
                "unallowlisted milestone name at $(relative(path)):$number: $(strip(line))")
        end
    end
end

function check_compatibility!(failures)
    for path in values(POLICY["compatibility"])
        path isa String || continue
        isfile(joinpath(ROOT, path)) ||
            push!(failures, "missing compatibility authority: $path")
    end
    for row in POLICY["public_names"]
        package_root =
            row["package"] == "ProcessBigraphs" ? "lib/ProcessBigraphs/src" :
            row["package"] == "CorePotts" ? "lib/CorePotts/src" : "src"
        corpus = join(read.(repository_files(joinpath(ROOT, package_root)), String), '\n')
        occursin(row["legacy"], corpus) ||
            push!(failures, "missing compatibility name $(row["package"]).$(row["legacy"])")
        occursin(row["canonical"], corpus) ||
            push!(failures, "missing canonical name $(row["package"]).$(row["canonical"])")
    end
end

if "--update" in ARGS
    write_index()
end

failures = String[]
check_active_paths!(failures)
check_living_content!(failures)
check_compatibility!(failures)
check_index!(failures)

if isempty(failures)
    println("Consolidation naming and historical archive check passed.")
else
    foreach(message -> println(stderr, "ERROR: ", message), failures)
    error("consolidation naming check failed with $(length(failures)) error(s)")
end
