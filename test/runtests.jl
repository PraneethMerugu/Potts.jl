# Test entry point for the whole monorepo.
#   GROUP=All (default) | Potts | CorePotts | LatticeFields | LatticePDE | MakiePotts | PottsModels | GPU
#   GROUP=<Sublib>_<group> (e.g. CorePotts_qa, CorePotts_core, LatticeFields_solvers,
#   LatticePDE_qa, MakiePotts_core, Potts_qa, Potts_fields)
# Groups and CI metadata are declared in test/test_groups.toml and lib/<Pkg>/test/test_groups.toml.
# Each sublibrary group runs in the workspace environment of its own test project via subprocess.
# The Potts suite (test/*_tests.jl) runs on ReTestItems in this process and its workers
# (test/shared/rti.jl): GROUP=Potts is the items tagged `:potts` without `:gpu` (and without
# `:qa` when POTTS_QA=false), on POTTS_TEST_WORKERS workers (default 4).
# test/README.md has the full group table, tags, and single-item runs.
using Pkg: Pkg

const ROOT = dirname(@__DIR__)
const MONOREPO_ORDER = ("LatticeFields", "LatticePDE", "CorePotts", "MakiePotts", "Potts", "PottsModels")

include(joinpath(@__DIR__, "shared", "rti.jl"))      # PottsRTI: the Potts suite on ReTestItems
include(joinpath(@__DIR__, "shared", "device_select.jl"))

function load_test_groups(path)
    raw = Pkg.TOML.parsefile(path)
    out = Dict{String, Dict{String, Any}}()
    for (name, val) in raw
        val isa AbstractDict ||
            throw(ArgumentError("test_groups.toml entry \"$name\" in $path must be a table; got $(typeof(val))"))
        out[string(name)] = Dict{String, Any}(string(k) => v for (k, v) in val)
    end
    return out
end

function resolve_group_alias(groups, name)
    seen = Set{String}()
    cur = String(name)
    while true
        cur in seen && throw(ArgumentError("Cyclic group alias in test_groups.toml involving \"$cur\""))
        push!(seen, cur)
        opts = get(groups, cur, nothing)
        opts === nothing && throw(ArgumentError("Unknown test group \"$cur\""))
        target = get(opts, "group", cur)
        target isa AbstractString ||
            throw(ArgumentError("Key `group` for \"$cur\" must be a string; got $(typeof(target))"))
        target == cur && return cur
        cur = String(target)
    end
    return
end

function in_all_groups(groups)
    names = String[]
    for (name, opts) in groups
        get(opts, "in_all", true) == true || continue
        get(opts, "group", name) == name || continue
        push!(names, name)
    end
    ordered = String[n for n in MONOREPO_ORDER if n in names]
    rest = sort!(String[n for n in names if !(n in ordered)])
    return append!(ordered, rest)
end

function detect_sublibrary_group(group::AbstractString, lib_dir::AbstractString)
    isempty(group) && return ("", "All")
    isdir(joinpath(lib_dir, group)) && return (String(group), "All")
    for i in lastindex(group):-1:firstindex(group)
        if group[i] == '_'
            prefix = group[firstindex(group):prevind(group, i)]
            suffix = group[nextind(group, i):end]
            isdir(joinpath(lib_dir, prefix)) && return (String(prefix), String(suffix))
        end
    end
    return ("", String(group))
end

function run_group(project, file, args...; env = ())
    bounds = Base.JLOptions().check_bounds == 0 ? ["--check-bounds=auto"] : String[]
    cmd = addenv(`$(Base.julia_cmd()) --startup-file=no $bounds --project=$project $file $args`, env...)
    @info "Running $(relpath(file, ROOT)) $(join(map(a -> relpath(a, ROOT), args), ' '))"
    return run(cmd)
end

function run_sublib(sublib::AbstractString, subgroup::AbstractString, raw_group::AbstractString)
    sublib_test = joinpath(ROOT, "lib", sublib, "test")
    toml_path = joinpath(sublib_test, "test_groups.toml")
    isfile(toml_path) || error("Missing test_groups.toml for sublibrary $sublib at $toml_path")
    sub_groups = load_test_groups(toml_path)
    isempty(subgroup) &&
        throw(ArgumentError("Empty sublibrary group in GROUP = \"$raw_group\" for $sublib"))
    target = if subgroup == "All"
        "All"
    elseif haskey(sub_groups, subgroup)
        resolve_group_alias(sub_groups, subgroup)
    else
        valid = join(["All"; sort!(collect(keys(sub_groups)))], ", ")
        throw(ArgumentError("Unknown group \"$subgroup\" for sublibrary $sublib (from GROUP = \"$raw_group\"). Valid groups: $valid"))
    end
    return run_group(sublib_test, joinpath(sublib_test, "runtests.jl"); env = ("GROUP" => target,))
end

function run_potts_subgroup(groups, name::AbstractString)
    if name == "Potts" || name == "Potts_All"
        @info "Running the Potts suite (test/*_tests.jl, ReTestItems)"
        return PottsRTI.potts_suite()
    end
    target = resolve_group_alias(groups, name)
    opts = groups[target]
    if target == "Multithreaded"
        @info "Running the Multithreaded suite (test/*_tests.jl, ReTestItems)" threads = Threads.nthreads()
        return PottsRTI.multithreaded_suite()
    end
    if target == "Potts_gpu"
        gpu = strip(get(ENV, "POTTS_GPU", ""))
        if isempty(gpu)
            gpu = Sys.isapple() ? "metal" : "rocm"
            return withenv("POTTS_GPU" => gpu) do
                PottsRTI.device_suite(; gpu)
            end
        end
        return PottsRTI.device_suite(; gpu)
    end
    want = Symbol.(get(opts, "tags", String[]))
    excl = Symbol.(get(opts, "exclude_tags", String[]))
    rocm = get(ENV, "POTTS_GPU", "") == "rocm"
    function keep(ti)
        return :potts in ti.tags &&
            (isempty(want) || any(in(ti.tags), want)) &&
            !any(in(ti.tags), excl) &&
            (:multithreaded in want || !(:multithreaded in ti.tags)) &&
            (rocm || !(:rocm in ti.tags))
    end
    @info "Running Potts group $target" tags = want
    return PottsRTI._two_passes(keep, PottsRTI.NWORKERS)
end

# Device group (not part of All): the device tests of LatticeFields, LatticePDE, CorePotts,
# and Potts, on the backend that POTTS_GPU / COREPOTTS_GPU request (test/shared/device_select.jl,
# D-157). Each sublibrary runs its own ReTestItems `GROUP=gpu` group when POTTS_DEVICE_ONLY=true
# (the default), or `GROUP=All` when POTTS_DEVICE_ONLY=false; the Potts suite runs its `:device`
# and `:gpu` items (`PottsRTI.device_suite`).
# Neither set: the platform's own, Metal on macOS and ROCm elsewhere. On ROCm the CorePotts and
# Potts suites end with the full no-`double` scan of their compiled kernels, and a last step checks
# that every CorePotts kernel and launch body was scanned (test/device_coverage.jl).
function run_gpu_group()
    gpu = PottsDeviceSelect.requested()
    isempty(gpu) && (gpu = Sys.isapple() ? "metal" : "rocm")
    @info "GROUP=GPU on $gpu"
    irdir = get(ENV, "POTTS_DEVICE_IR_DIR", "")       # set: keep the scanned IR there (for comparing runs)
    isempty(irdir) ? (irdir = mktempdir()) : mkpath(irdir)
    env = ("POTTS_GPU" => gpu, "COREPOTTS_GPU" => gpu, "POTTS_DEVICE_IR_DIR" => irdir)
    only = get(ENV, "POTTS_DEVICE_ONLY", "true") == "true"
    sub_group = only ? "gpu" : "All"
    run_group(
        joinpath(ROOT, "lib/LatticeFields/test"), joinpath(ROOT, "lib/LatticeFields/test/runtests.jl");
        env = ("GROUP" => sub_group, "LATTICEFIELDS_GPU" => gpu, "LATTICEFIELDS_QA" => "false")
    )
    run_group(
        joinpath(ROOT, "lib/LatticePDE/test"), joinpath(ROOT, "lib/LatticePDE/test/runtests.jl");
        env = ("GROUP" => sub_group, "LATTICEPDE_GPU" => gpu, "LATTICEPDE_QA" => "false")
    )
    run_group(
        joinpath(ROOT, "lib/CorePotts/test"), joinpath(ROOT, "lib/CorePotts/test/runtests.jl");
        env = ("GROUP" => sub_group, env..., "COREPOTTS_QA" => "false")
    )
    withenv(env..., "POTTS_QA" => "false") do
        only ? PottsRTI.device_suite() : PottsRTI.potts_suite(; nworkers = 1, gpu = true)
    end
    return only && gpu == "rocm" && run_group(joinpath(ROOT, "test"), joinpath(ROOT, "test/device_coverage.jl"); env)
end

function run_root_group(groups, name::AbstractString)
    target = resolve_group_alias(groups, name)
    opts = groups[target]
    if haskey(opts, "sublib")
        return run_sublib(opts["sublib"], "All", name)
    elseif target == "GPU"
        return run_gpu_group()
    else
        return run_potts_subgroup(groups, target)
    end
end

function dispatch(group_name::AbstractString)
    groups = load_test_groups(joinpath(@__DIR__, "test_groups.toml"))
    lib_dir = joinpath(ROOT, "lib")
    return if group_name == "All"
        for name in in_all_groups(groups)
            run_root_group(groups, name)
        end
    elseif group_name == "Potts_All"
        run_potts_subgroup(groups, "Potts_All")
    elseif haskey(groups, group_name)
        run_root_group(groups, group_name)
    else
        sublib, subgroup = detect_sublibrary_group(group_name, lib_dir)
        if !isempty(sublib)
            run_sublib(sublib, subgroup, group_name)
        else
            sublibs = sort!(filter(d -> isdir(joinpath(lib_dir, d, "test")), readdir(lib_dir)))
            valid = join(sort!(collect(keys(groups))), ", ")
            throw(ArgumentError("Unknown test GROUP = \"$group_name\". Valid root groups: All, $valid; or <Sublib>_<group> for $(join(sublibs, ", "))."))
        end
    end
end

const GROUP = let g = strip(get(ENV, "GROUP", ""))
    isempty(g) && !isempty(ARGS) && (g = strip(ARGS[1]))
    isempty(g) ? "All" : String(g)
end

dispatch(GROUP)
