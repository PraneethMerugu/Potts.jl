using TOML

const ROOT = normpath(joinpath(@__DIR__, ".."))
const COVERAGE_PATH =
    joinpath(ROOT, "design", "evidence", "consolidation-baseline", "coverage-v1.toml")
const MIGRATION_PATH =
    joinpath(ROOT, "spec", "consolidation-test-migrations-v1.toml")
const AUTHORITIES_PATH =
    joinpath(ROOT, "spec", "consolidation-test-authorities-v1.toml")

failures = String[]
check(condition, message) = condition || push!(failures, message)

coverage = TOML.parsefile(COVERAGE_PATH)
migration = TOML.parsefile(MIGRATION_PATH)
authorities = TOML.parsefile(AUTHORITIES_PATH)
rows = coverage["test_files"]
renames = migration["renames"]

old_paths = String[row["old"] for row in renames]
new_paths = String[row["new"] for row in renames]
check(length(old_paths) == length(unique(old_paths)),
    "test migration contains duplicate baseline paths")
check(length(new_paths) == length(unique(new_paths)),
    "test migration maps multiple baseline files to one successor")

baseline_paths = Set(String(row["path"]) for row in rows)
rename_map = Dict(old_paths .=> new_paths)
for (old, new) in rename_map
    check(old in baseline_paths, "test migration names unknown baseline path: $old")
    check(!isfile(joinpath(ROOT, old)), "renamed baseline test still exists: $old")
    check(isfile(joinpath(ROOT, new)), "renamed test successor is missing: $new")
end

function include_targets(path)
    text = read(path, String)
    targets = String[]
    for match in eachmatch(r"""include\(\s*"([^"]+)"\s*\)""", text)
        push!(targets, normpath(joinpath(dirname(path), match.captures[1])))
    end
    for match in eachmatch(
        r"""include\(\s*joinpath\(\s*@__DIR__\s*,((?:\s*"[^"]+"\s*,?)+)\)\s*\)""",
        text,
    )
        pieces = [part.captures[1] for part in
                  eachmatch(Regex("\"([^\"]+)\""), match.captures[1])]
        push!(targets, normpath(joinpath(dirname(path), pieces...)))
    end
    unique!(targets)
end

roots = normpath.(joinpath.(Ref(ROOT), String.(coverage["test_roots"])))
direct_entrypoints =
    normpath.(joinpath.(Ref(ROOT), String.(migration["direct_entrypoints"])))
workflow_corpus = join(
    read.(filter(path -> endswith(path, ".yml"),
        readdir(joinpath(ROOT, ".github", "workflows"); join=true)), String),
    '\n',
)
for path in direct_entrypoints
    relative = relpath(path, ROOT)
    check(occursin(relative, workflow_corpus),
        "direct test entrypoint is not named by a current workflow: $relative")
end
append!(roots, direct_entrypoints)
reachable = Set{String}()
pending = copy(roots)
while !isempty(pending)
    path = pop!(pending)
    path in reachable && continue
    isfile(path) || begin
        push!(failures, "current test root or include is missing: $(relpath(path, ROOT))")
        continue
    end
    push!(reachable, path)
    append!(pending, include_targets(path))
end

for row in rows
    old = String(row["path"])
    successor = get(rename_map, old, old)
    path = normpath(joinpath(ROOT, successor))
    check(isfile(path), "baseline test obligation has no surviving file: $old => $successor")
    if row["active"]
        check(path in reachable,
            "active baseline test obligation is not reachable: $old => $successor")
    end
end

active_count = count(row -> row["active"], rows)
behavioral_count = count(row -> row["role"] == "behavioral_test", rows)
check(active_count == coverage["active_test_file_count"],
    "active baseline test count changed during reconciliation")
check(behavioral_count == coverage["behavioral_test_file_count"],
    "behavioral baseline test count changed during reconciliation")

fixture_scenarios = String[]
for fixture in authorities["fixtures"]
    scenario = String(fixture["scenario"])
    push!(fixture_scenarios, scenario)
    authority = String(fixture["authority"])
    check(isfile(joinpath(ROOT, authority)),
        "fixture authority is missing for $scenario: $authority")
    check(startswith(authority, "test/") ||
          occursin("/test/", authority) ||
          startswith(authority, "integration/"),
        "fixture authority leaks into production for $scenario: $authority")
    for consumer in fixture["consumers"]
        check(isfile(joinpath(ROOT, consumer)),
            "fixture consumer is missing for $scenario: $consumer")
    end
end
check(length(fixture_scenarios) == length(unique(fixture_scenarios)),
    "fixture authority inventory repeats a scenario")

contract_ids = String[]
for suite in authorities["contract_suites"]
    id = String(suite["id"])
    push!(contract_ids, id)
    check(isfile(joinpath(ROOT, suite["authority"])),
        "contract-suite authority is missing for $id: $(suite["authority"])")
    check(length(suite["implementations"]) >= 2,
        "contract suite $id does not exercise multiple implementations")
end
check(length(contract_ids) == length(unique(contract_ids)),
    "contract-suite inventory repeats an id")

if isempty(failures)
    println("All $(length(rows)) baseline test-file obligations map to surviving evidence; " *
            "$(length(rename_map)) paths migrated to domain names.")
    println("Reusable fixture and cross-implementation contract authorities are explicit.")
else
    foreach(message -> println(stderr, "ERROR: ", message), failures)
    error("consolidation test reconciliation failed with $(length(failures)) error(s)")
end
