# MakiePotts tests on ReTestItems (TS1b). Test items are in `*_tests.jl`; each file's
# definitions are in its `@testsetup` module, and the old runner's fixtures and helpers are in
# shared/makiepotts.jl. The frozen acceptance file runs unchanged from acceptance_tests.jl.
# (visual_regression.jl, backends/ and clean_install_smoke.jl are separate scripts, as before.)
#
#   julia --project=lib/MakiePotts/test lib/MakiePotts/test/runtests.jl
#
# Environment:
#   MAKIEPOTTS_TEST_NAME = regex   only items whose name matches
#   RETESTITEMS_NWORKERS           worker processes (default 2; 0 runs in this process);
#                                  workers get this process's thread count
#   POTTS_TEST_END_EXPR_FILE       a file whose expression runs after each item (gate tooling)
# test/Project.toml is not a package's test env, so `runtests` is told the env is active.
using ReTestItems, Pkg

const MAKIEPOTTS_TESTDIR = @__DIR__

function makiepotts_tests(; nworkers = parse(Int, get(ENV, "RETESTITEMS_NWORKERS", "2")))
    name = (n = get(ENV, "MAKIEPOTTS_TEST_NAME", ""); isempty(n) ? nothing : Regex(n))
    endfile = get(ENV, "POTTS_TEST_END_EXPR_FILE", "")
    test_end_expr = isempty(endfile) ? Expr(:block) : Meta.parse("begin\n" * read(endfile, String) * "\nend")
    task_local_storage(:SOURCE_PATH, Pkg.Operations.testfile(dirname(Base.active_project()))) do
        runtests(MAKIEPOTTS_TESTDIR; nworkers, name, test_end_expr, testitem_timeout = 3600, retries = 0,
            nworker_threads = string(Threads.nthreads()), logs = :batched)
    end
    return nothing
end

makiepotts_tests()
