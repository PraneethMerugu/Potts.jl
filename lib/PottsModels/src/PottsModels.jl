"""
    PottsModels

Published cellular Potts models written in the `Potts` authoring surface, with the initial
conditions used to validate them against the legacy implementations.
Each model is an ordinary `@potts_model` constructor: `GranerGlazier(; name = :sorting)`,
keywords override structural parameters and parameter defaults, and `@extend` builds on it.
"""
module PottsModels

using Potts: Potts, @potts_model, Center, Circle, Closed, DiscreteCallback, Eden, Frame, Lattice, Metropolis, Moore,
    NeighborOrder, Periodic, Point, RandomPlane, RandomPoints, Scattered, Splits, VonNeumann, Voronoi, kind, layout,
    major_length, ownership, overlay, InsertUntil, Tiling, terminate!
# for the compile workload (end of this file)
using Potts: CheckerboardCPM, ExplicitEuler, PottsProblem, SequentialCPM, init, mtkcompile, step!
using DelimitedFiles: readdlm
using Printf: @sprintf
using PrecompileTools: PrecompileTools
using SciMLBase: ReturnCode

export GranerGlazier, WortelAct, MerksVasculogenesis, OpenVTGrowingMonolayer, SingleDivisionFixture,
    AkeebInvasion, OpenVTChain, OpenVTReferenceMonolayer, Merks2006, Merks2008
export graner_glazier_state, graner_glazier_aggregate, akeeb_state, akeeb_layout, akeeb_contacts, akeeb_observables,
    akeeb_phenotype, openvt_monolayer_state, merks_state, openvt_reference_state, merks_layout, merks2006_layout,
    merks2008_sprout, merks2008_denovo
export openvt_chain, openvt_release, spring_dashpot_width

include("analysis/Analysis.jl")
public Analysis
export openvt_metrics, openvt_metrics_line, openvt_neighbor_histogram, openvt_inhibition_code,
    openvt_inhibition_fractions, write_openvt, read_openvt, openvt_filename

include("graner_glazier.jl")
include("wortel_act.jl")
include("merks.jl")
include("openvt.jl")
include("openvt_chain.jl")
include("openvt_reference.jl")
public openvt_snapshot, openvt_frame, stop_at_cells, edge_guard
include("akeeb.jl")

include("benchmarks/openvt_analysis.jl")

# Precompile the models (D-047; in this file because the guardrails build every other src
# file from `using Potts` alone): every constructor and its `mtkcompile`, and for the published
# models the first `PottsProblem` and sequential MCS in their usual configuration (Akeeb also
# in Float32, sequential and checkerboard), so a session's first construction, problem and
# MCS reuse cached code. The generated code does not depend on the lattice size and RGF ids
# are content hashes, so the small lattices here compile the same functions as any other.
# Developers switch it off with the PrecompileTools preference `precompile_workload = false`.
function _first_mcs(c, op, alg = SequentialCPM(); kw...)
    prob = PottsProblem(c, op, (0, 10); kw...)
    step!(init(prob, alg; save_start = false))
    return nothing
end

PrecompileTools.@setup_workload begin
    σ = zeros(Int32, 24, 24)
    σ[8:14, 8:14] .= 1
    PrecompileTools.@compile_workload begin
        mtkcompile(SingleDivisionFixture(; name = :s))
        gg = graner_glazier_state()
        _first_mcs(mtkcompile(GranerGlazier(; name = :gg)), [ownership => gg[1], kind => gg[2]])
        _first_mcs(mtkcompile(WortelAct(; name = :w, lattice = (24, 24))), [ownership => σ, kind => [:cell]])
        _first_mcs(mtkcompile(MerksVasculogenesis(; name = :m, lattice = (24, 24))),
            merks_state(; lattice = (24, 24), n = 2, side = 5); field_solver = ExplicitEuler(substeps = 15, lower = 0.0))
        _first_mcs(mtkcompile(Merks2006(; name = :m6, lattice = (24, 24))),
            layout(merks2006_layout(; lattice = (24, 24), n = 2, side = 5), (24, 24)); field_solver = ExplicitEuler(substeps = 15))
        _first_mcs(mtkcompile(Merks2008(; name = :m8, lattice = (24, 24))),
            layout(merks2008_denovo(; lattice = (24, 24), n = 4, rounds = 2), (24, 24)); field_solver = ExplicitEuler(substeps = 15))
        _first_mcs(mtkcompile(OpenVTGrowingMonolayer(; name = :o, lattice = (24, 24))),
            openvt_monolayer_state(; lattice = (24, 24)); capacity = 64)
        _first_mcs(mtkcompile(OpenVTChain(; name = :c)), openvt_chain(11))
        _first_mcs(mtkcompile(OpenVTReferenceMonolayer(; name = :r, lattice = (24, 24))),
            openvt_reference_state(; lattice = (24, 24)); capacity = 64)
        a = mtkcompile(AkeebInvasion(; name = :a, lattice = (24, 30)))
        op = akeeb_state(; lattice = (24, 30))
        _first_mcs(a, op; capacity = 1000)
        _first_mcs(a, op; T = Float32, capacity = 1000)
        _first_mcs(a, op, CheckerboardCPM(); T = Float32, capacity = 1000)
    end
end

end
