# CorePotts tests on ReTestItems. Test items are in `*_tests.jl`; each file's
# definitions are in its `@testsetup` module, and definitions that several files use are in
# `shared/` (each setup includes the ones it needs). Every item runs in its own module, so
# an item depends only on the setup it names. Groups are declared in test_groups.toml.
#
#   julia --project=lib/CorePotts/test lib/CorePotts/test/runtests.jl [group...]
#
# Environment:
#   GROUP = All (default) | core | qa | gpu (or CorePotts_<group>)
#   COREPOTTS_GPU (or POTTS_GPU) = metal | rocm   device run (D-157): only the items tagged
#       `:device`, in this process, then the full kernel IR scan (`:device_scan`, ROCm).
#       Without a device, the `:gpu_only` items are skipped (the old runner skipped gpu.jl).
#   COREPOTTS_QA = false          skip the `:qa` items when running All
#   COREPOTTS_TEST_NAME = regex   only items whose name matches
#   COREPOTTS_TEST_TAGS = a,b     only items that carry one of these tags
#   RETESTITEMS_NWORKERS          worker processes (default 3, sized for the 24G scope; 0 runs
#                                 in this process). Workers get this process's thread count.
#   POTTS_TEST_END_EXPR_FILE      a file whose expression runs after each item (gate tooling)
# Items tagged `:timing` run after the others, one at a time in one worker.
#
# One item from the REPL (Revise-friendly):
#   using ReTestItems; runtests("lib/CorePotts/test"; name = r"geometry")
# test/Project.toml is not a package's test env, so `runtests` is told the env is active.
using ReTestItems, Pkg

const COREPOTTS_TESTDIR = @__DIR__

function _load_corepotts_groups()
    raw = Pkg.TOML.parsefile(joinpath(COREPOTTS_TESTDIR, "test_groups.toml"))
    out = Dict{String, Dict{String, Any}}()
    for (name, val) in raw
        val isa AbstractDict || throw(ArgumentError("Invalid entry \"$name\" in CorePotts test_groups.toml"))
        out[string(name)] = Dict{String, Any}(string(k) => v for (k, v) in val)
    end
    return out
end

function _resolve_corepotts_groups(groups_table, raw_groups)
    qa = get(ENV, "COREPOTTS_QA", "true") == "true"
    selected = String[]
    for raw in raw_groups
        g = strip(String(raw))
        startswith(g, "CorePotts_") && (g = g[length("CorePotts_") + 1:end])
        g == "CorePotts" && (g = "All")
        if g == "All"
            for name in sort!(collect(keys(groups_table)))
                opts = groups_table[name]
                get(opts, "in_all", true) == true || continue
                get(opts, "group", name) == name || continue
                name == "qa" && !qa && continue
                push!(selected, name)
            end
        elseif haskey(groups_table, g)
            target = string(get(groups_table[g], "group", g))
            haskey(groups_table, target) ||
                throw(ArgumentError("Unknown CorePotts target group \"$target\""))
            push!(selected, target)
        else
            valid = join(["All"; sort!(collect(keys(groups_table)))], ", ")
            throw(ArgumentError("Unknown CorePotts test group \"$g\". Valid groups: $valid"))
        end
    end
    return unique(selected)
end

const COREPOTTS_GROUPS_TABLE = _load_corepotts_groups()
const COREPOTTS_SELECTED_GROUPS = let cli = filter(a -> normpath(abspath(a)) != normpath(abspath(@__FILE__)), ARGS)
    raw = if !isempty(cli)
        cli
    elseif !isempty(strip(get(ENV, "GROUP", "")))
        [strip(ENV["GROUP"])]
    else
        ["All"]
    end
    _resolve_corepotts_groups(COREPOTTS_GROUPS_TABLE, raw)
end

if "gpu" in COREPOTTS_SELECTED_GROUPS && isempty(strip(get(ENV, "COREPOTTS_GPU", ""))) && isempty(strip(get(ENV, "POTTS_GPU", "")))
    ENV["COREPOTTS_GPU"] = Sys.isapple() ? "metal" : "rocm"
end

const COREPOTTS_DEVICES = joinpath(@__DIR__, "..", "..", "..", "test", "shared", "devices.jl")
isdefined(@__MODULE__, :PottsDevices) || !isfile(COREPOTTS_DEVICES) || include(COREPOTTS_DEVICES)
const COREPOTTS_ON_DEVICE = isdefined(@__MODULE__, :PottsDevices) && PottsDevices.on_device()

function corepotts_tests(groups = COREPOTTS_SELECTED_GROUPS;
        nworkers = parse(Int, get(ENV, "RETESTITEMS_NWORKERS", "3")))
    qa = get(ENV, "COREPOTTS_QA", "true") == "true"
    name = (n = get(ENV, "COREPOTTS_TEST_NAME", ""); isempty(n) ? nothing : Regex(n))
    want = Symbol.(filter(!isempty, split(get(ENV, "COREPOTTS_TEST_TAGS", ""), ',')))
    endfile = get(ENV, "POTTS_TEST_END_EXPR_FILE", "")
    test_end_expr = isempty(endfile) ? Expr(:block) : Meta.parse("begin\n" * read(endfile, String) * "\nend")

    group_specs = [(Symbol.(get(COREPOTTS_GROUPS_TABLE[g], "tags", String[])),
                    Symbol.(get(COREPOTTS_GROUPS_TABLE[g], "exclude_tags", String[])))
                   for g in groups]
    in_group(ti) = any(((tgs, ex),) -> (isempty(tgs) || any(in(ti.tags), tgs)) && !any(in(ti.tags), ex), group_specs)
    picked(ti) = in_group(ti) && (isempty(want) || any(in(ti.tags), want)) && (qa || !(:qa in ti.tags) || "qa" in groups)
    kw = (; name, test_end_expr, testitem_timeout = 3600, retries = 0, nworker_threads = string(Threads.nthreads()),
        logs = :batched)
    phases = if COREPOTTS_ON_DEVICE || "gpu" in groups
        [(ti -> (isempty(want) || any(in(ti.tags), want)) && :device in ti.tags && !(:device_scan in ti.tags), 0),
            (ti -> (isempty(want) || any(in(ti.tags), want)) && :device_scan in ti.tags, 0)]
    else
        [(ti -> picked(ti) && !(:gpu_only in ti.tags) && !(:timing in ti.tags), nworkers),
            (ti -> picked(ti) && !(:gpu_only in ti.tags) && :timing in ti.tags, min(nworkers, 1))]
    end
    failed = Any[]
    for (f, nw) in phases
        try
            task_local_storage(:SOURCE_PATH, Pkg.Operations.testfile(dirname(Base.active_project()))) do
                runtests(f, COREPOTTS_TESTDIR; nworkers = nw, kw...)
            end
        catch e
            e isa ReTestItems.NoTestException && continue
            push!(failed, e)
        end
    end
    isempty(failed) || throw(first(failed))
    return nothing
end

corepotts_tests()
