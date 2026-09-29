"""
    PottsModels

Published cellular Potts models written in the `Potts` authoring surface, with the initial
conditions used to validate them against the legacy implementations (ROADMAP M4.2).
Each model is an ordinary `@potts_model` constructor: `GranerGlazier(; name = :sorting)`,
keywords override structural parameters and parameter defaults, and `@extend` builds on it.
"""
module PottsModels

using Potts
using DelimitedFiles: readdlm
using Random: MersenneTwister

export GranerGlazier, WortelAct, MerksVasculogenesis, OpenVTMonolayer, AkeebInvasion
export graner_glazier_state, akeeb_state, akeeb_contacts

include("graner_glazier.jl")
include("wortel_act.jl")
include("merks.jl")
include("openvt.jl")
include("akeeb.jl")

end
