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

function _shuffle!(v::AbstractVector, seed::Integer)
    state = UInt64(seed) == 0 ? UInt64(0x9e3779b97f4a7c15) : UInt64(seed)
    for i in length(v):-1:2
        state ⊻= state >> 12
        state ⊻= state << 25
        state ⊻= state >> 27
        r = (state * UInt64(0x2545f4914f6cdd1d)) % UInt64(i)
        j = Int(r) + 1
        v[i], v[j] = v[j], v[i]
    end
    return v
end

const TESTDIR = dirname(@__DIR__)

_is_test_file(f::AbstractString) =
    endswith(f, "_tests.jl") || endswith(f, "_test.jl") ||
    endswith(f, "-tests.jl") || endswith(f, "-test.jl")

function _collect_test_files(dir::AbstractString)
    out = String[]
    for (root, _, files) in walkdir(dir)
        for f in sort!(files)
            _is_test_file(f) && push!(out, joinpath(root, f))
        end
    end
    return sort!(out)
end

function _ordered_paths(paths, spec::AbstractString = get(ENV, "POTTS_TEST_ORDER", "default"))
    s = lowercase(strip(String(spec)))
    (isempty(s) || s == "default") && return paths
    files = String[]
    for p in paths
        if isdir(p)
            append!(files, _collect_test_files(p))
        else
            push!(files, String(p))
        end
    end
    if s == "reverse"
        reverse!(files)
    elseif s == "random" || startswith(s, "random:")
        seed = s == "random" ? Int(time_ns() & 0x7fffffff) : parse(Int, s[(length("random:") + 1):end])
        @info "PottsRTI test order" order = "random" seed
        _shuffle!(files, seed)
    else
        throw(ArgumentError("Unknown POTTS_TEST_ORDER=$(repr(spec)); expected default, reverse, or random[:seed]"))
    end
    return Tuple(files)
end

function rti(args...; kw...)
    proj = ReTestItems.identify_project(TESTDIR)
    # ReTestItems accepts `(shouldrun, paths...)` or `(paths...)`
    call_args = if !isempty(args) && !(first(args) isa AbstractString) && length(args) >= 2
        (first(args), _ordered_paths(args[2:end])...)
    elseif !isempty(args) && all(a -> a isa AbstractString, args)
        _ordered_paths(args)
    else
        args
    end
    return task_local_storage(() -> ReTestItems.runtests(call_args...; kw...), :SOURCE_PATH,
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
# (item, testset, pass, fail, error, broken), the per-testset pass list of the old suite. Each
# process writes `<file>.<pid>`; the gate script concatenates them into `<file>`.
#
# The expression is evaluated in the item's module in a *worker process*, and ReTestItems
# serializes it there: it must be code with only literals in it. Interpolating a function of this
# module (as an earlier version did with `_counts`) makes the payload a reference to a module the
# worker does not have, and the worker dies while deserializing its first item: the coordinator
# then fails with ECONNRESET on the next write.
function passlog_expr()
    path = get(ENV, "POTTS_TEST_PASSLOG", "")
    isempty(path) && return Expr(:block)
    return quote
        let ts = Test.get_testset()
            # the counts of a testset's subtree: its passes are cumulative, its failures are direct
            function counts(results, n_passed)
                p, f, e, b = n_passed, 0, 0, 0
                for r in results
                    if r isa Test.AbstractTestSet
                        q = counts(r.results, r.n_passed); p += q[1]; f += q[2]; e += q[3]; b += q[4]
                    elseif r isa Test.Fail
                        f += 1
                    elseif r isa Test.Error
                        e += 1
                    elseif r isa Test.Broken
                        b += 1
                    end
                end
                return (p, f, e, b)
            end
            # one file per process (the coordinator and each worker), merged after the run: two
            # processes appending to one file split a row when a write lands in two pieces
            emit(parts...) = open(string($path, ".", getpid()), "a") do io
                write(io, join(parts, '\t'), '\n')
            end
            for r in ts.results
                r isa Test.AbstractTestSet || continue
                emit(ts.description, r.description, counts(r.results, r.n_passed)...)
            end
            # results outside any testset of the item (a bare @test, an error): one row
            d = (0, count(r -> r isa Test.Fail, ts.results), count(r -> r isa Test.Error, ts.results),
                 count(r -> r isa Test.Broken, ts.results))
            d[2] + d[3] + d[4] > 0 && emit(ts.description, "(item level)", d...)
        end
    end
end

"""
    potts_suite(; nworkers = NWORKERS, qa = ENV["POTTS_QA"] != "false", gpu = false)

GROUP=Potts: every item tagged `:potts` except the device files' (`:gpu`; with `gpu = true`
those too, the `:rocm` ones on ROCm only), and except `:qa` when `qa` is false. The serial
items run last, in one worker.
"""
function potts_suite(; nworkers = NWORKERS, qa = get(ENV, "POTTS_QA", "true") == "true", gpu = false)
    rocm = get(ENV, "POTTS_GPU", "") == "rocm"
    keep(ti) = :potts in ti.tags && (gpu || !(:gpu in ti.tags)) && (rocm || !(:rocm in ti.tags)) &&
        (qa || !(:qa in ti.tags)) && !(:gpu_only in ti.tags)   # the D-157 scan needs the device cache
    return _two_passes(keep, nworkers)
end

"""
    device_suite()

The Potts part of GROUP=GPU, run with POTTS_GPU set: the items that name a device (`:device`)
and the device files' items (`:gpu`; the `:rocm` ones on ROCm only), in-process, one at a time
(one device), without `:qa`; the `:device_scan` item last (`_phases`).
"""
function device_suite(; gpu = get(ENV, "POTTS_GPU", ""))
    keep(ti) = (:device in ti.tags || :gpu in ti.tags) && !(:qa in ti.tags) && (gpu == "rocm" || !(:rocm in ti.tags))
    # the D-157 scan is an item tagged `:device_scan`, and it reads the process's kernel cache: it
    # has to run after every other device item, in the process that compiled those kernels. Both
    # phases run in-process (`nworkers = 0`), one item at a time; a worker's cache is its own.
    return _phases(((ti -> keep(ti) && !(:device_scan in ti.tags), 0),
                    (ti -> keep(ti) && :device_scan in ti.tags, 0)))
end

_two_passes(keep, nworkers) =
    _phases(((ti -> keep(ti) && !serial(ti), nworkers), (ti -> keep(ti) && serial(ti), min(nworkers, 1))))

function _phases(phases)
    errs = Tuple{Any, Any}[]                 # (exception, backtrace), in pass order
    for (pass, n) in phases
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
