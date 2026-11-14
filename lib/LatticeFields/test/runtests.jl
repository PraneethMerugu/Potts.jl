# LatticeFields tests on ReTestItems (TS1b). Test items are in `*_tests.jl` (the group
# directories ir/, compile/, schedule/, problems/, solvers/, qa/, solvers_gate/, and exec at
# the top); each file's definitions are in its `@testsetup` module, which includes the
# helpers it uses (exec_helpers.jl, host_runner.jl, fixtures.jl, solvers_cases.jl,
# device_backend.jl) and the definitions it shares with other files (shared/).
#
#   julia --project=lib/LatticeFields/test lib/LatticeFields/test/runtests.jl [groups...]
#
# groups (tags): exec, ir, compile, schedule, problems, solvers, qa (all by default);
# `solvers_gate` (the PG-4 size sweep, about 10 minutes) is opt-in.
# Environment:
#   LATTICEFIELDS_GPU (or POTTS_GPU) = metal | rocm   also run the device items (`:gpu_only`)
#   LATTICEFIELDS_QA = false            skip the qa group
#   LATTICEFIELDS_TEST_NAME = regex     only items whose name matches
#   RETESTITEMS_NWORKERS                worker processes (default 3, sized for the 24G scope;
#                                       0 runs in this process); workers get this process's
#                                       thread count. With a device: 0 (one process on the device).
#   POTTS_TEST_END_EXPR_FILE            a file whose expression runs after each item (gate tooling)
# Items tagged `:timing` run after the others, one at a time in one worker.
# test/Project.toml is not a package's test env, so `runtests` is told the env is active.
using ReTestItems, Pkg

const LATTICEFIELDS_TESTDIR = @__DIR__
const gpu = lowercase(strip(get(ENV, "LATTICEFIELDS_GPU", get(ENV, "POTTS_GPU", ""))))
gpu in ("", "metal", "rocm") ||
    error("LATTICEFIELDS_GPU must be \"\", \"metal\" or \"rocm\"; got \"$gpu\"")

function latticefields_tests(groups = isempty(ARGS) ? ["exec", "ir", "compile", "schedule", "problems", "solvers", "qa"] :
                                      ARGS; nworkers = parse(Int, get(ENV, "RETESTITEMS_NWORKERS", isempty(gpu) ? "3" : "0")))
    qa = get(ENV, "LATTICEFIELDS_QA", "true") == "true"
    gs = Symbol.(filter(g -> g != "qa" || qa, groups))
    name = (n = get(ENV, "LATTICEFIELDS_TEST_NAME", ""); isempty(n) ? nothing : Regex(n))
    endfile = get(ENV, "POTTS_TEST_END_EXPR_FILE", "")
    test_end_expr = isempty(endfile) ? Expr(:block) : Meta.parse("begin\n" * read(endfile, String) * "\nend")
    picked(ti) = any(in(ti.tags), gs) && (!isempty(gpu) || !(:gpu_only in ti.tags))
    kw = (; name, test_end_expr, testitem_timeout = 3600, retries = 0, nworker_threads = string(Threads.nthreads()),
        logs = :batched)
    failed = Any[]
    for (f, nw) in ((ti -> picked(ti) && !(:timing in ti.tags), nworkers),
                    (ti -> picked(ti) && :timing in ti.tags, min(nworkers, 1)))
        try
            task_local_storage(:SOURCE_PATH, Pkg.Operations.testfile(dirname(Base.active_project()))) do
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
