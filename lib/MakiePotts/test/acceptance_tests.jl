# The acceptance file acceptance/cell_colors.jl runs unchanged, in this item's own
# module, with the packages the old runner had loaded.

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

@testitem "acceptance/cell_colors.jl" setup = [MP_acceptance] tags = [
    :makiepotts,
    :acceptance,
] begin
    include(joinpath(@__DIR__, "acceptance", "cell_colors.jl"))
end
