# The names every PottsModels test setup starts from (its first line):
#
#     include(joinpath(@__DIR__, "..", "shared", "common.jl"))
#
# the packages under test, the layouts, CorePotts, and the device selection of the Potts
# suites (test/shared/devices.jl: `PottsDevices`, one module per process).
using Test, Potts, PottsModels, Aqua, TOML
using Potts.Layouts
using Potts: CorePotts
using Statistics: mean
include(joinpath(@__DIR__, "..", "..", "..", "..", "test", "shared", "devices.jl"))
