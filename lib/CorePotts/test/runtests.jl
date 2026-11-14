# CorePotts tests on ReTestItems (TS1b). Test items are in `*_tests.jl`; each file's
# definitions are in its `@testsetup` module, and definitions that several files use are in
# `shared/` (each setup includes the ones it needs). Every item runs in its own module, so
# an item depends only on the setup it names.
#
#   julia --project=lib/CorePotts/test lib/CorePotts/test/runtests.jl
#
# Environment:
#   COREPOTTS_GPU (or POTTS_GPU) = metal | rocm   device run (D-157): only the items tagged
#       `:device`, in this process, then the full kernel IR scan (`:device_scan`, ROCm).
#       Without a device, the `:gpu_only` items are skipped (the old runner skipped gpu.jl).
#   COREPOTTS_QA = false          skip the `:qa` items
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
const COREPOTTS_DEVICES = joinpath(@__DIR__, "..", "..", "..", "test", "shared", "devices.jl")
isdefined(@__MODULE__, :PottsDevices) || !isfile(COREPOTTS_DEVICES) || include(COREPOTTS_DEVICES)
const COREPOTTS_ON_DEVICE = isdefined(@__MODULE__, :PottsDevices) && PottsDevices.on_device()

function corepotts_tests(; nworkers = parse(Int, get(ENV, "RETESTITEMS_NWORKERS", "3")))
    qa = get(ENV, "COREPOTTS_QA", "true") == "true"
    name = (n = get(ENV, "COREPOTTS_TEST_NAME", ""); isempty(n) ? nothing : Regex(n))
    want = Symbol.(filter(!isempty, split(get(ENV, "COREPOTTS_TEST_TAGS", ""), ',')))
    endfile = get(ENV, "POTTS_TEST_END_EXPR_FILE", "")
    test_end_expr = isempty(endfile) ? Expr(:block) : Meta.parse("begin\n" * read(endfile, String) * "\nend")
    picked(ti) = (isempty(want) || any(in(ti.tags), want)) && (qa || !(:qa in ti.tags))
    kw = (; name, test_end_expr, testitem_timeout = 3600, retries = 0, nworker_threads = string(Threads.nthreads()),
        logs = :batched)
    phases = COREPOTTS_ON_DEVICE ?
        [(ti -> picked(ti) && :device in ti.tags && !(:device_scan in ti.tags), 0),
         (ti -> picked(ti) && :device_scan in ti.tags, 0)] :
        [(ti -> picked(ti) && !(:gpu_only in ti.tags) && !(:timing in ti.tags), nworkers),
         (ti -> picked(ti) && !(:gpu_only in ti.tags) && :timing in ti.tags, min(nworkers, 1))]
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
