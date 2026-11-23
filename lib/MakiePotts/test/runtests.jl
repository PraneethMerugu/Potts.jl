# The tests of MakiePotts. The groups are in test_groups.toml; GROUP and the POTTS_TEST_*
# variables choose what runs (test/README.md at the repository root).
include(joinpath(@__DIR__, "..", "..", "..", "test", "runner", "PottsTestRunner.jl"))
PottsTestRunner.run_tests(@__DIR__)
