# LatticePDE tests on ReTestItems. Test items are in `*_tests.jl`; each file's
# definitions are in its `@testsetup` module. A setup includes, in the old include order, the
# definitions of every earlier file it uses (shared/; shared/lp_runner.jl is the old runner's
# preamble: imports, LATTICEPDE_CHECK_FUSION, term helpers and the vocabulary system), so a
# name means in each item what it meant in the old single-Main run. Groups are declared in
# test_groups.toml.
#
#   julia --project=lib/LatticePDE/test lib/LatticePDE/test/runtests.jl [group...]
#
# Environment:
#   GROUP = All (default) | core | qa | gpu (or LatticePDE_<group>)
#   LATTICEPDE_GPU = rocm | metal    also run the device items (`:gpu_only`: device_tests.jl,
#                                    report_device_tests.jl), all in this process
#   LATTICEPDE_QA = false            skip the `:qa` items when running All
#   LATTICEPDE_TEST_NAME = regex     only items whose name matches
#   LATTICEPDE_TEST_TAGS = a,b       only items that carry one of these tags (file names, `qa`)
#   RETESTITEMS_NWORKERS             worker processes (default 3, sized for the 24G scope; 0 runs
#                                    in this process); workers get this process's thread count
#   POTTS_TEST_END_EXPR_FILE         a file whose expression runs after each item (gate tooling)
# Items tagged `:timing` run after the others, one at a time in one worker.
# test/Project.toml is not a package's test env, so `runtests` is told the env is active.
using ReTestItems, Pkg

const LATTICEPDE_TESTDIR = @__DIR__

function _load_lp_groups()
    raw = Pkg.TOML.parsefile(joinpath(LATTICEPDE_TESTDIR, "test_groups.toml"))
    out = Dict{String, Dict{String, Any}}()
    for (name, val) in raw
        val isa AbstractDict || throw(ArgumentError("Invalid entry \"$name\" in LatticePDE test_groups.toml"))
        out[string(name)] = Dict{String, Any}(string(k) => v for (k, v) in val)
    end
    return out
end

function _resolve_lp_groups(groups_table, raw_groups)
    qa = get(ENV, "LATTICEPDE_QA", "true") == "true"
    selected = String[]
    for raw in raw_groups
        g = strip(String(raw))
        startswith(g, "LatticePDE_") && (g = g[length("LatticePDE_") + 1:end])
        g == "LatticePDE" && (g = "All")
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
                throw(ArgumentError("Unknown LatticePDE target group \"$target\""))
            push!(selected, target)
        else
            valid = join(["All"; sort!(collect(keys(groups_table)))], ", ")
            throw(ArgumentError("Unknown LatticePDE test group \"$g\". Valid groups: $valid"))
        end
    end
    return unique(selected)
end

const LATTICEPDE_GROUPS_TABLE = _load_lp_groups()
const LATTICEPDE_RAW_GROUPS = !isempty(ARGS) ? ARGS :
    (!isempty(strip(get(ENV, "GROUP", ""))) ? [strip(ENV["GROUP"])] : ["All"])
const LATTICEPDE_SELECTED_GROUPS = _resolve_lp_groups(LATTICEPDE_GROUPS_TABLE, LATTICEPDE_RAW_GROUPS)

if "gpu" in LATTICEPDE_SELECTED_GROUPS && isempty(strip(get(ENV, "LATTICEPDE_GPU", "")))
    pgpu = lowercase(strip(get(ENV, "POTTS_GPU", "")))
    ENV["LATTICEPDE_GPU"] = isempty(pgpu) ? (Sys.isapple() ? "metal" : "rocm") : pgpu
end

const LATTICEPDE_DEVICE = !isempty(get(ENV, "LATTICEPDE_GPU", ""))

function latticepde_tests(groups = LATTICEPDE_SELECTED_GROUPS;
        nworkers = parse(Int, get(ENV, "RETESTITEMS_NWORKERS", LATTICEPDE_DEVICE ? "0" : "3")))
    qa = get(ENV, "LATTICEPDE_QA", "true") == "true"
    name = (n = get(ENV, "LATTICEPDE_TEST_NAME", ""); isempty(n) ? nothing : Regex(n))
    want = Symbol.(filter(!isempty, split(get(ENV, "LATTICEPDE_TEST_TAGS", ""), ',')))
    endfile = get(ENV, "POTTS_TEST_END_EXPR_FILE", "")
    test_end_expr = isempty(endfile) ? Expr(:block) : Meta.parse("begin\n" * read(endfile, String) * "\nend")
    allow_gpu = "gpu" in groups || (LATTICEPDE_DEVICE && any(g -> g == "All" || g == "LatticePDE", LATTICEPDE_RAW_GROUPS))
    group_specs = [(Symbol.(get(LATTICEPDE_GROUPS_TABLE[g], "tags", String[])),
                    Symbol.(get(LATTICEPDE_GROUPS_TABLE[g], "exclude_tags", String[])))
                   for g in groups]
    in_group(ti) = any(((tgs, ex),) -> begin
        effective_ex = allow_gpu ? filter(!=(:gpu_only), ex) : ex
        (isempty(tgs) || any(in(ti.tags), tgs)) && !any(in(ti.tags), effective_ex)
    end, group_specs)
    picked(ti) = in_group(ti) && (isempty(want) || any(in(ti.tags), want)) &&
        (allow_gpu || !(:gpu_only in ti.tags)) && (qa || !(:qa in ti.tags) || "qa" in groups)
    kw = (; name, test_end_expr, testitem_timeout = 3600, retries = 0, nworker_threads = string(Threads.nthreads()),
        logs = :batched)
    failed = Any[]
    for (f, nw) in ((ti -> picked(ti) && !(:timing in ti.tags), nworkers),
                    (ti -> picked(ti) && :timing in ti.tags, min(nworkers, 1)))
        try
            task_local_storage(:SOURCE_PATH, Pkg.Operations.testfile(dirname(Base.active_project()))) do
                runtests(f, LATTICEPDE_TESTDIR; nworkers = nw, kw...)
            end
        catch e
            e isa ReTestItems.NoTestException && continue
            push!(failed, e)
        end
    end
    isempty(failed) || throw(first(failed))
    return nothing
end

latticepde_tests()
