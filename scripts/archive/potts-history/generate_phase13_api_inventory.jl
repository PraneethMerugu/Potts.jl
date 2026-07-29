using CorePotts
using PottsToolkit
using SHA
using TOML

const ROOT = normpath(joinpath(@__DIR__, ".."))
const POLICY_PATH = joinpath(
    ROOT, "design", "audits", "phase-13-api-freeze-policy.toml")
const PHASE11_COMPONENT_PATH = joinpath(
    ROOT, "design", "audits", "phase-11-stable-component-inventory.toml")
const PHASE14_PUBLIC_API_PATH = joinpath(
    ROOT, "design", "audits", "phase-14-public-api-v2.toml")
const PHASE16_PUBLIC_API_PATH = joinpath(
    ROOT, "spec", "process-bigraph-phase16-api-v1.toml")
const DEFAULT_OUTPUT = joinpath(
    ROOT, "design", "audits", "phase-13-api-inventory.toml")

function require(condition, message)
    condition || error(message)
end

function exported_names(module_value::Module)
    self = nameof(module_value)
    return sort!([name for name in names(module_value; all = false, imported = false)
                  if name != self]; by = string)
end

function reviewed_additive_exports(module_name::String)
    phase14 = TOML.parsefile(PHASE14_PUBLIC_API_PATH)
    phase16 = TOML.parsefile(PHASE16_PUBLIC_API_PATH)
    return union(
        Set(Symbol.(phase14["modules"][module_name])),
        Set(Symbol.(phase16["cross_package_additive_exports"][module_name])),
    )
end

function phase13_exports(module_value::Module, module_name::String)
    actual = Set(exported_names(module_value))
    allowed = reviewed_additive_exports(module_name)
    missing = sort!(collect(setdiff(allowed, actual)); by = string)
    require(isempty(missing),
        "$module_name is missing reviewed post-freeze exports: $(join(missing, ", "))")
    return sort!(collect(setdiff(actual, allowed)); by = string)
end

function binding_kind(module_value::Module, name::Symbol)
    startswith(string(name), "@") && return "macro"
    value = getfield(module_value, name)
    value isa Module && return "module"
    (value isa DataType || value isa UnionAll) && return "type"
    value isa Function && return "function"
    return "constant"
end

function has_documentation(module_value::Module, name::Symbol)
    binding = Base.Docs.Binding(module_value, name)
    return Base.Docs.hasdoc(binding)
end

function policy_names(section, key)
    return Set(Symbol.(get(section, key, String[])))
end

function validate_policy_names(module_name, exports, sections...)
    for (label, names_set) in sections
        unknown = sort!(collect(setdiff(names_set, exports)); by = string)
        require(isempty(unknown),
            "$module_name policy `$label` contains unknown exports: $(join(unknown, ", "))")
    end
end

function classify_toolkit(policy, exports)
    section = policy["PottsToolkit"]
    candidates = policy_names(section, "stable")
    if get(section, "stable_documented_exports", false)
        union!(candidates, name for name in exports
            if has_documentation(PottsToolkit, name))
    end
    limited = policy_names(section, "limited")
    experimental = policy_names(section, "experimental")
    internal = policy_names(section, "internal")
    validate_policy_names("PottsToolkit", Set(exports),
        "stable" => candidates, "limited" => limited,
        "experimental" => experimental, "internal" => internal)
    override = union(limited, experimental, internal)
    setdiff!(candidates, override)
    stable = Set(name for name in candidates
        if has_documentation(PottsToolkit, name))
    union!(internal, setdiff(Set(exports), union(stable, limited, experimental)))
    return Dict(
        :stable => stable,
        :limited => limited,
        :experimental => experimental,
        :internal => internal,
        :unpromoted => setdiff(candidates, stable),
    )
end

function classify_core(policy, exports, toolkit_classes)
    section = policy["CorePotts"]
    candidates = policy_names(section, "stable_candidates")
    limited = policy_names(section, "limited")
    experimental = policy_names(section, "experimental")
    internal = Set{Symbol}()

    if get(section, "inherit_stable_pottstoolkit_names", false)
        union!(candidates, intersect(Set(exports), toolkit_classes[:stable]))
    end
    if get(section, "inherit_phase11_component_inventory", false)
        component_inventory = TOML.parsefile(PHASE11_COMPONENT_PATH)
        union!(candidates, Symbol(entry["core"]) for entry in component_inventory["component"]
            if entry["status"] != "excluded")
    end
    setdiff!(candidates, union(limited, experimental))
    stable = get(section, "stable_requires_documentation", false) ?
             Set(name for name in candidates if has_documentation(CorePotts, name)) :
             copy(candidates)

    validate_policy_names("CorePotts", Set(exports),
        "stable_candidates" => candidates,
        "limited" => limited, "experimental" => experimental)
    require(isempty(intersect(stable, limited)),
        "CorePotts stable and limited classifications overlap")
    require(isempty(intersect(stable, experimental)),
        "CorePotts stable and experimental classifications overlap")
    require(isempty(intersect(limited, experimental)),
        "CorePotts limited and experimental classifications overlap")
    union!(internal, setdiff(Set(exports), union(stable, limited, experimental)))
    return Dict(
        :stable => stable,
        :limited => limited,
        :experimental => experimental,
        :internal => internal,
        :unpromoted => setdiff(candidates, stable),
    )
end

function class_for(name, classes)
    for classification in (:stable, :limited, :experimental, :internal)
        name in classes[classification] && return classification
    end
    error("unclassified export $name")
end

function module_inventory(module_value, exports, classes)
    entries = Dict{String, Any}[]
    for name in exports
        classification = class_for(name, classes)
        push!(entries, Dict(
            "name" => string(name),
            "classification" => string(classification),
            "kind" => binding_kind(module_value, name),
            "documented" => has_documentation(module_value, name),
        ))
    end
    counts = Dict(string(classification) =>
        count(entry -> entry["classification"] == string(classification), entries)
        for classification in (:stable, :limited, :experimental, :internal))
    undocumented_stable = [
        entry["name"] for entry in entries
        if entry["classification"] == "stable" && !entry["documented"]
    ]
    return entries, counts, undocumented_stable
end

function build_inventory()
    VERSION == v"1.12.6" ||
        error("Phase 13 API inventory requires Julia 1.12.6; found $VERSION")
    policy = TOML.parsefile(POLICY_PATH)
    toolkit_exports = phase13_exports(PottsToolkit, "PottsToolkit")
    core_exports = phase13_exports(CorePotts, "CorePotts")
    toolkit_classes = classify_toolkit(policy, toolkit_exports)
    core_classes = classify_core(policy, core_exports, toolkit_classes)
    toolkit_entries, toolkit_counts, toolkit_undocumented =
        module_inventory(PottsToolkit, toolkit_exports, toolkit_classes)
    core_entries, core_counts, core_undocumented =
        module_inventory(CorePotts, core_exports, core_classes)

    return Dict(
        "schema_version" => "1.0.0",
        "status" => policy["status"],
        "julia_version" => string(VERSION),
        "policy_sha256" => bytes2hex(sha256(read(POLICY_PATH))),
        "phase11_component_inventory_sha256" =>
            bytes2hex(sha256(read(PHASE11_COMPONENT_PATH))),
        "reproduction_command" =>
            "julia --project=. --startup-file=no scripts/generate_phase13_api_inventory.jl --force",
        "modules" => Dict(
            "CorePotts" => Dict(
                "export_count" => length(core_exports),
                "export_set_sha256" =>
                    bytes2hex(sha256(codeunits(join(string.(core_exports), "\n") * "\n"))),
                "counts" => core_counts,
                "unpromoted_candidates" =>
                    sort!(string.(collect(core_classes[:unpromoted]))),
                "undocumented_stable" => core_undocumented,
                "exports" => core_entries,
            ),
            "PottsToolkit" => Dict(
                "export_count" => length(toolkit_exports),
                "export_set_sha256" =>
                    bytes2hex(sha256(codeunits(join(string.(toolkit_exports), "\n") * "\n"))),
                "counts" => toolkit_counts,
                "unpromoted_candidates" =>
                    sort!(string.(collect(toolkit_classes[:unpromoted]))),
                "undocumented_stable" => toolkit_undocumented,
                "exports" => toolkit_entries,
            ),
        ),
    )
end

function parse_arguments(args)
    output = DEFAULT_OUTPUT
    force = false
    index = 1
    while index <= length(args)
        if args[index] == "--force"
            force = true
            index += 1
        elseif args[index] == "--output"
            index < length(args) || error("--output requires a path")
            output = abspath(args[index + 1])
            index += 2
        else
            error("unknown argument $(args[index])")
        end
    end
    return output, force
end

function main(args)
    output, force = parse_arguments(args)
    isfile(output) && !force &&
        error("refusing to overwrite $output without --force")
    mkpath(dirname(output))
    open(output, "w") do io
        TOML.print(io, build_inventory(); sorted = true)
    end
    println("wrote Phase 13 API inventory to $output")
end

abspath(PROGRAM_FILE) == abspath(@__FILE__) && main(ARGS)
