# The tests of the monorepo root: the Potts suite (test/*_tests.jl) and every package's
# suite in its own environment. The groups are in test_groups.toml; GROUP and the
# POTTS_TEST_* variables choose what runs, and an argument, when given, is the item-name
# pattern (test/README.md).
include(joinpath(@__DIR__, "runner", "PottsTestRunner.jl"))
PottsTestRunner.run_tests(@__DIR__; name = PottsTestRunner.name_pattern(ARGS))
