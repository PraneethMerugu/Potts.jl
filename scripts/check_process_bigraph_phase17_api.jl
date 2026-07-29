#!/usr/bin/env julia

using TOML

const ROOT = let
    prefix = "--root="
    argument = findfirst(arg -> startswith(arg, prefix), ARGS)
    argument === nothing ?
        normpath(joinpath(@__DIR__, "..")) :
        abspath(ARGS[argument][nextind(ARGS[argument], lastindex(prefix)):end])
end
const failures = String[]

check(condition, message) = condition || push!(failures, message)

function walk_expressions!(visitor, value)
    value isa Expr || return
    visitor(value)
    foreach(argument -> walk_expressions!(visitor, argument), value.args)
end

function declared_names(path, head)
    isfile(path) || return Set{String}()
    syntax = Meta.parseall(read(path, String); filename=path)
    result = Set{String}()
    walk_expressions!(syntax) do expression
        expression.head === head || return
        for argument in expression.args
            argument isa Symbol && push!(result, string(argument))
        end
    end
    return result
end

function load(relative)
    path = joinpath(ROOT, relative)
    check(isfile(path), "missing required file: $relative")
    return isfile(path) ? TOML.parsefile(path) : Dict{String,Any}()
end

contract = load("spec/process-bigraph-phase17-api-v1.toml")
inventory = load("spec/process-bigraph-phase17-api-inventory-v1.toml")
entry = load("spec/process-bigraph-phase17-entry-v1.toml")
entrypoint =
    joinpath(ROOT, "lib", "ProcessBigraphs", "src", "ProcessBigraphs.jl")
exports = declared_names(entrypoint, :export)
publics = declared_names(entrypoint, :public)
core_entrypoint =
    joinpath(ROOT, "lib", "CorePotts", "src", "CorePotts.jl")
core_exports = declared_names(core_entrypoint, :export)
core_publics = declared_names(core_entrypoint, :public)

rows = get(inventory, "bindings", Any[])
names = [String(row["name"]) for row in rows]
check(length(names) == length(unique(names)),
    "API inventory contains duplicate binding names")
check(get(inventory, "binding_count", -1) == length(rows),
    "API inventory binding_count is stale")
check(get(inventory, "unclassified_allowed", -1) == 0,
    "API inventory must fail closed on unclassified bindings")

classes = Set(String.(contract["classes"]))
check(all(row -> String(row["class"]) in classes, rows),
    "API inventory contains an unknown classification")

inventory_names = Set(names)
unexpected = sort!(collect(setdiff(union(exports, publics), inventory_names)))
check(isempty(unexpected),
    "unclassified advertised bindings: $(join(unexpected, ", "))")

for name in contract["process_bigraphs"]["user_existing_required"]["exported"]
    matching = filter(row -> row["name"] == name, rows)
    check(length(matching) == 1 &&
          matching[1]["class"] == "exported_user",
        "required user binding $name is not classified exactly once")
end
for name in contract["process_bigraphs"]["user_additions"]["exported"]
    matching = filter(row -> row["name"] == name, rows)
    check(length(matching) == 1 &&
          matching[1]["class"] == "exported_user",
        "required user addition $name is not classified exactly once")
end
for name in vcat(
        contract["process_bigraphs"]["extension_required"]["public_unexported_functions"],
        contract["process_bigraphs"]["extension_required"]["public_unexported_types"])
    matching = filter(row -> row["name"] == name, rows)
    check(length(matching) == 1 &&
          matching[1]["class"] == "public_extension",
        "required extension binding $name is not classified exactly once")
end
for name in contract["process_bigraphs"]["internal_required"]["bindings"]
    matching = filter(row -> row["name"] == name, rows)
    check(length(matching) == 1 &&
          matching[1]["class"] == "internal",
        "required internal binding $name is not classified exactly once")
end

for row in rows
    classification = String(row["class"])
    admitted = classification in ("exported_user", "public_extension")
    check(!admitted || row["docstring_required"] == true,
        "admitted binding $(row["name"]) does not require a docstring")
    check(!admitted || !isempty(String(row["owner_page"])),
        "admitted binding $(row["name"]) has no owning page")
    check(classification != "internal" ||
          (!row["desired_exported"] && !row["desired_public"]),
        "internal binding $(row["name"]) is advertised")
end

implementation_status = get(entry, "implementation_status", "")
boundary_active = implementation_status != "17.A-contract-freeze"
if boundary_active
    desired_exports = Set(String(row["name"]) for row in rows
        if row["desired_exported"])
    desired_publics = Set(String(row["name"]) for row in rows
        if row["desired_public"])
    check(exports == desired_exports,
        "ProcessBigraphs exports differ from the frozen desired boundary")
    check(publics == desired_publics,
        "ProcessBigraphs Julia-public declarations differ from the frozen desired boundary")
    for row in rows
        row["class"] in ("exported_user", "public_extension") || continue
        page = String(row["owner_page"])
        check(isfile(joinpath(ROOT, page)),
            "admitted binding $(row["name"]) owning page does not resolve: $page")
    end

    core_additions = vcat(
        contract["corepotts"]["user_additions"]["exported_types"],
        contract["corepotts"]["user_additions"]["exported_functions"],
        contract["corepotts"]["reused_supported_functions"]["exported"],
    )
    for name in core_additions
        check(String(name) in core_exports,
            "required CorePotts façade binding $name is not exported")
    end
    for name in contract["corepotts"]["internal_required"]["bindings"]
        check(String(name) ∉ core_exports && String(name) ∉ core_publics,
            "CorePotts internal binding $name is advertised")
    end
end

if isempty(failures)
    admitted = count(row ->
        row["class"] in ("exported_user", "public_extension"), rows)
    println("ProcessBigraphs Phase 17 API inventory passed:")
    println("  classified bindings: $(length(rows))")
    println("  admitted user/extension bindings: $admitted")
    println("  desired boundary enforced: $boundary_active")
else
    foreach(message -> println(stderr, "ERROR: ", message), failures)
    error("Phase 17 API inventory failed with $(length(failures)) error(s)")
end
