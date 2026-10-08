# The OpenVT monolayer figure functions (D-175): `PottsModels.openvt_f4_figure` (M Fig 4,
# the free-surface schematic) and `PottsModels.openvt_f1_figure` (M Fig 1, the Potts.jl
# panel and banner). Loaded with Makie and MakiePotts. No cell outlines anywhere (D-156):
# both panels are one `pottsplot` with `boundaries = false`; F4 adds only full-length
# lattice lines (a white site grid) and the pair dashes.
module PottsModelsMakieExt

using PottsModels: PottsModels
using Makie: Makie
using MakiePotts: MakiePotts, CellIdentityEncoding, CellSite, MediumSite, PottsRenderFrame, RenderCellIdentity,
    RenderCellMetadata, RenderGeometry, RenderOwner, cell_metadata, frame_geometry, frame_mcs, frame_size,
    owner_at, pottsplot!

_rgb(r, g, b) = Makie.RGBf(r / 255, g / 255, b / 255)
const MEDIUM_PAIR = _rgb(231, 41, 138)       # free_surface.tex `m`
const CELL_PAIR = _rgb(255, 192, 0)          # free_surface.tex `c`
const MEDIUM_F4 = _rgb(236, 236, 236)        # free_surface.tex `ma!10`
const POTTS_COLOUR = _rgb(8, 29, 88)         # spec §4.0.2, Q18 proposal
# free_surface.tex's cell fills `ca!60`, `cb!60`, `cc!60`, `cd!60` (60 % colour on white) for
# cells i, i−1, i+1, i+2 (ids 1–4); a configuration with more cells takes the automatic palette
_tint(r, g, b; p = 0.6) = Makie.RGBf((p .* (r, g, b) ./ 255 .+ (1 - p))...)
const TEX_CELLS = [_tint(34, 94, 168), _tint(65, 182, 196), _tint(29, 145, 192), _tint(117, 195, 177)]
# `mydash` (on 0.125, off 0.065 of the dash scale), in units of the line width
const TEX_DASH = Makie.Linestyle([0.0, 1.9, 2.9])

# ---- F4 ---------------------------------------------------------------------------------

# the (site of c, partner) Moore(1) pairs of cell c, split by partner: medium or another cell
function _pairs(σ, c)
    medium = Tuple{CartesianIndex{2}, CartesianIndex{2}}[]
    cell = Tuple{CartesianIndex{2}, CartesianIndex{2}}[]
    for s in CartesianIndices(σ)
        σ[s] == c || continue
        for d in CartesianIndices((-1:1, -1:1))
            d == CartesianIndex(0, 0) && continue
            t = s + d
            checkbounds(Bool, σ, t) || continue
            σ[t] == c && continue
            push!(σ[t] == 0 ? medium : cell, (s, t))
        end
    end
    return medium, cell
end

# one dash per pair, centred on the shared edge midpoint (axis pair) or corner (diagonal
# pair) and pointing from one site centre to the other, `len` lattice spacings long
function _dashes(pairs, g; len = 0.5)
    pts = Makie.Point2f[]
    for (s, t) in pairs
        a = g.origin .+ (Tuple(s) .- 0.5) .* g.spacing
        b = g.origin .+ (Tuple(t) .- 0.5) .* g.spacing
        mid = (a .+ b) ./ 2
        v = b .- a
        h = (len / 2) .* v ./ hypot((v ./ g.spacing)...)
        push!(pts, Makie.Point2f(mid .- h), Makie.Point2f(mid .+ h))
    end
    return pts
end

function PottsModels.openvt_f4_figure(σ::AbstractMatrix{<:Integer}, c::Integer)
    any(<(0), σ) && throw(ArgumentError("openvt_f4_figure: σ holds cell ids (> 0) and medium (0)"))
    any(==(c), σ) || throw(ArgumentError("openvt_f4_figure: cell $c has no site in σ"))
    owners = [x == 0 ? RenderOwner(MediumSite, 1) : RenderOwner(CellSite, x) for x in σ]
    ids = sort!(unique!(filter(>(0), vec(Int.(σ)))))
    cells = [RenderCellMetadata(RenderCellIdentity(id, 0), 1) for id in ids]
    frame = PottsRenderFrame(0, owners, cells)
    g = frame_geometry(frame)
    lo = g.origin
    hi = g.origin .+ g.size .* g.spacing
    medium, cell = _pairs(σ, c)
    m, n = length(medium), length(cell)

    fig = Makie.Figure(; size = (420, 470), backgroundcolor = :white)
    ax = Makie.Axis(fig[1, 1]; title = "Lattice models", aspect = Makie.DataAspect(), titlefont = :bold,
        titlesize = 18, spinewidth = 1.5)
    Makie.hidedecorations!(ax)
    palette = ids == 1:length(ids) && length(ids) <= length(TEX_CELLS) ? TEX_CELLS[1:length(ids)] : Makie.automatic
    pottsplot!(ax, frame; encoding = CellIdentityEncoding(), medium_color = MEDIUM_F4, category_palette = palette,
        boundaries = false)
    # the .tex's white site grid: full-length lattice lines only (no partial cell boundaries)
    grid = Makie.Point2f[]
    for k in 0:g.size[1]
        x = lo[1] + k * g.spacing[1]
        push!(grid, Makie.Point2f(x, lo[2]), Makie.Point2f(x, hi[2]))
    end
    for k in 0:g.size[2]
        y = lo[2] + k * g.spacing[2]
        push!(grid, Makie.Point2f(lo[1], y), Makie.Point2f(hi[1], y))
    end
    Makie.linesegments!(ax, grid; color = :white, linewidth = 1.5)
    isempty(medium) || Makie.linesegments!(ax, _dashes(medium, g); color = MEDIUM_PAIR, linewidth = 3.5, linestyle = TEX_DASH)
    isempty(cell) || Makie.linesegments!(ax, _dashes(cell, g); color = CELL_PAIR, linewidth = 3.5, linestyle = TEX_DASH)
    Makie.limits!(ax, lo[1], hi[1], lo[2], hi[2])
    f = m + n == 0 ? NaN : m / (m + n)
    Makie.Label(fig[2, 1], "fᵢ = $m / ($m + $n) = $(round(f; digits = 3))"; fontsize = 18, tellwidth = false)
    return fig
end

# ---- F1 ---------------------------------------------------------------------------------

_owner_id(frame, I) = (o = owner_at(frame, I); o.kind === CellSite ? Int(o.id) : 0)

# the window × window block (offsets) centred where the 45° ray from the colony centroid
# leaves the colony (the last cell site on it)
function _rim_window(frame, window)
    sz = frame_size(frame)
    all(>=(window), sz) || throw(ArgumentError("openvt_f1_figure: window $window exceeds the frame $(sz)"))
    sx = 0.0; sy = 0.0; k = 0
    for I in CartesianIndices(sz)
        _owner_id(frame, I) > 0 || continue
        sx += I[1]; sy += I[2]; k += 1
    end
    k == 0 && throw(ArgumentError("openvt_f1_figure: the frame holds no cell"))
    c = (sx / k, sy / k)
    d = (1, 1) ./ sqrt(2)
    t = 0.0
    for τ in 0:0.25:maximum(sz)
        I = round.(Int, c .+ τ .* d)
        all(1 .<= I .<= sz) || break
        _owner_id(frame, CartesianIndex(I)) > 0 && (t = τ)
    end
    centre = c .+ t .* d
    return clamp.(round.(Int, centre .- (window + 1) / 2), 0, sz .- window)
end

# the block as its own frame: same owners, metadata and site positions
function _crop(frame, off, window)
    g = frame_geometry(frame)
    sites = CartesianIndices((off[1] .+ (1:window), off[2] .+ (1:window)))
    owners = [owner_at(frame, I) for I in sites]
    ids = sort!(unique!([o.id for o in owners if o.kind === CellSite]))
    cells = RenderCellMetadata[cell_metadata(frame, RenderOwner(CellSite, id)) for id in ids]
    geometry = RenderGeometry((window, window); spacing = g.spacing, origin = g.origin .+ off .* g.spacing,
        source_axes = g.source_axes)
    return PottsRenderFrame(frame_mcs(frame), owners, cells; geometry)
end

function PottsModels.openvt_f1_figure(frame; window::Integer = 64, banner::Bool = true)
    length(frame_size(frame)) == 2 || throw(ArgumentError("openvt_f1_figure: a 2D frame is required"))
    window > 0 || throw(ArgumentError("openvt_f1_figure: window must be positive"))
    crop = _crop(frame, _rim_window(frame, window), window)
    g = frame_geometry(crop)
    # M's layout in mm (introduction.tex): a 45 mm panel, a 5 mm banner 1 mm above it; 10 px/mm
    P = 450
    height = banner ? P + P * 6 ÷ 45 + 20 : P + 20
    fig = Makie.Figure(; size = (P + 20, height), figure_padding = 10, backgroundcolor = :white)
    if banner
        Makie.Box(fig[1, 1]; width = P, height = P * 5 / 45, color = POTTS_COLOUR, strokevisible = false)
        Makie.Label(fig[1, 1], "Potts.jl"; color = :white, font = :bold, fontsize = 30, tellwidth = false,
            tellheight = false)
    end
    ax = Makie.Axis(fig[banner ? 2 : 1, 1]; width = P, height = P, backgroundcolor = :white)
    Makie.hidedecorations!(ax)
    Makie.hidespines!(ax)
    pottsplot!(ax, crop; encoding = CellIdentityEncoding(), medium_color = :white, boundaries = false)
    Makie.limits!(ax, g.origin[1], g.origin[1] + window * g.spacing[1], g.origin[2], g.origin[2] + window * g.spacing[2])
    banner && Makie.rowgap!(fig.layout, 1, P / 45)
    return fig
end

end
