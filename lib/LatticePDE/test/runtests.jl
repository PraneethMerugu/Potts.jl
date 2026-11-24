# The tests of LatticePDE. The groups are in test_groups.toml; GROUP and the POTTS_TEST_*
# variables choose what runs, and an argument, when given, is the item-name pattern
# (test/README.md at the repository root).
include(joinpath(@__DIR__, "..", "..", "..", "test", "runner", "PottsTestRunner.jl"))
PottsTestRunner.run_tests(@__DIR__; name = PottsTestRunner.name_pattern(ARGS))
