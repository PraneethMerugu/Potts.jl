# PottsModels tests on ReTestItems. Test items are in `*_tests.jl`; each file's definitions
# are in its `@testsetup` module, and definitions that several files use are in `shared/`
# (each setup includes the ones it needs). Every item runs in its own module, so an item
# depends only on the setup it names. Groups are declared in test_groups.toml.
#
#   julia --project=lib/PottsModels/test lib/PottsModels/test/runtests.jl [group...]
#
# Environment:
#   GROUP = All (default) | core | qa | acceptance | reproductions | guardrails | gpu
#       (or PottsModels_<group>). `core` is every file but the QA file.
#   POTTSMODELS_SHARD = k/n (default 1/1)   run the k-th of n shards (CI runs 3 processes,
#       .github/ci/parallel.sh). Files are dealt to shards longest first, by their measured
#       wall times (shard_weights.toml; a file it does not list weighs its median), so every
#       process computes the same split and every file runs in exactly one shard.
#   POTTSMODELS_QA = false       leave the QA file out of All
#   POTTSMODELS_TEST_NAME = regex   only items whose name matches
#   POTTS_GPU = metal | rocm     the acceptance files' device testsets run on the device
#       (D-157); the `gpu` group sets it.
#   RETESTITEMS_NWORKERS         worker processes (default 0: the items run in this process,
#       which has the shard's threads)
#   POTTS_TEST_END_EXPR_FILE     a file whose expression runs after each item (gate tooling)
#
# One file from the REPL:
#   using ReTestItems; runtests("lib/PottsModels/test/acceptance/sweep_validation_tests.jl")
# test/Project.toml is not a package's test env, so `runtests` is told the env is active.
using ReTestItems, Pkg, TOML

const POTTSMODELS_TESTDIR = @__DIR__

function _load_pm_groups()
    raw = TOML.parsefile(joinpath(POTTSMODELS_TESTDIR, "test_groups.toml"))
    out = Dict{String, Dict{String, Any}}()
    for (name, val) in raw
        val isa AbstractDict ||
            throw(ArgumentError("Invalid entry \"$name\" in PottsModels test_groups.toml"))
        out[string(name)] = Dict{String, Any}(string(k) => v for (k, v) in val)
    end
    return out
end

function _resolve_pm_groups(groups_table, raw_groups)
    qa = get(ENV, "POTTSMODELS_QA", "true") == "true"
    selected = String[]
    for raw in raw_groups
        g = strip(String(raw))
        startswith(g, "PottsModels_") && (g = g[(length("PottsModels_") + 1):end])
        g == "PottsModels" && (g = "All")
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
                throw(ArgumentError("Unknown PottsModels target group \"$target\""))
            push!(selected, target)
        else
            valid = join(["All"; sort!(collect(keys(groups_table)))], ", ")
            throw(
                ArgumentError(
                    "Unknown PottsModels test group \"$g\". Valid groups: $valid"
                )
            )
        end
    end
    return unique(selected)
end

const POTTSMODELS_GROUPS_TABLE = _load_pm_groups()
# A caller that forwards its own command line (for example `julia runtests.jl Core`) can
# leave this script's path in ARGS; that path is not a group, so it is dropped.
const POTTSMODELS_SELECTED_GROUPS = let cli = filter(
        a -> normpath(abspath(a)) != normpath(abspath(@__FILE__)), ARGS
    )
    raw = if !isempty(cli)
        cli
    elseif !isempty(strip(get(ENV, "GROUP", "")))
        [strip(ENV["GROUP"])]
    else
        ["All"]
    end
    _resolve_pm_groups(POTTSMODELS_GROUPS_TABLE, raw)
end

if "gpu" in POTTSMODELS_SELECTED_GROUPS && isempty(strip(get(ENV, "POTTS_GPU", "")))
    ENV["POTTS_GPU"] = Sys.isapple() ? "metal" : "rocm"
end

const POTTSMODELS_SHARD = let (k, n) = parse.(
        Int,
        split(get(ENV, "POTTSMODELS_SHARD", "1/1"), '/')
    )
    1 <= k <= n || throw(ArgumentError("POTTSMODELS_SHARD = $k/$n: need 1 ≤ k ≤ n"))
    (k, n)
end

"""Every test file, relative to the test directory, in a fixed order."""
function pottsmodels_test_files()
    out = String[]
    for (root, _, files) in walkdir(POTTSMODELS_TESTDIR), f in files
        endswith(f, "_tests.jl") &&
            push!(out, relpath(joinpath(root, f), POTTSMODELS_TESTDIR))
    end
    return sort!(replace.(out, '\\' => '/'))
end

"""The files of the selected groups: a group lists its files by directory (`dirs`), by name
(`files`), or all files except some (`exclude_files`)."""
function pottsmodels_group_files(groups = POTTSMODELS_SELECTED_GROUPS)
    all = pottsmodels_test_files()
    picked = Set{String}()
    for g in groups
        opts = POTTSMODELS_GROUPS_TABLE[g]
        dirs = get(opts, "dirs", String[])
        files = get(opts, "files", String[])
        excl = get(opts, "exclude_files", String[])
        for f in all
            f in excl && continue
            sel = (isempty(dirs) && isempty(files)) ||
                any(d -> startswith(f, d * "/"), dirs) || f in files
            sel && push!(picked, f)
        end
    end
    return filter(in(picked), all)
end

"""Deal `files` to `n` shards, longest first by the weights of shard_weights.toml."""
function pottsmodels_shards(files, n)
    weights = let p = joinpath(POTTSMODELS_TESTDIR, "shard_weights.toml")
        if isfile(p)
            Dict{
                String,
                Float64,
            }(k => Float64(v) for (k, v) in TOML.parsefile(p)["seconds"])
        else
            Dict{String, Float64}()
        end
    end
    known = [weights[f] for f in files if haskey(weights, f)]
    fallback = isempty(known) ? 1.0 : sort(known)[cld(length(known), 2)]
    w(f) = get(weights, f, fallback)
    load = zeros(n)
    shard = Dict{String, Int}()
    for f in sort(files; by = f -> (-w(f), f))                # longest first, ties by name
        j = argmin(load)
        shard[f] = j
        load[j] += w(f)
    end
    return [[f for f in files if shard[f] == j] for j in 1:n]
end

function pottsmodels_tests(
        groups = POTTSMODELS_SELECTED_GROUPS;
        nworkers = parse(Int, get(ENV, "RETESTITEMS_NWORKERS", "0"))
    )
    files = pottsmodels_group_files(groups)
    k, n = POTTSMODELS_SHARD
    mine = pottsmodels_shards(files, n)[k]
    n > 1 && @info "PottsModels shard $k/$n: $(length(mine)) of $(length(files)) files" mine
    isempty(mine) && return nothing
    name = (s = get(ENV, "POTTSMODELS_TEST_NAME", ""); isempty(s) ? nothing : Regex(s))
    endfile = get(ENV, "POTTS_TEST_END_EXPR_FILE", "")
    test_end_expr = if isempty(endfile)
        Expr(:block)
    else
        Meta.parse("begin\n" * read(endfile, String) * "\nend")
    end
    paths = [joinpath(POTTSMODELS_TESTDIR, f) for f in mine]
    # `Pkg.Operations.testfile` is an internal Pkg API (check it on dependency updates). It
    # gives the `runtests.jl` path, which `ReTestItems.runtests` reads from `:SOURCE_PATH`
    # as under `Pkg.test`.
    task_local_storage(
        :SOURCE_PATH,
        Pkg.Operations.testfile(dirname(Base.active_project()))
    ) do
        runtests(
            paths...; nworkers, name, test_end_expr, testitem_timeout = 7200, retries = 0,
            nworker_threads = string(Threads.nthreads()), logs = :batched
        )
    end
    return nothing
end

pottsmodels_tests()
