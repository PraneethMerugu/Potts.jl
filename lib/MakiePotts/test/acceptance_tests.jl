# The acceptance file acceptance/p6_0by_cell_colours.jl runs unchanged, in this item's own
# module, with the packages the old runner had loaded (TS1b).

@testsetup module MP_acceptance
using Test
using Aqua
using CairoMakie
using MakiePotts
using Random
import Makie
import CorePotts
include("shared/export_all.jl")
end

@testitem "acceptance/p6_0by_cell_colours.jl" setup = [MP_acceptance] tags = [:makiepotts, :acceptance] begin
    include(joinpath(@__DIR__, "acceptance", "p6_0by_cell_colours.jl"))
end
