using TOML

const ROOT = normpath(joinpath(@__DIR__, ".."))
const INVENTORY = joinpath(
    ROOT, "design", "audits", "phase-13-api-inventory.toml")

include(joinpath(@__DIR__, "generate_phase13_api_inventory.jl"))

isfile(INVENTORY) || error("missing generated Phase 13 API inventory")
committed = read(INVENTORY)
mktempdir() do directory
    regenerated_path = joinpath(directory, "phase-13-api-inventory.toml")
    open(regenerated_path, "w") do io
        TOML.print(io, build_inventory(); sorted = true)
    end
    regenerated = read(regenerated_path)
    committed == regenerated || error(
        "Phase 13 API inventory is stale; regenerate it with " *
        "`julia --project=. --startup-file=no scripts/generate_phase13_api_inventory.jl --force`")
end

inventory = TOML.parsefile(INVENTORY)
phase14_registry = TOML.parsefile(joinpath(
    ROOT, "design", "audits", "phase-14-public-api-v2.toml"))
phase16_registry = TOML.parsefile(joinpath(
    ROOT, "spec", "process-bigraph-phase16-api-v1.toml"))
for module_name in ("CorePotts", "PottsToolkit")
    module_inventory = inventory["modules"][module_name]
    isempty(module_inventory["undocumented_stable"]) || error(
        "$module_name has undocumented stable API: " *
        join(module_inventory["undocumented_stable"], ", "))
    sum(values(module_inventory["counts"])) == module_inventory["export_count"] ||
        error("$module_name API classifications do not cover every export")
    module_value = module_name == "CorePotts" ? CorePotts : PottsToolkit
    frozen = Set(Symbol(entry["name"]) for entry in module_inventory["exports"])
    phase14_allowed =
        Set(Symbol.(phase14_registry["modules"][module_name]))
    phase16_allowed = Set(Symbol.(phase16_registry[
        "cross_package_additive_exports"][module_name]))
    isempty(intersect(frozen, phase14_allowed)) || error(
        "$module_name Phase 14 additions overlap the frozen Phase 13 inventory")
    isempty(intersect(frozen, phase16_allowed)) || error(
        "$module_name Phase 16 additions overlap the frozen Phase 13 inventory")
    isempty(intersect(phase14_allowed, phase16_allowed)) || error(
        "$module_name Phase 16 additions duplicate the Phase 14 registry")
    allowed = union(phase14_allowed, phase16_allowed)
    actual = Set(exported_names(module_value))
    actual == union(frozen, allowed) || error(
        "$module_name exports differ from the frozen Phase 13 inventory plus " *
        "the reviewed post-freeze registries")
end

println("Phase 13 API inventory is unchanged; additive exports exactly match the reviewed post-freeze registries")
