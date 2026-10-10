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
using SHA: sha256
using TOML: TOML

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

# OpenVT figure functions (D-175). The methods live in the `PottsModelsMakieExt` extension,
# which loads with Makie and MakiePotts (`using CairoMakie, MakiePotts`); without them
# PottsModels neither loads nor depends on Makie.
"""
    PottsModels.openvt_f4_figure(σ, c) -> Makie.Figure

The lattice panel of the OpenVT monolayer benchmark's Fig 4 (the free-surface fraction
fᵢ; `G:results/free_surface.tex`, D-175): the 2D ownership array `σ` (`σ[I] > 0` a cell id,
`0` medium) drawn with `pottsplot` (`CellIdentityEncoding`, medium RGB(236,236,236), no
boundaries), a white site grid, and one short dash for every pair (site of cell `c`, Moore(1)
neighbour owned by anything else), across the pair's shared edge or corner: magenta
RGB(231,41,138) for medium partners and amber RGB(255,192,0) for other cells. Cells are
tinted with the .tex's cell colours when `σ`'s ids are exactly `1:n` with `n ≤ 4`, and with
the automatic identity palette (D-172) otherwise. A label shows
both counts, `fᵢ = m / (m + n)`, the G1 count of [`openvt_snapshot`](@ref
PottsModels.openvt_snapshot). The .tex's black outline of cell i is left out on purpose: no
cell outlines are drawn (D-156).

Requires Makie and MakiePotts to be loaded (`using CairoMakie, MakiePotts`).
"""
function openvt_f4_figure end

"""
    PottsModels.openvt_f1_figure(frame; window = 64, banner = true, areas = nothing) -> Makie.Figure

The Potts.jl panel of the OpenVT monolayer benchmark's Fig 1 ("Overview of participating
frameworks"; `G:results/introduction.tex`, D-175, D-185). `frame` is a 2D MakiePotts render
frame of a colony, e.g. `renderframe(u)` of the first state of case (a) with 10⁴ cells.

The panel is a square axis showing an unchanged `window × window` block of `frame` (same
owners, same cell identities and generations), centred on the colony rim along the 45°
diagonal from the colony centroid (colony lower left, medium upper right), in the style of
the other frameworks' closeups ([`openvt_colony_panel!`](@ref PottsModels.openvt_colony_panel!)
with `colour = :area`): each cell coloured by its area with `coolwarm`, scaled to the min–max
of the areas of the cells in the panel, a white medium and thin black pixel-edge boundaries
between unlike ids. The areas are the cells' site counts in the whole `frame`, so a cell cut
by the window keeps its full area; `areas` (cell id => area) supplies them instead, e.g. for a
block stored without the rest of the lattice. Above the panel, 1/45 of the panel high apart,
is the 5/45-high banner in the proposed Potts.jl colour RGB(8,29,88) with "Potts.jl" in white
bold; `banner = false` leaves it out and gives the bare panel (the consortium's
`closeup.png`). The 64-site default, about 8 cell diameters, is an estimate of what the TST
closeup shows.

Requires Makie and MakiePotts to be loaded (`using CairoMakie, MakiePotts`).
"""
function openvt_f1_figure end

"""
    PottsModels.openvt_colony_panel!(ax, frame; colour = :area, areas = nothing,
        inhibited = nothing, colorrange = nothing, linewidth = 0.75,
        state_colours = (growing, inhibited)) -> PottsPlot

Draw a 2D MakiePotts render frame into the Makie axis `ax` in the style of the OpenVT
consortium's colony figures (D-185; spec 15 §4.0.2): one `pottsplot` on a white medium and
thin black boundaries along every pixel edge between unlike ids (cell–cell and
cell–medium), drawn as one `linesegments` plot with square caps so the outline has no gaps.

- `colour = :area`: each cell coloured by its area with `coolwarm`. `areas` (cell id =>
  area) defaults to the cells' site counts in `frame`; `colorrange` defaults to the min–max
  of the areas of the cells in `frame`.
- `colour = :state`: growing and inhibited cells from `inhibited` (cell id => `true`/`1` for
  inhibited), by default in the colours of M's 2 Oct Fig 7: growing RGB(44,123,182),
  inhibited RGB(253,174,97); `state_colours = (growing, inhibited)` sets others (the 9 Oct
  draft's grids use yellow and teal or red).

Requires Makie and MakiePotts to be loaded (`using CairoMakie, MakiePotts`).
"""
function openvt_colony_panel! end
public openvt_f4_figure, openvt_f1_figure, openvt_colony_panel!

include("benchmarks/openvt_analysis.jl")
include("benchmarks/openvt_package.jl")
public openvt_submission_package

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
