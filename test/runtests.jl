# The tests of the monorepo root: the Potts suite (test/*_tests.jl) and every package's
# suite in its own environment. The groups are in test_groups.toml; GROUP and the
# POTTS_TEST_* variables choose what runs (test/README.md).
include(joinpath(@__DIR__, "runner", "PottsTestRunner.jl"))
PottsTestRunner.run_tests(@__DIR__)
