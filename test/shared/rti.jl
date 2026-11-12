# ReTestItems for the Potts suite (test/*_tests.jl), shared by test/runtests.jl and test/dev.jl.
#
#     include(joinpath(@__DIR__, "shared", "rti.jl"))   # defines the module `PottsRTI`
#
# `PottsRTI.rti(args...; kw...)` is `ReTestItems.runtests(args...; kw...)` in the active test
# environment. ReTestItems expects `test/Project.toml` to be the test environment of a package
# and refuses an unnamed project ("trying to activate test environment of an unnamed project").
# Ours is the workspace's test project, already active, so `rti` tells ReTestItems so: it treats
# a run as `Pkg.test`'s, in the current environment, when the task-local `SOURCE_PATH` is the
# project's `test/runtests.jl` (`ReTestItems.is_running_test_runtests_jl`).

# the test files are included into the including module (`Main`), which must know the macros
using ReTestItems: @testitem, @testsetup

module PottsRTI
using ReTestItems: ReTestItems
using Pkg: Pkg
using Test: Test

const TESTDIR = dirname(@__DIR__)

function rti(args...; kw...)
    proj = ReTestItems.identify_project(TESTDIR)
    return task_local_storage(() -> ReTestItems.runtests(args...; kw...), :SOURCE_PATH,
        Pkg.Operations.testfile(dirname(proj)))
end

# Workers share the 24G memory scope of the run (one systemd scope per Julia process tree):
# 4 workers of one thread each (the old suite ran in one single-threaded process); a worker
# is restarted after an item when the scope is above 80 % of its limit; an item that runs
# longer than 20 min fails (the slowest testset took 4 min in the old suite).
const NWORKERS = parse(Int, get(ENV, "POTTS_TEST_WORKERS", "4"))
const OPTIONS = (; nworker_threads = 1, memory_threshold = 0.8, testitem_timeout = 1200, retries = 0)

# Items that time code in-process (`:timing`) or start Julia subprocesses (`:subprocess`) run
# after the others, one at a time, on uncontended cores.
serial(ti) = :timing in ti.tags || :subprocess in ti.tags

# POTTS_TEST_PASSLOG=<file>: after each item, append one line per top-level testset of the item
# (item, testset, pass, fail, error, broken), the per-testset pass list of the old suite
function _counts(results, n_passed = 0; nested = true)
    p, f, e, b = n_passed, 0, 0, 0
    for r in results
        if r isa Test.AbstractTestSet
            nested || continue
            q = _counts(r.results, r.n_passed); p += q[1]; f += q[2]; e += q[3]; b += q[4]
        else
            r isa Test.Fail && (f += 1); r isa Test.Error && (e += 1); r isa Test.Broken && (b += 1)
        end
    end
    return (p, f, e, b)
end
function passlog_expr()
    path = get(ENV, "POTTS_TEST_PASSLOG", "")
    isempty(path) && return Expr(:block)
    return Expr(:block, :(let ts = Test.get_testset()
        open($path, "a") do io
            for r in ts.results
                r isa Test.AbstractTestSet || continue
                println(io, ts.description, '\t', r.description, '\t', join($(_counts)(r.results, r.n_passed), '\t'))
            end
            q = $(_counts)(ts.results, ts.n_passed; nested = false)
            any(!iszero, q) && println(io, ts.description, "\t(item level)\t", join(q, '\t'))
        end
    end))
end

"""
    potts_suite(; nworkers = NWORKERS, qa = ENV["POTTS_QA"] != "false", gpu = false)

GROUP=Potts: every item tagged `:potts` except the device files' (`:gpu`; with `gpu = true`
those too, the `:rocm` ones on ROCm only), and except `:qa` when `qa` is false. The serial
items run last, in one worker.
"""
function potts_suite(; nworkers = NWORKERS, qa = get(ENV, "POTTS_QA", "true") == "true", gpu = false)
    rocm = get(ENV, "POTTS_GPU", "") == "rocm"
    keep(ti) = :potts in ti.tags && (gpu || !(:gpu in ti.tags)) && (rocm || !(:rocm in ti.tags)) && (qa || !(:qa in ti.tags))
    return _two_passes(keep, nworkers)
end

"""
    device_suite(; nworkers = 1)

The Potts part of GROUP=GPU, run with POTTS_GPU set: the items that name a device (`:device`)
and the device files' items (`:gpu`; the `:rocm` ones on ROCm only), one at a time (one
device), without `:qa`.
"""
function device_suite(; nworkers = 1, gpu = get(ENV, "POTTS_GPU", ""))
    keep(ti) = (:device in ti.tags || :gpu in ti.tags) && !(:qa in ti.tags) && (gpu == "rocm" || !(:rocm in ti.tags))
    return _two_passes(keep, nworkers)
end

function _two_passes(keep, nworkers)
    errs = Tuple{Any, Any}[]                 # (exception, backtrace), in pass order
    for (pass, n) in ((ti -> keep(ti) && !serial(ti), nworkers), (ti -> keep(ti) && serial(ti), min(nworkers, 1)))
        try
            rti(pass, TESTDIR; nworkers = n, OPTIONS..., test_end_expr = passlog_expr())
        catch e
            e isa ReTestItems.NoTestException && continue
            push!(errs, (e, catch_backtrace()))
        end
    end
    # report every pass that failed, and fail the run with the first one (its stack is the cause;
    # a later pass's error is usually the same failure seen again)
    for (e, bt) in errs[2:end]
        @error "a later pass failed too" exception = (e, bt)
    end
    isempty(errs) && return nothing
    e, bt = first(errs)
    @error "the run failed" exception = (e, bt)   # the first pass's stack is the cause
    throw(e)
end

end
