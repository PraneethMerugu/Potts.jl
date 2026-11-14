# LatticePDE tests on ReTestItems (TS1b). Test items are in `*_tests.jl`; each file's
# definitions are in its `@testsetup` module. A setup includes, in the old include order, the
# definitions of every earlier file it uses (shared/; shared/lp_runner.jl is the old runner's
# preamble: imports, LATTICEPDE_CHECK_FUSION, term helpers and the vocabulary system), so a
# name means in each item what it meant in the old single-Main run.
#
#   julia --project=lib/LatticePDE/test lib/LatticePDE/test/runtests.jl
#
# Environment:
#   LATTICEPDE_GPU = rocm | metal    also run the device items (`:gpu_only`: device_tests.jl,
#                                    report_device_tests.jl), all in this process
#   LATTICEPDE_TEST_NAME = regex     only items whose name matches
#   LATTICEPDE_TEST_TAGS = a,b       only items that carry one of these tags (file names, `qa`)
#   RETESTITEMS_NWORKERS             worker processes (default 3, sized for the 24G scope; 0 runs
#                                    in this process); workers get this process's thread count
#   POTTS_TEST_END_EXPR_FILE         a file whose expression runs after each item (gate tooling)
# Items tagged `:timing` run after the others, one at a time in one worker.
# test/Project.toml is not a package's test env, so `runtests` is told the env is active.
using ReTestItems, Pkg

const LATTICEPDE_TESTDIR = @__DIR__
const LATTICEPDE_DEVICE = !isempty(get(ENV, "LATTICEPDE_GPU", ""))

function latticepde_tests(; nworkers = parse(Int, get(ENV, "RETESTITEMS_NWORKERS", LATTICEPDE_DEVICE ? "0" : "3")))
    name = (n = get(ENV, "LATTICEPDE_TEST_NAME", ""); isempty(n) ? nothing : Regex(n))
    want = Symbol.(filter(!isempty, split(get(ENV, "LATTICEPDE_TEST_TAGS", ""), ',')))
    endfile = get(ENV, "POTTS_TEST_END_EXPR_FILE", "")
    test_end_expr = isempty(endfile) ? Expr(:block) : Meta.parse("begin\n" * read(endfile, String) * "\nend")
    picked(ti) = (isempty(want) || any(in(ti.tags), want)) && (LATTICEPDE_DEVICE || !(:gpu_only in ti.tags))
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
