# A warm session for any test environment of the monorepo: Revise and the test runner, so
# items rerun in one Julia process and reuse its compiled code.
#
#     julia --project=test -i test/runner/session.jl
#     julia --project=lib/CorePotts/test -i test/runner/session.jl
#
#     run_tests(name = "coarse field")                    # items whose name matches
#     run_tests(tags = :fields_coarse)                    # items with a tag
#     run_tests(file = "fields_short_tests.jl")           # every item of one file
#     run_tests(name = "is_kind", workers = 1)            # in a fresh worker process
#
# In the session the items run in this process (POTTS_TEST_WORKERS=0), and at the root the
# group is the Potts suite (GROUP=Potts), not every package; set either variable before
# loading this file to choose otherwise. Revise picks up `src` edits when it is on the load
# path (for example in your default environment); test files are read again on every call.
# A long session can carry state that tests mutate: fresh processes (runtests.jl) stay the
# reference for gates and reported results.
if Base.identify_package("Revise") === nothing
    @warn "Revise is not on the load path (add it to your default environment); src edits \
        need a new session"
else
    @eval using Revise
end
include(joinpath(@__DIR__, "PottsTestRunner.jl"))
using .PottsTestRunner: run_tests

get!(ENV, "POTTS_TEST_WORKERS", "0")
get!(ENV, "GROUP", PottsTestRunner.session_group(dirname(Base.active_project())))

@info "Test session for $(dirname(Base.active_project())) (GROUP=$(ENV["GROUP"])): \
    run_tests(name = \"…\"), run_tests(tags = :tag), run_tests(file = \"x_tests.jl\")"
