# MakiePotts tests on ReTestItems. Test items are in `*_tests.jl`; each file's
# definitions are in its `@testsetup` module, and the old runner's fixtures and helpers are in
# shared/makiepotts.jl. The acceptance file runs unchanged from acceptance_tests.jl.
# (`backends/` contains separate optional GL/WGL/visual scripts.)
# Groups are declared in test_groups.toml.
#
#   julia --project=lib/MakiePotts/test lib/MakiePotts/test/runtests.jl [group...]
#
# Environment:
#   GROUP = All (default) | core | acceptance | adversarial | allocations |
#           downstream_conformance | saved_state_channels | visual (or MakiePotts_<group>)
#   MAKIEPOTTS_TEST_NAME = regex   only items whose name matches
#   RETESTITEMS_NWORKERS           worker processes (default 2; 0 runs in this process);
#                                  workers get this process's thread count
#   POTTS_TEST_END_EXPR_FILE       a file whose expression runs after each item (gate tooling)
# test/Project.toml is not a package's test env, so `runtests` is told the env is active.
using ReTestItems, Pkg

const MAKIEPOTTS_TESTDIR = @__DIR__

function _load_mp_groups()
    raw = Pkg.TOML.parsefile(joinpath(MAKIEPOTTS_TESTDIR, "test_groups.toml"))
    out = Dict{String, Dict{String, Any}}()
    for (name, val) in raw
        val isa AbstractDict || throw(ArgumentError("Invalid entry \"$name\" in MakiePotts test_groups.toml"))
        out[string(name)] = Dict{String, Any}(string(k) => v for (k, v) in val)
    end
    return out
end

function _resolve_mp_groups(groups_table, raw_groups)
    selected = String[]
    for raw in raw_groups
        g = strip(String(raw))
        startswith(g, "MakiePotts_") && (g = g[length("MakiePotts_") + 1:end])
        g == "MakiePotts" && (g = "All")
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
                throw(ArgumentError("Unknown MakiePotts target group \"$target\""))
            push!(selected, target)
        else
            valid = join(["All"; sort!(collect(keys(groups_table)))], ", ")
            throw(ArgumentError("Unknown MakiePotts test group \"$g\". Valid groups: $valid"))
        end
    end
    return unique(selected)
end

const MAKIEPOTTS_GROUPS_TABLE = _load_mp_groups()
const MAKIEPOTTS_RAW_GROUPS = !isempty(ARGS) ? ARGS :
    (!isempty(strip(get(ENV, "GROUP", ""))) ? [strip(ENV["GROUP"])] : ["All"])
const MAKIEPOTTS_SELECTED_GROUPS = _resolve_mp_groups(MAKIEPOTTS_GROUPS_TABLE, MAKIEPOTTS_RAW_GROUPS)

function makiepotts_tests(groups = MAKIEPOTTS_SELECTED_GROUPS;
        nworkers = parse(Int, get(ENV, "RETESTITEMS_NWORKERS", "2")),
        qa = get(ENV, "MAKIEPOTTS_QA", "true") == "true"
    )
    name = (n = get(ENV, "MAKIEPOTTS_TEST_NAME", ""); isempty(n) ? nothing : Regex(n))
    endfile = get(ENV, "POTTS_TEST_END_EXPR_FILE", "")
    test_end_expr = isempty(endfile) ? Expr(:block) : Meta.parse("begin\n" * read(endfile, String) * "\nend")
    is_all = any(g -> (s = strip(String(g)); s == "All" || s == "MakiePotts" || s == "MakiePotts_All"), MAKIEPOTTS_RAW_GROUPS) &&
        groups == MAKIEPOTTS_SELECTED_GROUPS
    gs = Symbol[]
    for g in groups
        append!(gs, Symbol.(get(MAKIEPOTTS_GROUPS_TABLE[g], "tags", [g])))
    end
    kw = (; nworkers, name, test_end_expr, testitem_timeout = 3600, retries = 0,
        nworker_threads = string(Threads.nthreads()), logs = :batched)
    task_local_storage(:SOURCE_PATH, Pkg.Operations.testfile(dirname(Base.active_project()))) do
        if is_all
            if qa
                runtests(MAKIEPOTTS_TESTDIR; kw...)
            else
                runtests(ti -> !(:qa in ti.tags), MAKIEPOTTS_TESTDIR; kw...)
            end
        else
            runtests(ti -> any(in(ti.tags), gs) && (qa || !(:qa in ti.tags)), MAKIEPOTTS_TESTDIR; kw...)
        end
    end
    return nothing
end

makiepotts_tests()
