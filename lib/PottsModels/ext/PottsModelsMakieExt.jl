# The OpenVT monolayer figure functions: `PottsModels.openvt_f4_figure` (M Fig 4, the
# free-surface schematic; D-175), `PottsModels.openvt_f1_figure` (M Fig 1, the Potts.jl panel
# and banner) and `PottsModels.openvt_colony_panel!` (the consortium style for colony
# snapshots, D-185). Loaded with Makie and MakiePotts. F4 is one `pottsplot` with
# `boundaries = false`, plus full-length lattice lines and the pair dashes (D-156). The
# consortium figures (F1, F7 and F8 snapshots) follow the other frameworks' panels (D-185):
# cells coloured by area (`coolwarm`, the panel's own min–max) or by state (growing or
# inhibited), with thin black pixel-edge boundaries between unlike ids.
module PottsModelsMakieExt

using PottsModels: PottsModels
using Makie: Makie
using MakiePotts: MakiePotts, CellChannelKey, CellIdentityEncoding, CellSite, ChannelEncoding, MediumSite,
    PottsRenderFrame, RenderCellIdentity, RenderCellMetadata, RenderChannel, RenderGeometry, RenderOwner,
    cell_metadata, frame_geometry, frame_mcs, frame_size, owner_at, pottsplot!

_rgb(r, g, b) = Makie.RGBf(r / 255, g / 255, b / 255)
const MEDIUM_PAIR = _rgb(231, 41, 138)       # free_surface.tex `m`
const CELL_PAIR = _rgb(255, 192, 0)          # free_surface.tex `c`
const MEDIUM_F4 = _rgb(236, 236, 236)        # free_surface.tex `ma!10`
const POTTS_COLOUR = _rgb(8, 29, 88)         # spec §4.0.2, Q18 proposal
# growing and inhibited cells in M's Fig 7 (the TST row, G:results/TST/TST_10k_snapshots.pdf,
# ColorBrewer RdYlBu): blue for growing cells, orange for (type 2) inhibited ones; spec §4.0.2 F7
const GROWING = _rgb(44, 123, 182)
const INHIBITED = _rgb(253, 174, 97)
const OUTLINE_WIDTH = 0.75                   # px at the figure's own scale: a thin line
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

# ---- consortium style (D-185) ------------------------------------------------------------

_owner_id(frame, I) = (o = owner_at(frame, I); o.kind === CellSite ? Int(o.id) : 0)

# the pixel edges between sites of unlike owners (cell–cell and cell–medium), as segment
# end points in data coordinates: every such edge once, nothing else
function _edges(frame)
    g = frame_geometry(frame)
    nx, ny = frame_size(frame)
    dx, dy = g.spacing
    ox, oy = g.origin
    pts = Makie.Point2f[]
    for j in 1:ny, i in 1:(nx - 1)
        owner_at(frame, CartesianIndex(i, j)) == owner_at(frame, CartesianIndex(i + 1, j)) && continue
        x = ox + i * dx
        push!(pts, Makie.Point2f(x, oy + (j - 1) * dy), Makie.Point2f(x, oy + j * dy))
    end
    for j in 1:(ny - 1), i in 1:nx
        owner_at(frame, CartesianIndex(i, j)) == owner_at(frame, CartesianIndex(i, j + 1)) && continue
        y = oy + j * dy
        push!(pts, Makie.Point2f(ox + (i - 1) * dx, y), Makie.Point2f(ox + i * dx, y))
    end
    return pts
end

# the frame with one cell channel added (same owners, cells, geometry and MCS)
function _with_channel(frame, name, values::AbstractDict)
    ids = Set{Int}()
    for I in CartesianIndices(frame_size(frame))
        o = owner_at(frame, I)
        o.kind === CellSite && push!(ids, Int(o.id))
    end
    cells = RenderCellMetadata[cell_metadata(frame, RenderOwner(CellSite, id)) for id in sort!(collect(ids))]
    owners = [owner_at(frame, I) for I in CartesianIndices(frame_size(frame))]
    vals = Dict{RenderCellIdentity, Float64}()
    for c in cells
        id = Int(c.identity.id)
        haskey(values, id) || throw(ArgumentError("openvt_colony_panel!: no $name for cell $id"))
        vals[c.identity] = Float64(values[id])
    end
    key = CellChannelKey(name, Float64)
    return PottsRenderFrame(frame_mcs(frame), owners, cells; geometry = frame_geometry(frame),
        channels = (RenderChannel(key, vals; label = string(name)),)), key, vals
end

# every cell's site count in a frame (its area when the frame is the whole lattice)
function _site_counts(frame)
    n = Dict{Int, Int}()
    for I in CartesianIndices(frame_size(frame))
        id = _owner_id(frame, I)
        id > 0 && (n[id] = get(n, id, 0) + 1)
    end
    return n
end

function PottsModels.openvt_colony_panel!(ax, frame; colour::Symbol = :area, areas = nothing, inhibited = nothing,
        colorrange = nothing, linewidth::Real = OUTLINE_WIDTH)
    length(frame_size(frame)) == 2 || throw(ArgumentError("openvt_colony_panel!: a 2D frame is required"))
    if colour === :area
        a = areas === nothing ? _site_counts(frame) : areas
        fr, key, vals = _with_channel(frame, :area, a)
        if colorrange === nothing
            isempty(vals) && throw(ArgumentError("openvt_colony_panel!: the frame holds no cell"))
            lo, hi = extrema(values(vals))
            colorrange = lo == hi ? (lo - 0.5, hi + 0.5) : (lo, hi)
        end
        pp = pottsplot!(ax, fr; encoding = ChannelEncoding(key; label = "cell area"), colormap = :coolwarm,
            colorrange, medium_color = :white, boundaries = false)
    elseif colour === :state
        inhibited === nothing && throw(ArgumentError("openvt_colony_panel!: colour = :state needs `inhibited`"))
        fr, key, _ = _with_channel(frame, :inhibited, Dict(id => (v == true || v == 1) ? 1.0 : 0.0 for (id, v) in inhibited))
        pp = pottsplot!(ax, fr; encoding = ChannelEncoding(key; label = "inhibited"),
            colormap = Makie.cgrad([GROWING, INHIBITED], 2; categorical = true), colorrange = (0.0, 1.0),
            medium_color = :white, boundaries = false)
    else
        throw(ArgumentError("openvt_colony_panel!: colour is :area or :state, got :$colour"))
    end
    Makie.linesegments!(ax, _edges(fr); color = :black, linewidth, linecap = :square)
    return pp
end

# ---- F1 ---------------------------------------------------------------------------------

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

function PottsModels.openvt_f1_figure(frame; window::Integer = 64, banner::Bool = true, areas = nothing)
    length(frame_size(frame)) == 2 || throw(ArgumentError("openvt_f1_figure: a 2D frame is required"))
    window > 0 || throw(ArgumentError("openvt_f1_figure: window must be positive"))
    # areas from the whole frame, so cells cut by the window keep their full area
    a = areas === nothing ? _site_counts(frame) : areas
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
    PottsModels.openvt_colony_panel!(ax, crop; colour = :area, areas = a)
    Makie.limits!(ax, g.origin[1], g.origin[1] + window * g.spacing[1], g.origin[2], g.origin[2] + window * g.spacing[2])
    banner && Makie.rowgap!(fig.layout, 1, P / 45)
    return fig
end

end
