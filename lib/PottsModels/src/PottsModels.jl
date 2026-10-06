"""
    PottsModels

Published cellular Potts models written in the `Potts` authoring surface, with the initial
conditions used to validate them against the legacy implementations.
Each model is an ordinary `@potts_model` constructor: `GranerGlazier(; name = :sorting)`,
keywords override structural parameters and parameter defaults, and `@extend` builds on it.
"""
module PottsModels

using Potts: Potts, @potts_model, Circle, Closed, DiscreteCallback, Lattice, Metropolis, Moore, Periodic, Point,
    RandomPlane, RandomPoints, VonNeumann, Voronoi, kind, layout, major_length, ownership, overlay, InsertUntil, Tiling,
    terminate!
using DelimitedFiles: readdlm
using Random: MersenneTwister
using SciMLBase: ReturnCode

export GranerGlazier, WortelAct, MerksVasculogenesis, OpenVTGrowingMonolayer, SingleDivisionFixture,
    AkeebInvasion, OpenVTChain, OpenVTReferenceMonolayer
export graner_glazier_state, graner_glazier_aggregate, akeeb_state, akeeb_layout, akeeb_contacts, akeeb_observables,
    openvt_monolayer_state, merks_state, openvt_reference_state
export openvt_chain, openvt_release, spring_dashpot_width

include("analysis/Analysis.jl")
public Analysis

include("graner_glazier.jl")
include("wortel_act.jl")
include("merks.jl")
include("openvt.jl")
include("openvt_chain.jl")
include("openvt_reference.jl")
public openvt_snapshot, stop_at_cells, edge_guard
include("akeeb.jl")

end
