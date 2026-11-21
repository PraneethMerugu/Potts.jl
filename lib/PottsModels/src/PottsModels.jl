"""
    PottsModels

Published cellular Potts models written in the `Potts` authoring surface, with the initial
conditions used to validate them against the legacy implementations.
Each model is an ordinary `@potts_model` constructor: `GranerGlazier(; name = :sorting)`,
keywords override structural parameters and parameter defaults, and `@extend` builds on it.
"""
module PottsModels

using Potts: Potts, @potts_model, Closed, DiscreteCallback, Lattice, Metropolis, Moore,
    NeighborOrder, Periodic,
    RandomPlane, VonNeumann, kind, major_length, ownership, terminate!
using Potts.Layouts: Center, Circle, Eden, Fill, Frame, Group, InsertUntil, Interior,
    Objects, Point, RandomPoints, Scattered, Sphere, Splits, Tiling, Voronoi,
    layout, overlay
# for the compile workload (end of this file)
using Potts: CheckerboardCPM, ExplicitEuler, PottsProblem, SequentialCPM, init, mtkcompile,
    step!
using DelimitedFiles: readdlm
using Printf: @sprintf
using PrecompileTools: PrecompileTools
using SciMLBase: ReturnCode
using SHA: sha256
using TOML: TOML

export GranerGlazier, WortelAct, MerksVasculogenesis, OpenVTGrowingMonolayer,
    AkeebInvasion, OpenVTChain, OpenVTReferenceMonolayer, Merks2006, Merks2008,
    ShearedFoam, FortunaMigration
export graner_glazier_state, graner_glazier_aggregate, akeeb_state, akeeb_layout,
    akeeb_contacts, akeeb_observables,
    akeeb_phenotype, openvt_monolayer_state, merks_state, openvt_reference_state,
    merks_layout, merks2006_layout,
    merks2008_sprout, merks2008_denovo, sheared_foam_state, fortuna_lattice, fortuna_layout
export openvt_chain, openvt_release, spring_dashpot_width

include("analysis/Analysis.jl")
public Analysis
export openvt_metrics, openvt_metrics_line, openvt_neighbor_histogram,
    openvt_inhibition_code,
    openvt_inhibition_fractions, write_openvt, read_openvt, openvt_filename

include("graner_glazier.jl")
include("wortel_act.jl")
include("merks.jl")
include("openvt.jl")
include("openvt_chain.jl")
include("openvt_reference.jl")
public openvt_snapshot, openvt_frame, stop_at_cells, edge_guard
include("akeeb.jl")
include("foam.jl")
include("fortuna.jl")

# OpenVT figure functions (D-175). The methods live in the `PottsModelsMakieExt` extension,
# which loads with Makie and MakiePotts (`using CairoMakie, MakiePotts`); without them
# PottsModels neither loads nor depends on Makie.
"""
    PottsModels.openvt_f4_figure(σ, c) -> Makie.Figure

Draw the lattice panel of the OpenVT monolayer benchmark's Fig 4: the free-surface fraction
`fᵢ` of cell `c` (`G:results/free_surface.tex` in the consortium repository).

The 2D ownership array `σ` is drawn with `pottsplot` (`CellIdentityEncoding`, medium
RGB(236,236,236), no boundaries) under a white site grid. One short dash marks every pair
(site of cell `c`, `Moore(1)` neighbor owned by anything else), across the pair's shared
edge or corner: magenta RGB(231,41,138) for medium partners and amber RGB(255,192,0) for
other cells. Cells are tinted with the .tex's cell colors when the cell numbers of `σ` are
exactly `1:n` with `n ≤ 4`, and with the automatic identity palette otherwise. A caption
shows both counts and `fᵢ = m / (m + n)`, the count of
[`openvt_snapshot`](@ref PottsModels.openvt_snapshot). The .tex's black outline of cell `c`
is left out: no cell outlines are drawn.

The method is in an extension and requires Makie and MakiePotts to be loaded
(`using CairoMakie, MakiePotts`).

# Arguments
- `σ::AbstractMatrix{<:Integer}`: the ownership, cell numbers `> 0` and medium `0`.
- `c::Integer`: the cell whose pairs are marked.

Throws an `ArgumentError` when `σ` has a negative entry or `c` owns no site.

# Returns
- `Makie.Figure`: the panel.

# Examples
```julia
using PottsModels, CairoMakie, MakiePotts
σ = [0 0 0 0; 0 1 2 0; 0 1 1 0; 0 0 0 0]
fig = PottsModels.openvt_f4_figure(σ, 1)
```

See also [`openvt_snapshot`](@ref PottsModels.openvt_snapshot).
"""
function openvt_f4_figure end

"""
    PottsModels.openvt_f1_figure(frame; window = 64, banner = true,
        areas = nothing) -> Makie.Figure

Draw the Potts.jl panel of the OpenVT monolayer benchmark's Fig 1 ("Overview of
participating frameworks"; `G:results/introduction.tex` in the consortium repository).

The panel is a square axis that shows an unchanged `window × window` block of `frame`
(same owners, same cell identities and generations). The block is centered on the colony
rim along the 45° diagonal from the colony centroid (colony lower left, medium upper
right), in the style of the other frameworks' closeups
([`openvt_colony_panel!`](@ref PottsModels.openvt_colony_panel!) with `color = :area`):
each cell colored by its area with `coolwarm`, scaled to the min–max of the areas of the
cells in the panel, a white medium and thin black boundaries along the site edges between
unlike owners. The lattice fills the panel edge to edge inside a thin gray frame.

The areas are the cells' site counts in the whole `frame`, so a cell cut by the window
keeps its full area. Above the panel, 1/45 of the panel height apart, is a banner 5/45 of
the panel high in the proposed Potts.jl color RGB(8,29,88), with "Potts.jl" in white bold.
To show a block moved inward from the rim, pass that block as `frame` with `window` equal
to its size. The submitted panel is moved inward to about 70 % tissue (65 to 75 %;
`lib/PottsModels/reproductions/15_openvt_monolayer.jl`).

The method is in an extension and requires Makie and MakiePotts to be loaded
(`using CairoMakie, MakiePotts`).

# Arguments
- `frame`: a 2D MakiePotts render frame of a colony, for example `renderframe(u)`.

# Keywords
- `window::Integer = 64`: the side of the block, in sites. It must be positive. 64 sites
  is about 8 cell diameters, estimated from the TST closeup
  (`lib/PottsModels/reproductions/15_openvt_monolayer.jl`).
- `banner::Bool = true`: draw the banner; `false` gives the bare panel.
- `areas = nothing`: the cell areas (cell number => area), for example for a block stored
  without the rest of the lattice. By default, the site counts in `frame`.

Throws an `ArgumentError` for a frame that is not 2D, a `window` that is not positive, a
`window` larger than the frame, or a frame with no cell.

# Returns
- `Makie.Figure`: the panel.

# Examples
```julia
using PottsModels, CairoMakie, MakiePotts
fig = PottsModels.openvt_f1_figure(renderframe(sol.u[1]); banner = false)
```

See also [`openvt_colony_panel!`](@ref PottsModels.openvt_colony_panel!).
"""
function openvt_f1_figure end

"""
    PottsModels.openvt_colony_panel!(ax, frame; color = :area, areas = nothing,
        inhibited = nothing, colorrange = nothing, linewidth = 0.75,
        state_colors = (growing, inhibited)) -> PottsPlot

Draw a 2D MakiePotts render frame into the Makie axis `ax` in the style of the OpenVT
consortium's colony figures (`docs/design/research/model-specs/15_openvt_monolayer.md`
§4.0.2).

The panel is one `pottsplot` on a white medium, with thin black boundaries along every site
edge between unlike owners (cell–cell and cell–medium). The boundaries are one
`linesegments` plot with square caps, so the outline has no gaps.

- `color = :area`: each cell colored by its area with `coolwarm`.
- `color = :state`: growing and inhibited cells, from `inhibited`. The default colors are
  those of the TST row of the manuscript's Fig 7: growing RGB(44,123,182) and inhibited
  RGB(253,174,97).

The method is in an extension and requires Makie and MakiePotts to be loaded
(`using CairoMakie, MakiePotts`).

# Arguments
- `ax`: a Makie axis.
- `frame`: a 2D MakiePotts render frame.

# Keywords
- `color::Symbol = :area`: `:area` or `:state`.
- `areas = nothing`: the cell areas (cell number => area) for `color = :area`. By default,
  the site counts in `frame`.
- `inhibited = nothing`: cell number => `true` or `1` for an inhibited cell. Required with
  `color = :state`.
- `colorrange = nothing`: the color range of `color = :area`. By default, the min–max of
  the areas of the cells in `frame`.
- `linewidth::Real = 0.75`: the width of the boundaries.
- `state_colors = (growing, inhibited)`: the two colors of `color = :state`.

Throws an `ArgumentError` for a frame that is not 2D, another `color`, `color = :state`
without `inhibited`, `areas` or `inhibited` with no entry for a cell of `frame`, or
`color = :area` with `colorrange === nothing` on a frame with no cell.

# Returns
- `PottsPlot`: the plot of the cells.

# Examples
```julia
using PottsModels, CairoMakie, MakiePotts
fig = Figure()
ax = Axis(fig[1, 1]; aspect = DataAspect())
PottsModels.openvt_colony_panel!(ax, renderframe(u); color = :area)
```

See also [`openvt_f1_figure`](@ref PottsModels.openvt_f1_figure).
"""
function openvt_colony_panel! end
public openvt_f4_figure, openvt_f1_figure, openvt_colony_panel!

include("benchmarks/openvt_analysis.jl")
include("benchmarks/openvt_package.jl")
public openvt_submission_package, openvt_spread_compare, openvt_spread_table

# Precompile the models (D-047; in this file because the guardrails build every other src
# file from `using Potts` alone): every constructor and its `mtkcompile`, and for the
# published models the first `PottsProblem` and sequential MCS in their usual configuration
# (Akeeb also in Float32, sequential and checkerboard), so a session's first construction,
# problem and MCS reuse cached code. The generated code does not depend on the lattice size
# and RGF ids are content hashes, so the small lattices here compile the same functions as
# any other. Developers switch it off with the PrecompileTools preference
# `precompile_workload = false`.
function _first_mcs(c, op, alg = SequentialCPM(); kw...)
    prob = PottsProblem(c, op, (0, 10); kw...)
    step!(init(prob, alg; save_start = false, save_everystep = false))
    return nothing
end

# The workload: also run by the AMDGPU extension (PottsModelsAMDGPUExt), since loading
# AMDGPU invalidates much of this cache (PG-11)
function _precompile_workload()
    σ = zeros(Int32, 24, 24)
    σ[8:14, 8:14] .= 1
    gg = graner_glazier_state()
    _first_mcs(mtkcompile(GranerGlazier(; name = :gg)), [ownership => gg[1], kind => gg[2]])
    _first_mcs(
        mtkcompile(WortelAct(; name = :w, lattice = (24, 24))), [
            ownership => σ, kind => [:cell],
        ]
    )
    _first_mcs(
        mtkcompile(MerksVasculogenesis(; name = :m, lattice = (24, 24))),
        merks_state(; lattice = (24, 24), n = 2, side = 5); field_solver = ExplicitEuler(
            substeps = 15, lower_bound = 0.0
        )
    )
    # Float32 under CheckerboardCPM: the configuration of a device run (PG-11)
    _first_mcs(
        mtkcompile(MerksVasculogenesis(; name = :m, lattice = (24, 24))),
        merks_state(; lattice = (24, 24), n = 2, side = 5), CheckerboardCPM(); T = Float32,
        field_solver = ExplicitEuler(substeps = 15, lower_bound = 0.0)
    )
    _first_mcs(
        mtkcompile(Merks2006(; name = :m6, lattice = (24, 24))),
        layout(merks2006_layout(; lattice = (24, 24), n = 2, side = 5), (24, 24));
        field_solver = ExplicitEuler(substeps = 15)
    )
    _first_mcs(
        mtkcompile(Merks2008(; name = :m8, lattice = (24, 24))),
        layout(merks2008_denovo(; lattice = (24, 24), n = 4, rounds = 2), (24, 24));
        field_solver = ExplicitEuler(substeps = 15)
    )
    _first_mcs(
        mtkcompile(OpenVTGrowingMonolayer(; name = :o, lattice = (24, 24))),
        openvt_monolayer_state(; lattice = (24, 24)); capacity = 64
    )
    _first_mcs(mtkcompile(OpenVTChain(; name = :c)), openvt_chain(11))
    _first_mcs(
        mtkcompile(OpenVTReferenceMonolayer(; name = :r, lattice = (24, 24))),
        openvt_reference_state(; lattice = (24, 24)); capacity = 64
    )
    _first_mcs(
        mtkcompile(ShearedFoam(; name = :f, lattice = (32, 32))),
        [sheared_foam_state(; lattice = (32, 32)); :ytop => 32.0; :ymid => 16.5],
        SequentialCPM(;
            skip_interior = true
        )
    )
    a = mtkcompile(AkeebInvasion(; name = :a, lattice = (24, 30)))
    op = akeeb_state(; lattice = (24, 30))
    _first_mcs(a, op; capacity = 1000)
    _first_mcs(a, op; T = Float32, capacity = 1000)
    _first_mcs(a, op, CheckerboardCPM(); T = Float32, capacity = 1000)
    return nothing
end
PrecompileTools.@setup_workload begin
    PrecompileTools.@compile_workload begin
        _precompile_workload()
    end
end

end
