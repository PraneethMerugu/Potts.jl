# LatticeFields tests on ReTestItems. Test items are in `*_tests.jl` (the group
# directories ir/, compile/, schedule/, problems/, solvers/, qa/, solvers_gate/, and exec at
# the top); each file's definitions are in its `@testsetup` module, which includes the
# helpers it uses (exec_helpers.jl, host_runner.jl, fixtures.jl, solvers_cases.jl,
# device_backend.jl) and the definitions it shares with other files (shared/). Groups are
# declared in test_groups.toml.
#
#   julia --project=lib/LatticeFields/test lib/LatticeFields/test/runtests.jl [groups...]
#
# groups (tags): exec, ir, compile, schedule, problems, solvers, qa (all by default);
# `solvers_gate` (the solver iteration budget sweep over sizes, about 10 minutes) and `gpu`
# are opt-in. Environment:
#   GROUP = All (default) | exec | ir | compile | schedule | problems | solvers | qa |
#   solvers_gate | gpu
#   LATTICEFIELDS_GPU (or POTTS_GPU) = metal | rocm   also run the device items
#                                                     (`:gpu_only`)
#   LATTICEFIELDS_QA = false            skip the qa group when running All
#   LATTICEFIELDS_TEST_NAME = regex     only items whose name matches
#   RETESTITEMS_NWORKERS                worker processes (default 3, sized for the 24G
#                                       scope; 0 runs in this process); workers get this
#                                       process's thread count. With a device: 0 (one
#                                       process on the device).
#   POTTS_TEST_END_EXPR_FILE            a file whose expression runs after each item (gate
#                                       tooling)
# Items tagged `:timing` run after the others, one at a time in one worker.
# test/Project.toml is not a package's test env, so `runtests` is told the env is active.
using ReTestItems, Pkg

const LATTICEFIELDS_TESTDIR = @__DIR__

function _load_lf_groups()
    raw = Pkg.TOML.parsefile(joinpath(LATTICEFIELDS_TESTDIR, "test_groups.toml"))
    out = Dict{String, Dict{String, Any}}()
    for (name, val) in raw
        val isa AbstractDict ||
            throw(ArgumentError("Invalid entry \"$name\" in LatticeFields \
                test_groups.toml"))
        out[string(name)] = Dict{String, Any}(string(k) => v for (k, v) in val)
    end
    return out
end

function _resolve_lf_groups(groups_table, raw_groups)
    selected = String[]
    for raw in raw_groups
        g = strip(String(raw))
        startswith(g, "LatticeFields_") && (g = g[(length("LatticeFields_") + 1):end])
        g == "LatticeFields" && (g = "All")
        if g == "All"
            for name in sort!(collect(keys(groups_table)))
                opts = groups_table[name]
                get(opts, "in_all", true) == true || continue
                get(opts, "group", name) == name || continue
                push!(selected, name)
            end
        elseif haskey(groups_table, g)
            target = string(get(groups_table[g], "group", g))
            haskey(groups_table, target) ||
                throw(ArgumentError("Unknown LatticeFields target group \"$target\""))
            push!(selected, target)
        else
            valid = join(["All"; sort!(collect(keys(groups_table)))], ", ")
            throw(
                ArgumentError(
                    "Unknown LatticeFields test group \"$g\". Valid groups: $valid"
                )
            )
        end
    end
    return unique(selected)
end

const LATTICEFIELDS_GROUPS_TABLE = _load_lf_groups()
const LATTICEFIELDS_RAW_GROUPS = if !isempty(ARGS)
    ARGS
elseif !isempty(strip(get(ENV, "GROUP", "")))
    [strip(ENV["GROUP"])]
else
    ["All"]
end
const LATTICEFIELDS_SELECTED_GROUPS = _resolve_lf_groups(
    LATTICEFIELDS_GROUPS_TABLE,
    LATTICEFIELDS_RAW_GROUPS
)

if "gpu" in LATTICEFIELDS_SELECTED_GROUPS &&
        isempty(strip(get(ENV, "LATTICEFIELDS_GPU", ""))) &&
        isempty(strip(get(ENV, "POTTS_GPU", "")))
    ENV["LATTICEFIELDS_GPU"] = Sys.isapple() ? "metal" : "rocm"
end

const gpu = lowercase(strip(get(ENV, "LATTICEFIELDS_GPU", get(ENV, "POTTS_GPU", ""))))
gpu in ("", "metal", "rocm") ||
    error("LATTICEFIELDS_GPU must be \"\", \"metal\" or \"rocm\"; got \"$gpu\"")

function latticefields_tests(
        groups = LATTICEFIELDS_SELECTED_GROUPS;
        nworkers = parse(Int, get(ENV, "RETESTITEMS_NWORKERS", isempty(gpu) ? "3" : "0"))
    )
    resolved = _resolve_lf_groups(LATTICEFIELDS_GROUPS_TABLE, groups)
    qa = get(ENV, "LATTICEFIELDS_QA", "true") == "true"
    explicit_qa = any(g -> g == "qa" || g == "LatticeFields_qa", groups)
    active = filter(g -> g != "qa" || qa || explicit_qa, resolved)
    gs = Symbol[]
    for g in active
        append!(gs, Symbol.(get(LATTICEFIELDS_GROUPS_TABLE[g], "tags", [g])))
    end
    name = (n = get(ENV, "LATTICEFIELDS_TEST_NAME", ""); isempty(n) ? nothing : Regex(n))
    endfile = get(ENV, "POTTS_TEST_END_EXPR_FILE", "")
    test_end_expr = if isempty(endfile)
        Expr(:block)
    else
        Meta.parse("begin\n" * read(endfile, String) * "\nend")
    end
    picked(ti) = any(in(ti.tags), gs) && (!isempty(gpu) || !(:gpu_only in ti.tags))
    kw = (;
        name, test_end_expr, testitem_timeout = 3600, retries = 0,
        nworker_threads = string(Threads.nthreads()),
        logs = :batched,
    )
    failed = Any[]
    for (f, nw) in (
            (ti -> picked(ti) && !(:timing in ti.tags), nworkers),
            (ti -> picked(ti) && :timing in ti.tags, min(nworkers, 1)),
        )
        try
            task_local_storage(
                :SOURCE_PATH,
                Pkg.Operations.testfile(dirname(Base.active_project()))
            ) do
                runtests(f, LATTICEFIELDS_TESTDIR; nworkers = nw, kw...)
            end
        catch e
            e isa ReTestItems.NoTestException && continue
            push!(failed, e)
        end
    end
    isempty(failed) || throw(first(failed))
    return nothing
end

latticefields_tests()
