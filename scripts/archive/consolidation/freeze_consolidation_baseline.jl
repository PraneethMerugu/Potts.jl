#!/usr/bin/env julia

using SHA
using TOML

const ROOT = normpath(joinpath(@__DIR__, ".."))
const BASELINE_COMMIT = "d2f4d40e78fb68ee20da483d9784b55d25bf6147"
const OUTPUT_ROOT = joinpath(
    ROOT, "design", "evidence", "consolidation-baseline")
const WRITE = "--write" in ARGS

git(arguments...) =
    readchomp(Cmd(Cmd(["git", string.(arguments)...]); dir=ROOT))
git_bytes(arguments...) =
    read(Cmd(Cmd(["git", string.(arguments)...]); dir=ROOT))
const BASELINE_BYTE_CACHE = Dict{String, Vector{UInt8}}()
const BASELINE_TEXT_CACHE = Dict{String, String}()
baseline_bytes(path) = get!(BASELINE_BYTE_CACHE, path) do
    git_bytes("show", "$(BASELINE_COMMIT):$(path)")
end
baseline_text(path) = get!(BASELINE_TEXT_CACHE, path) do
    String(baseline_bytes(path))
end
sha256_hex(bytes) = bytes2hex(sha256(bytes))
normalize_path(path) = replace(normpath(path), '\\' => '/')

function tracked_paths()
    filter(!isempty, split(
        git("ls-tree", "-r", "--name-only", BASELINE_COMMIT), '\n'))
end

const TRACKED = tracked_paths()
const TRACKED_SET = Set(TRACKED)

function toml_bytes(value)
    io = IOBuffer()
    TOML.print(io, value; sorted=true)
    write(io, '\n')
    take!(io)
end

function emit(relative_path, value)
    path = joinpath(OUTPUT_ROOT, relative_path)
    expected = toml_bytes(value)
    if WRITE
        mkpath(dirname(path))
        open(path, "w") do io
            write(io, expected)
        end
        println("wrote ", relpath(path, ROOT))
        return
    end
    isfile(path) ||
        error("missing generated baseline artifact: $(relpath(path, ROOT))")
    read(path) == expected ||
        error("stale generated baseline artifact: $(relpath(path, ROOT))")
    println("verified ", relpath(path, ROOT))
end

function package_for(path)
    startswith(path, "lib/ProcessBigraphs/") && return "ProcessBigraphs"
    startswith(path, "lib/CorePotts/") && return "CorePotts"
    startswith(path, "lib/MakiePotts/") && return "MakiePotts"
    (startswith(path, "src/") || startswith(path, "ext/") ||
     startswith(path, "test/")) && return "PottsToolkit"
    startswith(path, "integration/") && return "integration"
    startswith(path, "benchmark/") && return "benchmark"
    "repository"
end

function source_paths()
    filter(TRACKED) do path
        endswith(path, ".jl") || return false
        startswith(path, "src/") ||
            startswith(path, "ext/") ||
            occursin(r"^lib/[^/]+/(src|ext)/", path)
    end
end

function environment_paths()
    filter(path -> basename(path) in ("Project.toml", "Manifest.toml"), TRACKED)
end

function project_record(path)
    parsed = TOML.parse(baseline_text(path))
    Dict(
        "path" => path,
        "sha256" => sha256_hex(baseline_bytes(path)),
        "name" => get(parsed, "name", ""),
        "uuid" => get(parsed, "uuid", ""),
        "version" => get(parsed, "version", ""),
        "direct_dependencies" =>
            sort!(collect(keys(get(parsed, "deps", Dict{String, Any}())))),
        "weak_dependencies" =>
            sort!(collect(keys(get(parsed, "weakdeps", Dict{String, Any}())))),
        "extensions" =>
            sort!(collect(keys(get(parsed, "extensions", Dict{String, Any}())))),
    )
end

function include_edges()
    edges = Dict{String, Any}[]
    unmatched = Dict{String, Any}[]
    for path in source_paths()
        text = baseline_text(path)
        matched_spans = UnitRange{Int}[]
        for match in eachmatch(r"include\(\s*\"([^\"]+)\"\s*\)", text)
            target = normalize_path(joinpath(dirname(path), match.captures[1]))
            push!(matched_spans, match.offset:(match.offset + ncodeunits(match.match) - 1))
            push!(edges, Dict(
                "package" => package_for(path),
                "source" => path,
                "target" => target,
                "target_tracked" => target in TRACKED_SET,
            ))
        end
        if occursin("include(", text)
            literal_count = length(matched_spans)
            total_count = length(collect(eachmatch(r"\binclude\(", text)))
            total_count == literal_count || push!(unmatched, Dict(
                "path" => path,
                "include_count" => total_count,
                "literal_include_count" => literal_count,
            ))
        end
    end
    sort!(edges; by=edge -> (edge["package"], edge["source"], edge["target"]))
    sort!(unmatched; by=row -> row["path"])
    edges, unmatched
end

function dependency_edges()
    edges = Dict{String, Any}[]
    for path in filter(path -> basename(path) == "Project.toml", environment_paths())
        parsed = TOML.parse(baseline_text(path))
        source = get(parsed, "name", path)
        for (kind, key) in (
            ("direct", "deps"),
            ("weak", "weakdeps"),
        )
            for target in sort!(collect(keys(
                    get(parsed, key, Dict{String, Any}()))))
                push!(edges, Dict(
                    "source" => source,
                    "target" => target,
                    "kind" => kind,
                    "project" => path,
                ))
            end
        end
        for (extension, trigger) in sort!(collect(
                get(parsed, "extensions", Dict{String, Any}())))
            triggers = trigger isa Vector ? string.(trigger) : [string(trigger)]
            for target in triggers
                push!(edges, Dict(
                    "source" => source,
                    "target" => target,
                    "kind" => "extension_trigger",
                    "extension" => extension,
                    "project" => path,
                ))
            end
        end
    end
    sort!(edges; by=edge -> (
        edge["project"], edge["kind"], edge["source"], edge["target"]))
end

function build_identity()
    includes, unmatched = include_edges()
    source = [
        Dict(
            "path" => path,
            "package" => package_for(path),
            "sha256" => sha256_hex(baseline_bytes(path)),
            "bytes" => length(baseline_bytes(path)),
        )
        for path in source_paths()
    ]
    sort!(source; by=row -> row["path"])
    projects = project_record.(
        filter(path -> basename(path) == "Project.toml", environment_paths()))
    manifests = [
        Dict(
            "path" => path,
            "sha256" => sha256_hex(baseline_bytes(path)),
            "bytes" => length(baseline_bytes(path)),
        )
        for path in filter(
            path -> basename(path) == "Manifest.toml", environment_paths())
    ]
    sort!(projects; by=row -> row["path"])
    sort!(manifests; by=row -> row["path"])
    Dict(
        "schema_version" => "1.0.0",
        "evidence_id" => "semantic-preserving-consolidation-baseline-identity-v1",
        "status" => "frozen",
        "qualified_commit" => BASELINE_COMMIT,
        "qualified_tree" => git("show", "-s", "--format=%T", BASELINE_COMMIT),
        "qualified_parent" => git("show", "-s", "--format=%P", BASELINE_COMMIT),
        "merge_base_origin_main" =>
            git("merge-base", BASELINE_COMMIT, "origin/main"),
        "tracked_file_count" => length(TRACKED),
        "source_file_count" => length(source),
        "environment_input_count" => length(environment_paths()),
        "runtime_scoped_worktree_matches_commit" => true,
        "runtime_scope" => [
            ".github", "Project.toml", "Manifest.toml", "benchmark", "docs",
            "examples", "ext", "integration", "lib", "paper", "scripts", "src",
            "test",
        ],
        "qualified_ci" => Dict(
            "run_id" => 30399756947,
            "head_commit" => BASELINE_COMMIT,
            "conclusion" => "success",
            "required_job_count" => 16,
        ),
        "qualified_environment" => Dict(
            "julia_version" => "1.12.6",
            "source" =>
                "design/evidence/process-bigraph-phase16i-evidence-v1.toml",
        ),
        "projects" => projects,
        "manifests" => manifests,
        "dependency_edges" => dependency_edges(),
        "include_edges" => includes,
        "unparsed_include_sites" => unmatched,
        "source_files" => source,
    )
end

function walk_expressions!(visitor, value)
    visitor(value)
    value isa Expr || return
    for argument in value.args
        walk_expressions!(visitor, argument)
    end
end

function parsed_source(path)
    Meta.parseall(baseline_text(path); filename=path)
end

function exported_names(entrypoint)
    result = Set{String}()
    walk_expressions!(parsed_source(entrypoint)) do value
        value isa Expr && value.head === :export || return
        for argument in value.args
            argument isa Symbol && push!(result, string(argument))
        end
    end
    sort!(collect(result))
end

function signature_name(signature)
    signature isa Symbol && return string(signature)
    signature isa QuoteNode && return signature_name(signature.value)
    signature isa Expr || return ""
    signature.head === :where && return signature_name(signature.args[1])
    signature.head === :(::) && return signature_name(signature.args[1])
    signature.head === :call || return ""
    callee = signature.args[1]
    callee isa Symbol && return string(callee)
    callee isa Expr && callee.head === :. &&
        return string(callee.args[end] isa QuoteNode ?
            callee.args[end].value : callee.args[end])
    ""
end

normalize_signature(value) =
    replace(strip(sprint(show, value)), r"\s+" => " ")

function declared_type_name(declaration)
    declaration isa Symbol && return string(declaration)
    declaration isa Expr || return ""
    declaration.head === :(<:) &&
        return declared_type_name(declaration.args[1])
    declaration.head === :curly &&
        return declared_type_name(declaration.args[1])
    ""
end

function declared_interfaces(package, files)
    signatures = Dict{String, Set{String}}()
    types = Dict{String, Set{String}}()
    for path in files
        walk_expressions!(parsed_source(path)) do value
            value isa Expr || return
            if value.head === :function
                signature = value.args[1]
                name = signature_name(signature)
                isempty(name) || push!(
                    get!(signatures, name, Set{String}()),
                    "$(normalize_signature(signature)) @ $(path)",
                )
            elseif value.head === :(=)
                signature = value.args[1]
                name = signature_name(signature)
                isempty(name) || push!(
                    get!(signatures, name, Set{String}()),
                    "$(normalize_signature(signature)) @ $(path)",
                )
            elseif value.head === :struct
                declaration = value.args[2]
                name = declared_type_name(declaration)
                isempty(name) || push!(
                    get!(types, name, Set{String}()),
                    "$(normalize_signature(declaration)) @ $(path)",
                )
            end
        end
    end
    signatures, types
end

const PACKAGE_ENTRYPOINTS = Dict(
    "ProcessBigraphs" => "lib/ProcessBigraphs/src/ProcessBigraphs.jl",
    "CorePotts" => "lib/CorePotts/src/CorePotts.jl",
    "PottsToolkit" => "src/PottsToolkit.jl",
    "MakiePotts" => "lib/MakiePotts/src/MakiePotts.jl",
)

function package_source_files(package)
    filter(path -> package_for(path) == package, source_paths())
end

function existing_classifications()
    inventory = TOML.parse(baseline_text(
        "design/audits/phase-13-api-inventory.toml"))
    result = Dict{Tuple{String, String}, String}()
    for package in ("CorePotts", "PottsToolkit")
        module_record = inventory["modules"][package]
        for entry in module_record["exports"]
            result[(package, entry["name"])] = entry["classification"]
        end
    end
    result
end

function process_bigraph_qualified_only()
    api = TOML.parse(baseline_text("spec/process-bigraph-phase16-api-v1.toml"))
    Set(string.(api["planned_public_unexported"]))
end

function consumer_paths()
    filter(TRACKED) do path
        (endswith(path, ".jl") || endswith(path, ".md")) || return false
        startswith(path, "src/") ||
            startswith(path, "test/") ||
            startswith(path, "lib/") ||
            startswith(path, "integration/") ||
            startswith(path, "examples/") ||
            startswith(path, "docs/")
    end
end

function qualified_consumers(package, exports)
    result = Dict{String, Set{String}}()
    expression = Regex("\\b$(package)\\.([A-Za-z_][A-Za-z0-9_!]*|@[A-Za-z_][A-Za-z0-9_]*)")
    for path in consumer_paths()
        for match in eachmatch(expression, baseline_text(path))
            name = match.captures[1]
            name in exports && continue
            push!(get!(result, name, Set{String}()), path)
        end
    end
    result
end

function consumer_scope(package, path)
    package_for(path) == package && return "own_package"
    startswith(path, "docs/") && return "documentation"
    startswith(path, "examples/") && return "example"
    startswith(path, "integration/") && return "integration"
    package_for(path) in (
        "ProcessBigraphs", "CorePotts", "PottsToolkit", "MakiePotts") &&
        return "sibling_package"
    "external_repository"
end

function error_and_diagnostic_inventory(files)
    errors = Set{String}()
    codes = Dict{String, Set{String}}()
    for path in files
        text = baseline_text(path)
        expression = parsed_source(path)
        walk_expressions!(expression) do value
            value isa Expr && value.head === :struct || return
            declaration = value.args[2]
            name = declared_type_name(declaration)
            endswith(name, "Error") && push!(errors, name)
        end
        for match in eachmatch(
                r"(?:_fail|[A-Za-z_][A-Za-z0-9_]*(?:Error|Diagnostic))\s*\(\s*:(\w+)"s,
                text)
            push!(get!(codes, match.captures[1], Set{String}()), path)
        end
    end
    (
        sort!(collect(errors)),
        [
            Dict("code" => code, "sources" => sort!(collect(paths)))
            for (code, paths) in sort!(collect(codes); by=first)
        ],
    )
end

function build_api()
    classifications = existing_classifications()
    pb_qualified = process_bigraph_qualified_only()
    packages = Dict{String, Any}[]
    for package in sort!(collect(keys(PACKAGE_ENTRYPOINTS)))
        entrypoint = PACKAGE_ENTRYPOINTS[package]
        exports = exported_names(entrypoint)
        files = package_source_files(package)
        signatures, types = declared_interfaces(package, files)
        qualified = qualified_consumers(package, Set(exports))
        errors, codes = error_and_diagnostic_inventory(files)
        export_records = Dict{String, Any}[]
        for name in exports
            kind = haskey(types, name) ? "type" :
                haskey(signatures, name) ? "function_or_constructor" :
                "constant_or_macro"
            interface = sort!(collect(union(
                get(signatures, name, Set{String}()),
                get(types, name, Set{String}()),
            )))
            classification = get(
                classifications,
                (package, name),
                package == "ProcessBigraphs" ? "internal_beta_export" :
                package == "MakiePotts" ? "public_export" : "unclassified",
            )
            push!(export_records, Dict(
                "name" => name,
                "kind" => kind,
                "classification" => classification,
                "interface_signatures" => interface,
                "interface_sha256" =>
                    sha256_hex(join(interface, "\n")),
            ))
        end
        qualified_records = Dict{String, Any}[]
        public_qualified_only = String[]
        for (name, paths) in sort!(collect(qualified); by=first)
            declared = haskey(signatures, name) || haskey(types, name)
            explicitly_qualified =
                package == "ProcessBigraphs" && name in pb_qualified
            scopes = sort!(unique(consumer_scope.(Ref(package), collect(paths))))
            externally_observable = any(!=("own_package"), scopes)
            (explicitly_qualified || (declared && externally_observable)) &&
                push!(public_qualified_only, name)
            push!(qualified_records, Dict(
                "name" => name,
                "declared_in_package" => declared,
                "explicitly_qualified" => explicitly_qualified,
                "externally_observable" => externally_observable,
                "consumer_scopes" => scopes,
                "consumers" => sort!(collect(paths)),
                "interface_signatures" => sort!(collect(union(
                    get(signatures, name, Set{String}()),
                    get(types, name, Set{String}()),
                ))),
            ))
        end
        push!(packages, Dict(
            "name" => package,
            "entrypoint" => entrypoint,
            "entrypoint_sha256" => sha256_hex(baseline_bytes(entrypoint)),
            "source_file_count" => length(files),
            "export_count" => length(exports),
            "qualified_only_reference_count" => length(qualified_records),
            "public_qualified_only_count" => length(public_qualified_only),
            "public_qualified_only_names" => public_qualified_only,
            "milestone_coded_exports" => filter(
                name -> occursin(r"(?:Phase|phase|P)[0-9]+", name),
                exports),
            "exports" => export_records,
            "qualified_only_references" => qualified_records,
            "error_types" => errors,
            "diagnostic_codes" => codes,
        ))
    end
    Dict(
        "schema_version" => "1.0.0",
        "evidence_id" => "semantic-preserving-consolidation-baseline-api-v1",
        "status" => "frozen",
        "qualified_commit" => BASELINE_COMMIT,
        "signature_representation" =>
            "normalized unexpanded Julia declaration plus defining source path",
        "default_representation" =>
            "keyword and positional defaults are retained in declaration signatures",
        "classification_authorities" => [
            "design/audits/phase-13-api-inventory.toml",
            "spec/process-bigraph-phase16-api-v1.toml",
            "exported MakiePotts surface at the qualified commit",
        ],
        "packages" => packages,
    )
end

function direct_includes(path)
    result = String[]
    text = baseline_text(path)
    for match in eachmatch(r"include\(\s*\"([^\"]+)\"\s*\)", text)
        target = normalize_path(joinpath(dirname(path), match.captures[1]))
        target in TRACKED_SET && push!(result, target)
    end
    for match in eachmatch(
            r"include\(\s*joinpath\(\s*@__DIR__((?:\s*,\s*\"[^\"]+\")+)\s*\)\s*\)",
            text)
        segments = [
            part.captures[1]
            for part in eachmatch(r"\"([^\"]+)\"", match.captures[1])
        ]
        target = normalize_path(joinpath(dirname(path), segments...))
        target in TRACKED_SET && push!(result, target)
    end
    unique(result)
end

function reachable_from(roots)
    visited = Set{String}()
    function visit(path)
        path in visited && return
        push!(visited, path)
        for target in direct_includes(path)
            visit(target)
        end
    end
    visit.(roots)
    visited
end

const TEST_ROOTS = [
    "test/runtests.jl",
    "lib/ProcessBigraphs/test/runtests.jl",
    "lib/ProcessBigraphs/test/specification_oracle/runtests.jl",
    "lib/ProcessBigraphs/test/specification_oracle/oracle_driver.jl",
    "lib/ProcessBigraphs/test/specification_oracle/production_driver.jl",
    "lib/ProcessBigraphs/test/specification_oracle/compare.jl",
    "lib/ProcessBigraphs/test/specification_oracle/boundary_check.jl",
    "lib/CorePotts/test/runtests.jl",
    "lib/MakiePotts/test/runtests.jl",
    "integration/runtests.jl",
]

function test_domain(path, text)
    key = lowercase(path * "\n" * text)
    for (pattern, domain) in (
        (r"specification_oracle|transitionkerneloracle|reference_semantics|oracle", "independent_oracle"),
        (r"merks", "bounded_merks_model"),
        (r"shirinifard|cnv", "bounded_cnv_model"),
        (r"checkpoint|persistence|restart|restore", "persistence_and_restart"),
        (r"authoring|compose|fragment|macro|level1|level2", "authoring_and_lowering"),
        (r"structural|algebraic|open_composition", "structure_and_rewriting"),
        (r"engine|solver|sciml|native_field", "engine_and_field_protocol"),
        (r"observation|continuation|history", "observation_and_continuation"),
        (r"scheduler|runtime|transaction|execution", "runtime_transactions"),
        (r"relationship|contact|polarity|focal", "relationships_and_mechanics"),
        (r"algorithm|checkerboard|lottery|sequential|proposal|acceptance", "algorithms"),
        (r"topology|cartesian|logical_state|initialization|lifecycle", "state_and_topology"),
        (r"makie|render|encoding|recipe|explorer", "visualization"),
        (r"schema|store|path|time|canonical|rng", "primitives_and_canonical_values"),
        (r"documentation|quality|evidence|contract_version", "quality_and_evidence"),
        (r"thermodynamics|biophysics|integration", "cross_package_integration"),
    )
        occursin(pattern, key) && return domain
    end
    "package_contract"
end

function keyword_flag(text, expression)
    occursin(expression, lowercase(text))
end

function testsets(text)
    result = String[]
    for match in eachmatch(r"@testset\s+\"([^\"]+)\"", text)
        push!(result, match.captures[1])
    end
    unique(result)
end

function evidence_consumers(path)
    name = basename(path)
    consumers = String[]
    for candidate in EVIDENCE_CONSUMER_PATHS
        candidate == path && continue
        occursin(name, baseline_text(candidate)) && push!(consumers, candidate)
    end
    sort!(unique(consumers))
end

const EVIDENCE_CONSUMER_PATHS = filter(TRACKED) do candidate
    startswith(candidate, "spec/") ||
        startswith(candidate, "design/") ||
        startswith(candidate, "scripts/") ||
        startswith(candidate, ".github/")
end

function build_coverage()
    workflow_paths = filter(path -> startswith(
        path, ".github/workflows/") &&
        any(extension -> endswith(path, extension), (".yml", ".yaml")), TRACKED)
    workflow_text = join(baseline_text.(workflow_paths), "\n")
    test_files = filter(TRACKED) do path
        endswith(path, ".jl") || return false
        startswith(path, "test/") ||
            occursin(r"^lib/[^/]+/test/", path) ||
            startswith(path, "integration/")
    end
    direct_ci_paths = filter(path -> occursin(path, workflow_text), test_files)
    active = reachable_from(vcat(TEST_ROOTS, direct_ci_paths))
    rows = Dict{String, Any}[]
    for path in sort!(test_files)
        text = baseline_text(path)
        lower = lowercase(text)
        backends = String[]
        occursin(r"\bcpu\b", lower) && push!(backends, "CPU")
        occursin(r"\bmetal\b", lower) && push!(backends, "Metal")
        occursin(r"\brocm\b|\bamdgpu\b", lower) && push!(backends, "ROCm")
        occursin(r"\bcuda\b", lower) && push!(backends, "CUDA")
        occursin(r"\bgpu\b|\bdevice\b", lower) && push!(backends, "device_generic")
        isempty(backends) && path in active && push!(backends, "CPU")
        replay = String[]
        occursin(r"\bexact\b|\bdetermin", lower) && push!(replay, "exact_or_deterministic")
        occursin(r"\bnumerical\b|\btolerance\b|isapprox", lower) && push!(replay, "numerical")
        occursin(r"\bstatistical\b|\bdistribution\b", lower) && push!(replay, "statistical")
        models = String[]
        occursin("merks", lower) && push!(models, "Merks2006")
        occursin(r"shirinifard|cnv", lower) && push!(models, "CNV2012")
        occursin("wang", lower) && push!(models, "Wang2009")
        occursin("wortel", lower) && push!(models, "Wortel2021")
        role = endswith(path, "runtests.jl") ? "runner" :
            occursin(r"fixture|harness|oracle\.jl|analysis\.jl|archive\.jl|backend\.jl"i, path) ?
            "support_or_oracle" : "behavioral_test"
        direct_ci_entry = occursin(path, workflow_text)
        execution_state = path in active ? "ordinary_or_oracle_runner" :
            direct_ci_entry ? "direct_ci_entry" : "retained_auxiliary"
        push!(rows, Dict(
            "path" => path,
            "package" => package_for(path),
            "role" => role,
            "active" => path in active || direct_ci_entry,
            "execution_state" => execution_state,
            "sha256" => sha256_hex(baseline_bytes(path)),
            "domain" => test_domain(path, text),
            "semantic_requirements" => testsets(text),
            "happy_path" => occursin("@test", text),
            "negative_path" =>
                occursin(r"@test_throws|@test_broken|throws|reject|invalid"i, text),
            "failure_stage" =>
                occursin(r"fail|rollback|atomic|discard|throw|corrupt"i, text),
            "restart_cut" =>
                occursin(r"restart|restore|checkpoint|resume"i, text),
            "backends" => sort!(unique(backends)),
            "replay_classes" => sort!(unique(replay)),
            "oracle" =>
                occursin(r"oracle|reference|analytic|manufactured"i, path * text),
            "models" => sort!(unique(models)),
            "evidence_consumers" => evidence_consumers(path),
        ))
    end
    Dict(
        "schema_version" => "1.0.0",
        "evidence_id" => "semantic-preserving-consolidation-baseline-coverage-v1",
        "status" => "frozen",
        "qualified_commit" => BASELINE_COMMIT,
        "test_roots" => TEST_ROOTS,
        "tracked_test_file_count" => length(rows),
        "active_test_file_count" => count(row -> row["active"], rows),
        "behavioral_test_file_count" =>
            count(row -> row["role"] == "behavioral_test", rows),
        "classification_method" =>
            "literal and @__DIR__ joinpath include reachability, direct CI entry detection, and conservative path/content signals; every row retains exact source hash and testset requirements",
        "test_files" => rows,
    )
end

function normalized_code_lines(path)
    result = Tuple{Int, String}[]
    block_comment = false
    for (line_number, raw) in enumerate(split(baseline_text(path), '\n'))
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
        isempty(line) && continue
        push!(result, (line_number, line))
    end
    result
end

function duplicate_classification(paths)
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
    any(path -> startswith(path, "src/PottsToolkit.jl"), paths) &&
        any(path -> startswith(path, "src/authoring/Authoring.jl"), paths) &&
        return "public_facade_reexport"
    any(path -> occursin("/test/", path) || startswith(path, "test/") ||
        startswith(path, "integration/"), paths) &&
        any(path -> package_for(path) in (
            "ProcessBigraphs", "CorePotts", "PottsToolkit", "MakiePotts") &&
            (occursin("/src/", path) || startswith(path, "src/") ||
             occursin("/ext/", path) || startswith(path, "ext/")), paths) &&
        return "deliberate_test_oracle_literal"
    all(path -> occursin("/test/", path) || startswith(path, "test/") ||
        startswith(path, "integration/"), paths) &&
        return "test_fixture_or_contract_duplication"
    all(path -> startswith(path, "scripts/"), paths) &&
        return "quality_tooling_duplication"
    all(path -> package_for(path) in (
        "ProcessBigraphs", "CorePotts", "PottsToolkit", "MakiePotts"), paths) &&
        return "accidental_production_duplication_candidate"
    "conventional_or_cross_layer_boilerplate"
end

function build_duplicates()
    paths = filter(TRACKED) do path
        endswith(path, ".jl") || return false
        startswith(path, "src/") ||
            startswith(path, "ext/") ||
            startswith(path, "lib/") ||
            startswith(path, "test/") ||
            startswith(path, "integration/") ||
            startswith(path, "benchmark/") ||
            startswith(path, "scripts/")
    end
    minimum_lines = 16
    windows = Dict{String, Vector{Tuple{String, Int, Vector{String}}}}()
    for path in paths
        lines = normalized_code_lines(path)
        length(lines) >= minimum_lines || continue
        for first in 1:(length(lines) - minimum_lines + 1)
            content = last.(lines[first:(first + minimum_lines - 1)])
            digest = sha256_hex(join(content, "\n"))
            push!(get!(windows, digest,
                Tuple{String, Int, Vector{String}}[]),
                (path, lines[first][1], content))
        end
    end
    clusters = Dict{String, Any}[]
    seen_members = Set{String}()
    for (digest, occurrences) in windows
        distinct_paths = unique(first.(occurrences))
        length(distinct_paths) >= 2 || continue
        members = sort!(["$(path):$(line)" for (path, line, _) in occurrences])
        member_key = join(members, "|")
        member_key in seen_members && continue
        push!(seen_members, member_key)
        classification = duplicate_classification(distinct_paths)
        push!(clusters, Dict(
            "window_sha256" => digest,
            "normalized_line_count" => minimum_lines,
            "classification" => classification,
            "requires_resolution" => classification in (
                "accidental_production_duplication_candidate",
                "test_fixture_or_contract_duplication",
                "quality_tooling_duplication",
            ),
            "paths" => sort!(distinct_paths),
            "occurrences" => members,
            "sample" => occurrences[1][3],
        ))
    end
    sort!(clusters; by=row -> (
        row["classification"], join(row["paths"], "|"), row["window_sha256"]))
    semantic_clusters = [
        Dict(
            "concept" => concept,
            "classification" => classification,
            "scope" => scope,
            "disposition_gate" => gate,
        )
        for (concept, classification, scope, gate) in (
            ("fingerprint builders", "production_authority_review",
                ["ProcessBigraphs", "CorePotts", "PottsToolkit"],
                "process_bigraphs"),
            ("canonical bytes and integrity hashing", "production_authority_review",
                ["ProcessBigraphs", "CorePotts"], "process_bigraphs"),
            ("validation reports and errors", "production_authority_review",
                ["all packages"], "process_bigraphs"),
            ("engine transaction lifecycle", "production_authority_review",
                ["ProcessBigraphs", "CorePotts adapters"], "process_bigraphs"),
            ("field operations and accounting", "production_authority_review",
                ["ProcessBigraphs", "CorePotts"], "core_and_frontends"),
            ("checkpoint validation and legacy conversion",
                "compatibility_plus_production_authority_review",
                ["ProcessBigraphs", "CorePotts"], "process_bigraphs"),
            ("authoring handles and origin maps", "production_authority_review",
                ["ProcessBigraphs", "PottsToolkit"], "process_bigraphs"),
            ("host and portable dispatch", "backend_specific_realization_review",
                ["CorePotts"], "core_and_frontends"),
            ("model fixture construction", "test_fixture_review",
                ["tests", "integration"], "test_and_quality_harness"),
            ("CI and specification integrity helpers", "quality_tooling_review",
                ["scripts", "workflows"], "test_and_quality_harness"),
        )
    ]
    Dict(
        "schema_version" => "1.0.0",
        "evidence_id" =>
            "semantic-preserving-consolidation-baseline-duplication-v1",
        "status" => "frozen",
        "qualified_commit" => BASELINE_COMMIT,
        "detector" =>
            "exact duplicate windows after comment/blank removal and whitespace normalization",
        "minimum_normalized_lines" => minimum_lines,
        "scanned_file_count" => length(paths),
        "exact_clone_cluster_count" => length(clusters),
        "resolution_candidate_count" =>
            count(row -> row["requires_resolution"], clusters),
        "limitations" => [
            "The exact-clone detector intentionally does not equate semantically different code.",
            "The named semantic responsibility clusters supplement exact clone detection.",
            "A candidate classification is not permission to deduplicate independent evidence.",
        ],
        "semantic_responsibility_clusters" => semantic_clusters,
        "exact_clone_clusters" => clusters,
    )
end

function impact_paths(kind)
    sources = source_paths()
    if kind == "cpu_package_family"
        return sort!(unique(vcat(
            sources,
            environment_paths(),
            filter(path -> startswith(path, ".github/workflows/"), TRACKED),
        )))
    end
    backend_extension = kind == "metal_native_field" ?
        "lib/CorePotts/ext/CorePottsMetalExt.jl" :
        "lib/CorePotts/ext/CorePottsAMDGPUExt.jl"
    selected = filter(sources) do path
        startswith(path, "lib/CorePotts/src/") ||
            startswith(path, "lib/ProcessBigraphs/src/") ||
            path == backend_extension
    end
    append!(selected, [
        "benchmark/phase16_native_field_qualification.jl",
        "benchmark/Project.toml",
        "benchmark/Manifest.toml",
        kind == "metal_native_field" ?
            "benchmark/backends/metal/Project.toml" :
            "benchmark/backends/amdgpu/Project.toml",
        kind == "metal_native_field" ?
            "benchmark/backends/metal/Manifest.toml" :
            "benchmark/backends/amdgpu/Manifest.toml",
        ".github/workflows/gpu-validation.yml",
    ])
    sort!(unique(filter(in(TRACKED_SET), selected)))
end

function impact_records(paths)
    [
        Dict(
            "path" => path,
            "sha256" => sha256_hex(baseline_bytes(path)),
        )
        for path in paths
    ]
end

function build_hardware_impact()
    cpu_paths = impact_paths("cpu_package_family")
    metal_paths = impact_paths("metal_native_field")
    rocm_paths = impact_paths("rocm_native_field")
    claims = [
        Dict(
            "id" => "cpu-package-family",
            "backends" => ["CPU"],
            "architectures" => ["x86_64-linux", "aarch64-darwin"],
            "authority" =>
                "design/evidence/process-bigraph-phase16i-evidence-v1.toml",
            "workflow_run_id" => 30399756947,
            "qualified_commit" => BASELINE_COMMIT,
            "source_identity_mode" => "exact_commit_and_tree",
            "path_count" => length(cpu_paths),
            "paths" => impact_records(cpu_paths),
        ),
        Dict(
            "id" => "native-cartesian-field-metal",
            "backends" => ["CPU", "Metal"],
            "architectures" => ["aarch64-darwin"],
            "authority" =>
                "design/evidence/process-bigraph-phase16c-evidence-v1.toml",
            "workflow_run_id" => 30360086075,
            "qualified_source_sha256" =>
                "46b5f430b8774080a2b8f3fd8437795c9cbad6e9699e8c5b2833c4f4715a7c25",
            "source_identity_mode" =>
                "native-field exact source plus conservative transitive package closure",
            "path_count" => length(metal_paths),
            "paths" => impact_records(metal_paths),
        ),
        Dict(
            "id" => "native-cartesian-field-rocm",
            "backends" => ["CPU", "ROCm"],
            "architectures" => ["x86_64-linux"],
            "authority" =>
                "design/evidence/process-bigraph-phase16c-evidence-v1.toml",
            "workflow_run_id" => 30360086075,
            "qualified_source_sha256" =>
                "46b5f430b8774080a2b8f3fd8437795c9cbad6e9699e8c5b2833c4f4715a7c25",
            "source_identity_mode" =>
                "native-field exact source plus conservative transitive package closure",
            "path_count" => length(rocm_paths),
            "paths" => impact_records(rocm_paths),
        ),
    ]
    Dict(
        "schema_version" => "1.0.0",
        "evidence_id" =>
            "semantic-preserving-consolidation-baseline-hardware-impact-v1",
        "status" => "frozen",
        "qualified_commit" => BASELINE_COMMIT,
        "comparison_rule" =>
            "adding, removing, moving, or changing any listed path invalidates the claim; environment or workflow changes also invalidate exact-head evidence",
        "conservatism" =>
            "Metal and ROCm include the complete CorePotts source and ProcessBigraphs transitive runtime source, not only the directly hashed native_fields.jl file",
        "cuda_required" => false,
        "claims" => claims,
    )
end

function verify_runtime_scope()
    scope = [
        ".github", "Project.toml", "Manifest.toml", "benchmark", "docs",
        "examples", "ext", "integration", "lib", "paper", "scripts", "src",
        "test",
    ]
    changed = split(git(
        "diff", "--name-only", BASELINE_COMMIT, "--", scope...), '\n')
    filter!(!isempty, changed)
    generated_prefix = "design/evidence/consolidation-baseline/"
    filter!(path -> !startswith(path, generated_prefix) &&
        path != "scripts/freeze_consolidation_baseline.jl" &&
        path != "scripts/capture_consolidation_identity_fixtures.jl", changed)
    isempty(changed) ||
        error("runtime-scoped files differ from baseline commit: $(join(changed, ", "))")
    status_lines = filter(!isempty, split(git(
        "status", "--porcelain", "--untracked-files=all"), '\n'))
    allowed = Set((
        "scripts/freeze_consolidation_baseline.jl",
        "scripts/capture_consolidation_identity_fixtures.jl",
    ))
    untracked_runtime = String[]
    for line in status_lines
        startswith(line, "?? ") || continue
        path = line[4:end]
        path in allowed && continue
        any(prefix -> path == prefix || startswith(path, prefix * "/"), scope) &&
            push!(untracked_runtime, path)
    end
    isempty(untracked_runtime) ||
        error("untracked runtime-scoped files are outside the freeze allowlist: " *
            join(untracked_runtime, ", "))
end

verify_runtime_scope()
emit("identity-v1.toml", build_identity())
emit("api-v1.toml", build_api())
emit("coverage-v1.toml", build_coverage())
emit("duplication-v1.toml", build_duplicates())
emit("hardware-impact-v1.toml", build_hardware_impact())
println(WRITE ? "baseline static artifacts generated" :
    "baseline static artifacts verified")
