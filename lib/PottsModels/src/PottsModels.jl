"""
    PottsModels

Published cellular Potts models written in the `Potts` authoring surface, with the initial
conditions used to validate them against the legacy implementations.
Each model is an ordinary `@potts_model` constructor: `GranerGlazier(; name = :sorting)`,
keywords override structural parameters and parameter defaults, and `@extend` builds on it.
"""
module PottsModels

using Potts: Potts, @potts_model, Circle, Closed, Lattice, Metropolis, Moore, Periodic, Point,
    RandomPlane, RandomPoints, VonNeumann, Voronoi, kind, layout, major_length, ownership, overlay, InsertUntil, Tiling
using DelimitedFiles: readdlm
using Random: MersenneTwister

export GranerGlazier, WortelAct, MerksVasculogenesis, OpenVTGrowingMonolayer, SingleDivisionFixture,
    AkeebInvasion
export graner_glazier_state, graner_glazier_aggregate, akeeb_state, akeeb_layout, akeeb_contacts, openvt_monolayer_state, merks_state

include("graner_glazier.jl")
include("wortel_act.jl")
include("merks.jl")
include("openvt.jl")
include("akeeb.jl")

include("analysis/Analysis.jl")
public Analysis

end
