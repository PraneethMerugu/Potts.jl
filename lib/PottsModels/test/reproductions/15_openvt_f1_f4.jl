# P6.15h (ROADMAP Step 3b): the OpenVT monolayer benchmark's Fig 1 (the Potts.jl panel and
# banner) and Fig 4 (the free-surface schematic, lattice panel), with the unit test that G1
# equals the drawn count. Frozen (AUTONOMY §7.3). Sources: spec 15 v3.2
# (docs/design/research/model-specs/15_openvt_monolayer.md) §2.4 (f_i, G1), §4.0 (F1, F4),
# §4.0.2 (colours, F1), §6 G1, and the consortium figure sources G:results/introduction.tex,
# G:results/free_surface.tex and G:results/colors.tex at 54f375f (read on the PC; no G file
# is copied here, the F4 configuration and dashes below are a transcription).
#
# ---------------------------------------------------------------------------------------------
# F4 (M Fig 4, lattice panel; G:results/free_surface.tex:31-110)
# ---------------------------------------------------------------------------------------------
# The drawing is a 7 × 7 crop of a square lattice: medium (13 sites), cell i (12), cell i−1
# (7), cell i+1 (9), cell i+2 (8). Tikz pixel (x, y), x, y ∈ 0:6, spans [x, x+1] × [y, y+1];
# here σ[x + 1, y + 1] holds it and cell i = 1, i−1 = 2, i+1 = 3, i+2 = 4 (the P6.15c
# convention). Every (site of cell i, Moore(1) neighbour of another owner) pair is drawn as a
# short dashed segment across the pair's shared edge (axis neighbours) or corner (diagonal
# neighbours), along the pair's direction: magenta m = RGB(231,41,138) for medium partners,
# amber c = RGB(255,192,0) for other cells. The .tex draws 13 magenta and 25 amber dashes,
# exactly the Moore pair counts, so f_i = 13 / (13 + 25) = 13/38 (TST "method 3", spec §2.4).
# (A commented-out older caption reads 11/(11 + 29); the drawn dashes are 13 and 25.)
#
# The Potts deliverable `PottsModels.openvt_f4_figure(σ, c) -> Makie.Figure`:
# - one Axis (title text "Lattice models") holding one `pottsplot` of σ (frame owners equal
#   σ: id > 0 a cell, 0 medium), `encoding = CellIdentityEncoding()`, medium light grey
#   = the .tex `ma!10` = RGB(236,236,236), `boundaries = false`;
# - one dash per pair of cell c, as a `lines`/`linesegments` segment in the pottsplot's data
#   coordinates, centred on the shared edge midpoint or corner and pointing from one site
#   centre towards the other, of length 0.2–1.0 lattice spacings, coloured m or c;
# - a text that shows both counts (e.g. "f_i = 13 / (13 + 25)");
# - no cell outlines (D-156): the only other line segments allowed are full-length lattice
#   lines (a uniform site grid like the .tex's white grid, or the panel frame). The .tex's
#   black outline of cell i and its partial cell boundaries are left out on purpose.
#
# G1 (spec §6) is the per-cell medium/unlike Moore(1) pair count. The F5 analysis (frozen
# `15_openvt_f5.jl`) reads it through `PottsModels.openvt_snapshot(u).f`; P6.15c already
# checks the in-model contact fold against M's Fig 4 (13/38). Here the figure's marks are
# decoded back to pairs and must equal (i) the transcribed .tex dashes (the hand count),
# (ii) a brute-force pair oracle and (iii) `openvt_snapshot`'s f, for every cell of the
# configuration (cells 2–4 touch the crop's closed edge).
#
# ---------------------------------------------------------------------------------------------
# F1 (M Fig 1; G:results/introduction.tex:52-92)
# ---------------------------------------------------------------------------------------------
# One 45 × 45 mm closeup per framework with a 45 × 5 mm banner 1 mm above it, filled in the
# framework colour, the name centred in white bold. The closeups show the colony's
# upper-right rim (colony lower left, medium upper right) on a white background.
# The Potts deliverable `PottsModels.openvt_f1_figure(frame; window = 64) -> Makie.Figure`,
# where `frame` is a 2D MakiePotts render frame (in use: `renderframe(sol)` of the final state
# of case (a), D-175):
# - the panel (re-frozen under D-185, which amends D-156/D-172/D-175 for the consortium
#   figures): one Axis holding one `pottsplot` that colours each cell by its area with
#   `coolwarm` (a cell `ChannelEncoding`), scaled to the min–max of the areas of the cells in
#   the panel, on a white medium. The areas are those of the whole frame (or the `areas`
#   keyword), so a cell cut by the window keeps its full area. Thin black boundaries are
#   drawn along exactly the pixel edges between unlike ids (cell–cell and cell–medium) inside
#   the block, each once, with no gaps and no other line or stroked polygon. It shows a
#   window × window block of the frame's sites, unchanged (same owners, same cell
#   identities and generations), centred on the colony rim along the 45° diagonal from the
#   colony centroid (the "top-right quadrant crop" of spec §4.0.2 F1). 64 sites ≈ 8 cell
#   diameters (2R = 7.98 px), what the TST closeup shows;
# - the banner: a `Makie.Box` filled with RGB(8,29,88) (Q18 proposal, spec §4.0.2), as wide
#   as the panel, 5/45 of the panel high, 1/45 of the panel above it; a `Makie.Label`
#   "Potts.jl" in white bold centred on it. The panel is square.
#
# The colour-scale limits (the panel's own min–max) are a provisional reading (D-185): the
# consortium does not state its closeups' limits.
#
# Tiers: one, always, light (CairoMakie load plus small figures; no simulation). The
# detector controls build figures with MakiePotts directly, so a broken detector cannot pass
# a bad figure.
using Potts, PottsModels, Test

const P615H_MAKIE = try
    @eval using CairoMakie, MakiePotts
    @eval using CairoMakie: Makie
    true
catch err
    @warn "P6.15h: CairoMakie and MakiePotts must be in the test environment" exception = err
    false
end

const P615H_M = (231, 41, 138)        # free_surface.tex `m`: medium pairs
const P615H_C = (255, 192, 0)         # free_surface.tex `c`: cell pairs
const P615H_MEDIUM_F4 = (236, 236, 236)   # free_surface.tex `ma!10` (ma = 64,64,64)
const P615H_POTTS = (8, 29, 88)       # spec §4.0.2, Q18
const P615H_WINDOW = 64

# ---------------------------------------------------------------------------------------------
# F4 configuration and the .tex dashes (transcribed)
# ---------------------------------------------------------------------------------------------

function p615h_fig4()
    σ = zeros(Int32, 7, 7)
    cells = (
        [(3, 1), (2, 2), (3, 2), (4, 2), (2, 3), (3, 3), (4, 3), (5, 3), (2, 4), (3, 4), (4, 4), (3, 5)],   # i
        [(0, 0), (1, 0), (2, 0), (3, 0), (0, 1), (1, 1), (2, 1)],                                           # i−1
        [(4, 0), (5, 0), (6, 0), (4, 1), (5, 1), (6, 1), (5, 2), (6, 2), (6, 3)],                           # i+1
        [(4, 6), (5, 6), (6, 6), (4, 5), (5, 5), (6, 5), (5, 4), (6, 4)],                                   # i+2
    )
    for (c, px) in enumerate(cells), (x, y) in px
        σ[x + 1, y + 1] = c
    end
    return σ
end

# dashes of free_surface.tex:48-98 as (centre, direction): :h `(-\L,0) -- ++(2\L,0)`,
# :v `(0,-\L) -- ++(0,2\L)`, :d `(45:\L) -- ++(-135:2\L)` (along (1,1)), :a
# `(-45:\L) -- ++(135:2\L)` (along (-1,1))
const P615H_TEX_M = [
    ((2, 2.5), :h), ((2, 3.5), :h), ((2, 4.5), :h), ((3, 5.5), :h),
    ((2.5, 5), :v), ((3.5, 6), :v),
    ((2, 3), :a), ((2, 4), :d), ((2, 5), :a), ((3, 6), :a),
    ((2, 3), :d), ((2, 4), :a), ((3, 5), :a),
]
const P615H_TEX_C = [
    ((4, 5.5), :h), ((5, 4.5), :h), ((6, 3.5), :h),
    ((5, 2.5), :h), ((4, 1.5), :h),
    ((3, 1.5), :h),
    ((4.5, 5), :v), ((5.5, 4), :v),
    ((5.5, 3), :v), ((4.5, 2), :v), ((3.5, 1), :v),
    ((2.5, 2), :v),
    ((4, 6), :d), ((5, 5), :d), ((6, 4), :d),
    ((4, 5), :d), ((5, 4), :d),
    ((3, 2), :d),
    ((3, 1), :d), ((2, 2), :d),
    ((6, 3), :a), ((5, 2), :a), ((4, 1), :a),
    ((5, 3), :a), ((4, 2), :a),
]
const P615H_DIR = Dict(:h => (1, 0), :v => (0, 1), :d => (1, 1), :a => (-1, 1))

# a pair as (site of cell c, partner site), from a dash centre (tikz units) and its direction
function p615h_tex_pair(σ, c, (centre, dir))
    o = P615H_DIR[dir]
    a = CartesianIndex(round(Int, centre[1] - o[1] / 2 + 0.5), round(Int, centre[2] - o[2] / 2 + 0.5))
    b = CartesianIndex(round(Int, centre[1] + o[1] / 2 + 0.5), round(Int, centre[2] + o[2] / 2 + 0.5))
    return σ[a] == c ? (a, b) : (b, a)
end

# brute force: every (site of c, in-bounds Moore(1) neighbour not of c) pair
function p615h_pairs(σ, c)
    med = Tuple{CartesianIndex{2}, CartesianIndex{2}}[]
    cel = Tuple{CartesianIndex{2}, CartesianIndex{2}}[]
    for s in CartesianIndices(σ)
        σ[s] == c || continue
        for d in CartesianIndices((-1:1, -1:1))
            d == CartesianIndex(0, 0) && continue
            t = s + d
            checkbounds(Bool, σ, t) || continue
            σ[t] == c && continue
            push!(σ[t] == 0 ? med : cel, (s, t))
        end
    end
    return (; med, cel)
end

# the duck-typed saved state `openvt_snapshot` takes (as in the frozen 15_openvt_f3_f8.jl)
function p615h_state(σ)
    n = Int(maximum(σ))
    vol = Float64[count(==(c), σ) for c in 1:n]
    return (; σ, cell = (; volume = vol, A_star = fill(50.0, n)))
end

# ---------------------------------------------------------------------------------------------
# Figure inspection
# ---------------------------------------------------------------------------------------------

p615h_rgb(t) = Makie.RGBf((t ./ 255)...)
function p615h_close(a, b; tol = 1.5 / 255)
    x = try Makie.RGBAf(Makie.to_color(a)) catch; return false end
    y = Makie.RGBAf(Makie.to_color(b))
    return abs(x.r - y.r) <= tol && abs(x.g - y.g) <= tol && abs(x.b - y.b) <= tol
end

# every visible plot under a scene (an invisible plot hides its children)
function p615h_plots(scene; out = Any[])
    for p in scene.plots
        p615h_walk(p, out)
    end
    for s in scene.children
        p615h_plots(s; out)
    end
    return out
end
function p615h_walk(p, out)
    v = try p.visible[] catch; true end
    v === false && return out
    push!(out, p)
    for q in p.plots
        p615h_walk(q, out)
    end
    return out
end

p615h_pottsplots(scene) = [p for p in p615h_plots(scene) if p isa MakiePotts.PottsPlot]
p615h_axes(fig) = [b for b in fig.content if b isa Makie.Axis]
function p615h_panel(fig)
    axs = [ax for ax in p615h_axes(fig) if !isempty(p615h_pottsplots(ax.scene))]
    return length(axs) == 1 ? only(axs) : nothing
end

p615h_owners(frame) = [(o = owner_at(frame, I); o.kind === CellSite ? Int(o.id) : 0) for I in CartesianIndices(frame_size(frame))]

# (a, b, colour) for each segment of the visible lines / linesegments plots under `scene`
function p615h_segments(scene)
    segs = Tuple{NTuple{2, Float64}, NTuple{2, Float64}, Any}[]
    for p in p615h_plots(scene)
        (p isa Makie.Lines || p isa Makie.LineSegments) || continue
        pts = [(Float64(q[1]), Float64(q[2])) for q in p[1][]]
        col = p.color[]
        colour(k) = col isa AbstractVector ? (k <= length(col) ? col[k] : nothing) : col
        if p isa Makie.LineSegments
            for k in 1:2:(length(pts) - 1)
                push!(segs, (pts[k], pts[k + 1], colour(k)))
            end
        else
            for k in 1:(length(pts) - 1)
                (any(isnan, pts[k]) || any(isnan, pts[k + 1])) && continue
                push!(segs, (pts[k], pts[k + 1], colour(k)))
            end
        end
    end
    return segs
end

# stroked polygons under `scene` (outlines), except the full-extent rectangle (a panel frame)
function p615h_stroked(scene, geom)
    n = 0
    for p in p615h_plots(scene)
        p isa Makie.Poly || continue
        sw = try maximum(p.strokewidth[]) catch; 0.0 end
        sc = try Makie.RGBAf(Makie.to_color(p.strokecolor[])) catch; Makie.RGBAf(0, 0, 0, 1) end
        (sw > 0 && sc.alpha > 0) || continue
        g = p[1][]
        full = g isa Makie.Rect && all(isapprox.(Tuple(minimum(g))[1:2], geom.origin; atol = 1e-3)) &&
               all(isapprox.(Tuple(maximum(g))[1:2], geom.origin .+ geom.size .* geom.spacing; atol = 1e-3))
        full || (n += 1)
    end
    return n
end

# a lattice line across the whole frame (site grid or frame), in data coordinates
function p615h_fullspan((a, b, _), geom)
    lo = geom.origin
    hi = geom.origin .+ geom.size .* geom.spacing
    tol = 1e-3 * minimum(geom.spacing)
    online(v, k) = (r = (v - lo[k]) / geom.spacing[k]; abs(r - round(r)) * geom.spacing[k] <= tol)
    if abs(a[2] - b[2]) <= tol      # horizontal
        return online(a[2], 2) && isapprox(min(a[1], b[1]), lo[1]; atol = tol) && isapprox(max(a[1], b[1]), hi[1]; atol = tol)
    elseif abs(a[1] - b[1]) <= tol  # vertical
        return online(a[1], 1) && isapprox(min(a[2], b[2]), lo[2]; atol = tol) && isapprox(max(a[2], b[2]), hi[2]; atol = tol)
    end
    return false
end

p615h_marker_colour(col) = col !== nothing && (p615h_close(col, p615h_rgb(P615H_M)) || p615h_close(col, p615h_rgb(P615H_C)))

# decode the pair marks of cell c: (; medium, cell, bad, outline) where `bad` counts marks
# that are not one pair of c in the right colour and `outline` counts every other segment
# that is not a full-length lattice line
function p615h_marks(scene, geom, σ, c)
    medium = Tuple{CartesianIndex{2}, CartesianIndex{2}}[]
    cell = Tuple{CartesianIndex{2}, CartesianIndex{2}}[]
    bad = 0
    outline = 0
    for seg in p615h_segments(scene)
        a, b, col = seg
        A = (a .- geom.origin) ./ geom.spacing
        B = (b .- geom.origin) ./ geom.spacing
        v = B .- A
        len = hypot(v...)
        if !(p615h_marker_colour(col) && 0.2 <= len <= 1.0)
            p615h_fullspan(seg, geom) || (outline += 1)
            continue
        end
        mid = (A .+ B) ./ 2
        o = map(x -> abs(x) / len > 0.38 ? Int(sign(x)) : 0, v)
        s1 = mid .- o ./ 2
        s2 = mid .+ o ./ 2
        centred(s) = all(x -> abs(x - (round(x - 0.5) + 0.5)) < 0.15, s)
        if o == (0, 0) || !centred(s1) || !centred(s2)
            bad += 1
            continue
        end
        I1 = CartesianIndex(round(Int, s1[1] + 0.5), round(Int, s1[2] + 0.5))
        I2 = CartesianIndex(round(Int, s2[1] + 0.5), round(Int, s2[2] + 0.5))
        if !(checkbounds(Bool, σ, I1) && checkbounds(Bool, σ, I2)) || ((σ[I1] == c) == (σ[I2] == c))
            bad += 1
            continue
        end
        s, t = σ[I1] == c ? (I1, I2) : (I2, I1)
        if σ[t] == 0 && p615h_close(col, p615h_rgb(P615H_M))
            push!(medium, (s, t))
        elseif σ[t] != 0 && p615h_close(col, p615h_rgb(P615H_C))
            push!(cell, (s, t))
        else
            bad += 1
        end
    end
    return (; medium, cell, bad, outline)
end

function p615h_texts(fig)
    out = String[]
    for p in p615h_plots(fig.scene)
        p isa Makie.Text || continue
        t = try p.text[] catch; nothing end
        t === nothing && continue
        t isa AbstractVector ? append!(out, string.(t)) : push!(out, string(t))
    end
    return out
end

# outline violations of a panel: visible boundary overlays, `boundaries = true`, stroked
# polygons and (with `markers = false`) any line segment at all, else any non-mark segment
# that is not a full-length lattice line
function p615h_outlines(ax, σ, c; markers)
    pp = only(p615h_pottsplots(ax.scene))
    geom = frame_geometry(pp.frame[])
    n = count(p -> p isa MakiePotts.PottsBoundaries, p615h_plots(ax.scene))
    n += count(p -> p.boundaries[] === true, p615h_pottsplots(ax.scene))
    n += p615h_stroked(ax.scene, geom)
    n += markers ? p615h_marks(ax.scene, geom, σ, c).outline : length(p615h_segments(ax.scene))
    return n
end

# a hand-made F4-like figure for the detector controls
function p615h_control_figure(σ; boundaries = false, overlay = false, outline_lines = false, marks = true)
    owners = [x == 0 ? RenderOwner(MediumSite, 1) : RenderOwner(CellSite, x) for x in σ]
    cells = [RenderCellMetadata(RenderCellIdentity(c, 0), 1) for c in 1:Int(maximum(σ))]
    frame = PottsRenderFrame(0, owners, cells)
    fig = Makie.Figure(; size = (300, 300))
    ax = Makie.Axis(fig[1, 1]; aspect = Makie.DataAspect())
    pottsplot!(ax, frame; encoding = CellIdentityEncoding(), boundaries)
    overlay && pottsboundaries!(ax, frame)
    if marks
        pr = p615h_pairs(σ, 1)
        for (list, col) in ((pr.med, P615H_M), (pr.cel, P615H_C))
            pts = Makie.Point2f[]
            for (s, t) in list
                cs = (s[1] - 0.5, s[2] - 0.5); ct = (t[1] - 0.5, t[2] - 0.5)
                mid = (cs .+ ct) ./ 2; d = (ct .- cs) ./ hypot((ct .- cs)...)
                push!(pts, Makie.Point2f(mid .- 0.25 .* d), Makie.Point2f(mid .+ 0.25 .* d))
            end
            Makie.linesegments!(ax, pts; color = p615h_rgb(col))
        end
    end
    grid = Makie.Point2f[]
    for k in 0:7
        append!(grid, (Makie.Point2f(k, 0), Makie.Point2f(k, 7), Makie.Point2f(0, k), Makie.Point2f(7, k)))
    end
    Makie.linesegments!(ax, grid; color = :white)                       # a uniform site grid
    outline_lines && Makie.lines!(ax, [Makie.Point2f(2, 2), Makie.Point2f(5, 2), Makie.Point2f(5, 3)]; color = :black)
    return fig, ax
end

# ---------------------------------------------------------------------------------------------
# F1 fixture: a disc colony of 6 × 6 block cells, generations id mod 4
# ---------------------------------------------------------------------------------------------

function p615h_colony(; L = 200, radius = 80)
    σ = zeros(Int, L, L)
    c = (L + 1) / 2
    nb = cld(L, 6)
    for I in CartesianIndices(σ)
        hypot(I[1] - c, I[2] - c) <= radius || continue
        σ[I] = (fld(I[1] - 1, 6)) * nb + fld(I[2] - 1, 6) + 1
    end
    ids = sort!(unique(filter(>(0), vec(σ))))
    owners = [x == 0 ? RenderOwner(MediumSite, 1) : RenderOwner(CellSite, x) for x in σ]
    cells = [RenderCellMetadata(RenderCellIdentity(id, id % 4), 1) for id in ids]
    return σ, PottsRenderFrame(1234, owners, cells)
end

# the visible W × W block of the panel: (owners, the plotted frame, its sites)
function p615h_visible(ax)
    pp = only(p615h_pottsplots(ax.scene))
    fr = pp.frame[]
    g = frame_geometry(fr)
    lim = ax.finallimits[]
    lo, hi = Tuple(minimum(lim)), Tuple(maximum(lim))
    keep(k, i) = (x = g.origin[k] + (i - 0.5) * g.spacing[k]; lo[k] < x < hi[k])
    xs = [i for i in 1:frame_size(fr)[1] if keep(1, i)]
    ys = [j for j in 1:frame_size(fr)[2] if keep(2, j)]
    return p615h_owners(fr)[xs, ys], fr, (xs, ys)
end

function p615h_find(σ, w)
    W1, W2 = size(w)
    for oy in 0:(size(σ, 2) - W2), ox in 0:(size(σ, 1) - W1)
        @views σ[ox .+ (1:W1), oy .+ (1:W2)] == w && return (ox, oy)
    end
    return nothing
end

function p615h_rim(σ)
    sites = [Tuple(I) for I in CartesianIndices(σ) if σ[I] > 0]
    c = (sum(first, sites) / length(sites), sum(last, sites) / length(sites))
    d = (1, 1) ./ sqrt(2)
    t = 0.0
    for τ in 0:0.25:maximum(size(σ))
        I = round.(Int, c .+ τ .* d)
        all(1 .<= I .<= size(σ)) || break
        σ[I...] > 0 && (t = τ)
    end
    return c, t
end

function p615h_bbox(b)
    r = b.layoutobservables.computedbbox[]
    return (; x = Float64(minimum(r)[1]), y = Float64(minimum(r)[2]), w = Float64(Makie.widths(r)[1]), h = Float64(Makie.widths(r)[2]))
end

# the pixel edges between unlike owners of a block `w` whose site (i, j) spans
# [ox + i − 1, ox + i] × [oy + j − 1, oy + j]: the set of (endpoint, endpoint), rounded
function p615h_edge_oracle(w, (ox, oy))
    E = Set{NTuple{2, NTuple{2, Int}}}()
    W1, W2 = size(w)
    for j in 1:W2, i in 1:(W1 - 1)
        w[i, j] == w[i + 1, j] || push!(E, ((ox + i, oy + j - 1), (ox + i, oy + j)))
    end
    for j in 1:(W2 - 1), i in 1:W1
        w[i, j] == w[i, j + 1] || push!(E, ((ox + i - 1, oy + j), (ox + i, oy + j)))
    end
    return E
end
# the panel's line segments as the same kind of set (one unit edge each), plus a count of the
# segments that are not one black unit lattice edge
function p615h_edge_marks(scene)
    E = NTuple{2, NTuple{2, Int}}[]
    other = 0
    for (a, b, col) in p615h_segments(scene)
        ra = round.(Int, a); rb = round.(Int, b)
        ok = col !== nothing && p615h_close(col, Makie.RGBf(0, 0, 0)) && all(abs.(a .- ra) .< 1e-3) &&
             all(abs.(b .- rb) .< 1e-3) && sum(abs.(ra .- rb)) == 1
        ok ? push!(E, ra < rb ? (ra, rb) : (rb, ra)) : (other += 1)
    end
    return E, other
end
# line widths of the visible line plots under a scene
p615h_linewidths(scene) = [Float64(maximum(p.linewidth[])) for p in p615h_plots(scene) if p isa Makie.Lines || p isa Makie.LineSegments]

# the panel's heatmap values (NaN off cells), as the pottsplot draws them
function p615h_values(ax)
    hm = [p for p in p615h_plots(ax.scene) if p isa Makie.Heatmap]
    length(hm) == 1 || return nothing
    return Float64.(only(hm)[3][])
end

# ---------------------------------------------------------------------------------------------
# (a) G1: the F5 analysis count equals the drawn count and the hand count
# ---------------------------------------------------------------------------------------------

@testset "P6.15h (a) G1 oracle: the .tex dashes are the Moore pair count (f_i = 13/38)" begin
    σ = p615h_fig4()
    @test [count(==(c), σ) for c in 0:4] == [13, 12, 7, 9, 8]
    pr = p615h_pairs(σ, 1)
    tm = [p615h_tex_pair(σ, 1, d) for d in P615H_TEX_M]
    tc = [p615h_tex_pair(σ, 1, d) for d in P615H_TEX_C]
    @test length(tm) == 13 == length(unique(tm)) && length(tc) == 25 == length(unique(tc))
    @test all(((s, t),) -> σ[s] == 1 && σ[t] == 0, tm) && all(((s, t),) -> σ[s] == 1 && σ[t] ∉ (0, 1), tc)
    @test Set(tm) == Set(pr.med) && Set(tc) == Set(pr.cel)
    o = PottsModels.openvt_snapshot(p615h_state(σ))
    @test o.f[1] == 13 / 38
    @test o.f == [length(p615h_pairs(σ, c).med) / (length(p615h_pairs(σ, c).med) + length(p615h_pairs(σ, c).cel)) for c in 1:4]
    @test [length(p615h_pairs(σ, c).med) for c in 1:4] == [13, 5, 0, 2]
end

@testset "P6.15h (a) G1: openvt_f4_figure marks exactly the pairs openvt_snapshot counts" begin
    @test P615H_MAKIE
    σ = p615h_fig4()
    o = PottsModels.openvt_snapshot(p615h_state(σ))
    for c in 1:4
        fig = PottsModels.openvt_f4_figure(σ, c)
        ax = p615h_panel(fig)
        @test ax !== nothing
        geom = frame_geometry(only(p615h_pottsplots(ax.scene)).frame[])
        mk = p615h_marks(ax.scene, geom, σ, c)
        pr = p615h_pairs(σ, c)
        @test mk.bad == 0
        @test length(mk.medium) == length(unique(mk.medium)) && length(mk.cell) == length(unique(mk.cell))
        @test Set(mk.medium) == Set(pr.med) && Set(mk.cell) == Set(pr.cel)
        @test length(mk.medium) / (length(mk.medium) + length(mk.cell)) == o.f[c]
        if c == 1
            @test Set(mk.medium) == Set(p615h_tex_pair(σ, 1, d) for d in P615H_TEX_M)
            @test Set(mk.cell) == Set(p615h_tex_pair(σ, 1, d) for d in P615H_TEX_C)
            @test (length(mk.medium), length(mk.cell)) == (13, 25)
        end
    end
end

# ---------------------------------------------------------------------------------------------
# (b) structure of the figure functions
# ---------------------------------------------------------------------------------------------

@testset "P6.15h (b) F4 figure: panel, colours, identity encoding, no outlines" begin
    @test P615H_MAKIE
    @test Base.ispublic(PottsModels, :openvt_f4_figure)
    σ = p615h_fig4()
    fig = PottsModels.openvt_f4_figure(σ, 1)
    @test fig isa Makie.Figure
    Makie.colorbuffer(fig)
    @test length(p615h_pottsplots(fig.scene)) == 1
    ax = p615h_panel(fig)
    @test ax !== nothing
    pp = only(p615h_pottsplots(ax.scene))
    @test p615h_owners(pp.frame[]) == σ
    @test pp.encoding[] isa CellIdentityEncoding
    @test pp.boundaries[] === false
    @test p615h_close(pp.medium_color[], p615h_rgb(P615H_MEDIUM_F4); tol = 2.5 / 255)
    @test p615h_outlines(ax, σ, 1; markers = true) == 0
    segs = p615h_segments(ax.scene)
    @test count(s -> p615h_close(s[3], p615h_rgb(P615H_M)), segs) == 13
    @test count(s -> p615h_close(s[3], p615h_rgb(P615H_C)), segs) == 25
    tx = p615h_texts(fig)
    @test any(t -> occursin("Lattice models", t), tx)
    @test any(t -> occursin("13", t) && occursin("25", t), tx)
end

@testset "P6.15h (b) F1 figure: Potts.jl panel and banner" begin
    @test P615H_MAKIE
    @test Base.ispublic(PottsModels, :openvt_f1_figure)
    σ, frame = p615h_colony()
    c, rim = p615h_rim(σ)
    for (W, fig) in ((P615H_WINDOW, PottsModels.openvt_f1_figure(frame)), (40, PottsModels.openvt_f1_figure(frame; window = 40)))
        @test fig isa Makie.Figure
        Makie.colorbuffer(fig)
        @test length(p615h_pottsplots(fig.scene)) == 1
        ax = p615h_panel(fig)
        @test ax !== nothing
        pp = only(p615h_pottsplots(ax.scene))
        # colours (D-185): cell area on coolwarm, the panel's own min–max; white medium
        @test pp.encoding[] isa ChannelEncoding
        @test string(pp.colormap[]) == "coolwarm"
        @test p615h_close(pp.medium_color[], Makie.RGBf(1, 1, 1))
        # the crop: an unchanged W × W block on the 45° rim
        w, fr, _ = p615h_visible(ax)
        @test size(w) == (W, W)
        off = p615h_find(σ, w)
        @test off !== nothing
        vals = p615h_values(ax)
        @test vals !== nothing && size(vals) == size(w)
        if off !== nothing && vals !== nothing
            full = Dict(id => count(==(id), σ) for id in unique(filter(>(0), vec(w))))
            @test all(I -> w[I] == 0 ? isnan(vals[I]) : vals[I] == full[w[I]], CartesianIndices(w))
            # cells cut by the window keep their full-state area (the fixture has some)
            @test any(id -> count(==(id), w) < full[id], keys(full))
            @test all(Float64.(pp.colorrange[]) .== Float64.(extrema(values(full))))
            # boundaries (D-185): thin black, exactly the unlike-id pixel edges, each once
            E, other = p615h_edge_marks(ax.scene)
            @test other == 0
            @test length(E) == length(unique(E)) && Set(E) == p615h_edge_oracle(w, off)
            @test !isempty(E) && all(<=(1.5), p615h_linewidths(ax.scene))
            @test p615h_stroked(ax.scene, frame_geometry(fr)) == 0
        end
        if off !== nothing
            centre = off .+ (W + 1) / 2
            v = centre .- c
            @test 30 <= atand(v[2], v[1]) <= 60
            @test abs(hypot(v...) - rim) <= W / 4
            @test any(==(0), w) && any(>(0), w)
            ids = unique(filter(>(0), vec(w)))
            @test all(id -> cell_metadata(fr, RenderOwner(CellSite, id)).identity ==
                            cell_metadata(frame, RenderOwner(CellSite, id)).identity, ids)
        end
        # the banner
        boxes = [b for b in fig.content if b isa Makie.Box && p615h_close(b.color[], p615h_rgb(P615H_POTTS); tol = 0.6 / 255)]
        labels = [b for b in fig.content if b isa Makie.Label && string(b.text[]) == "Potts.jl"]
        @test length(boxes) == 1 && length(labels) == 1
        if length(boxes) == 1 && length(labels) == 1
            pv = ax.scene.viewport[]
            P = (; x = Float64(minimum(pv)[1]), y = Float64(minimum(pv)[2]), w = Float64(Makie.widths(pv)[1]), h = Float64(Makie.widths(pv)[2]))
            B = p615h_bbox(only(boxes))
            Lb = p615h_bbox(only(labels))
            @test isapprox(P.w, P.h; rtol = 0.01)                          # square panel
            @test isapprox(B.w, P.w; rtol = 0.01) && isapprox(B.x, P.x; atol = 0.01 * P.w)
            @test isapprox(B.h / P.h, 5 / 45; rtol = 0.1)
            @test isapprox((B.y - (P.y + P.h)) / P.h, 1 / 45; atol = 0.5 / 45)
            @test B.x <= Lb.x + Lb.w / 2 <= B.x + B.w && B.y <= Lb.y + Lb.h / 2 <= B.y + B.h
            lab = only(labels)
            @test p615h_close(lab.color[], Makie.RGBf(1, 1, 1))
            @test occursin("bold", lowercase(string(lab.font[])))
        end
    end
    # `areas` overrides the frame's site counts, and the scale follows (bare panel, no banner)
    fig = PottsModels.openvt_f1_figure(frame; areas = Dict(id => 3 * count(==(id), σ) + 1 for id in unique(filter(>(0), vec(σ)))),
        banner = false)
    ax = p615h_panel(fig)
    @test ax !== nothing
    @test isempty([b for b in fig.content if b isa Makie.Box])
    w, _, _ = p615h_visible(ax)
    vals = p615h_values(ax)
    @test all(I -> w[I] == 0 ? isnan(vals[I]) : vals[I] == 3 * count(==(w[I]), σ) + 1, CartesianIndices(w))
    pp = only(p615h_pottsplots(ax.scene))
    @test all(Float64.(pp.colorrange[]) .== extrema(3 * count(==(id), σ) + 1.0 for id in unique(filter(>(0), vec(w)))))
end

# ---------------------------------------------------------------------------------------------
# (c) negative controls
# ---------------------------------------------------------------------------------------------

@testset "P6.15h (c) a perturbed configuration changes the count, and the figure follows" begin
    σ = p615h_fig4()
    f0 = PottsModels.openvt_snapshot(p615h_state(σ)).f[1]
    # tikz (1, 3) medium → cell i−1: three medium pairs of cell i become cell pairs (10 + 28)
    σ1 = copy(σ); σ1[2, 4] = 2
    # tikz (3, 5) (cell i's tip) → medium: cell i's pairs change on both counts
    σ2 = copy(σ); σ2[4, 6] = 0
    @test (length(p615h_pairs(σ1, 1).med), length(p615h_pairs(σ1, 1).cel)) == (10, 28)
    for σp in (σ1, σ2)
        pr = p615h_pairs(σp, 1)
        fp = PottsModels.openvt_snapshot(p615h_state(σp)).f[1]
        @test fp == length(pr.med) / (length(pr.med) + length(pr.cel))
        @test fp != f0
        @test P615H_MAKIE
        fig = PottsModels.openvt_f4_figure(σp, 1)
        ax = p615h_panel(fig)
        @test ax !== nothing
        geom = frame_geometry(only(p615h_pottsplots(ax.scene)).frame[])
        mk = p615h_marks(ax.scene, geom, σp, 1)
        @test mk.bad == 0
        @test Set(mk.medium) == Set(pr.med) && Set(mk.cell) == Set(pr.cel)
        @test length(mk.medium) / (length(mk.medium) + length(mk.cell)) == fp
        @test (length(mk.medium), length(mk.cell)) != (13, 25)
        @test any(t -> occursin(string(length(pr.med)), t) && occursin(string(length(pr.cel)), t), p615h_texts(fig))
    end
end

@testset "P6.15h (c) the detectors catch outlines and wrong marks" begin
    @test P615H_MAKIE
    σ = p615h_fig4()
    # a clean hand-made figure passes, with exactly the oracle's marks
    fig, ax = p615h_control_figure(σ)
    geom = frame_geometry(only(p615h_pottsplots(ax.scene)).frame[])
    mk = p615h_marks(ax.scene, geom, σ, 1)
    @test mk.bad == 0 && mk.outline == 0
    @test (length(mk.medium), length(mk.cell)) == (13, 25)
    @test p615h_outlines(ax, σ, 1; markers = true) == 0
    @test p615h_outlines(ax, σ, 1; markers = false) > 0                 # F1's stricter rule sees the marks
    # outlines in three forms are caught
    @test p615h_outlines(p615h_control_figure(σ; boundaries = true)[2], σ, 1; markers = true) > 0
    @test p615h_outlines(p615h_control_figure(σ; overlay = true)[2], σ, 1; markers = true) > 0
    @test p615h_outlines(p615h_control_figure(σ; outline_lines = true)[2], σ, 1; markers = true) > 0
    # marks decoded against the wrong cell are flagged, not counted
    @test p615h_marks(ax.scene, geom, σ, 2).bad > 0
    # F1 (D-185): the edge decoder sees a missing edge (a gap), an extra segment, and a grey line
    σf = p615h_fig4()
    Ef = p615h_edge_oracle(σf, (0, 0))
    gapfig = Makie.Figure(); gax = Makie.Axis(gapfig[1, 1])
    segs = collect(Ef)
    Makie.linesegments!(gax, [Makie.Point2f(p) for e in segs[2:end] for p in e]; color = :black)
    E, other = p615h_edge_marks(gax.scene)
    @test other == 0 && Set(E) != Ef && length(E) == length(Ef) - 1
    Makie.linesegments!(gax, [Makie.Point2f(0.5, 0.5), Makie.Point2f(2.5, 0.5)]; color = :black)
    @test p615h_edge_marks(gax.scene)[2] == 1
    greyfig = Makie.Figure(); grax = Makie.Axis(greyfig[1, 1])
    Makie.linesegments!(grax, [Makie.Point2f(p) for e in segs for p in e]; color = :gray70)
    @test p615h_edge_marks(grax.scene)[2] == length(Ef)
    # the snapshot of a configuration without any medium contact has f = 0 and no magenta marks
    σ3 = copy(σ); σ3[σ3 .== 0] .= 4
    @test PottsModels.openvt_snapshot(p615h_state(σ3)).f[1] == 0.0 && isempty(p615h_pairs(σ3, 1).med)
end
