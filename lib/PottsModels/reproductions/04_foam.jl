# # Jiang, Swart, Saxena, Asipauskas & Glazier (1999): sheared two-dimensional foam
#
# A dry foam is a packing of gas bubbles separated by thin walls. Sheared slowly, it stores
# energy in its walls like an elastic solid until bubbles swap neighbours (T1 events), and
# then it flows. Jiang and co-authors modelled the foam as a large-Q Potts model with an
# area constraint per bubble and a shear term that biases copies along x. They showed
# hysteresis loops whose shape changes from elastic to viscoelastic to plastic with the
# shear amplitude and the wall energy J, and stick–slip avalanches of T1 events whose
# statistics depend on how disordered the foam is.
#
# - Y. Jiang, P.J. Swart, A. Saxena, M. Asipauskas, J.A. Glazier, "Hysteresis and
#   avalanches in two-dimensional foam rheology simulations", *Phys. Rev. E* **59**, 5819
#   (1999), doi:[10.1103/PhysRevE.59.5819](https://doi.org/10.1103/PhysRevE.59.5819).
#
# The page shows, in order:
#
# 1. the model code;
# 2. a minimal run: the paper's ordered foam, from a brick wall;
# 3. the results against the paper: the runs as videos, a verdict summary and the table
#    of deviations;
# 4. the details, collapsed: protocol, every pre-registered row, the full-run command and
#    provenance.
#
# !!! warning "Provisional"
#     No full run of this reproduction exists yet. The full run (V1–V20 with 5 replicates
#     each, about 150 CPU-hours) is offline work; until its record is committed under
#     `lib/PottsModels/reproductions/data/04/`, the results below are **smoke-scale**: the
#     no-shear rows on 2 ordered foams and 1 disordered foam at the paper's size, a short
#     shear check, and short videos. The shear amplitudes in the videos are model units,
#     because the γ scale κ is calibrated by the full run.

using Potts, PottsModels
using PottsModels.Analysis: stored_energy, side_counts, topology_moments, cell_graph, t1_events
using CairoMakie
using Statistics: mean, median
using Markdown
using Random: Xoshiro
CairoMakie.activate!(type = "png")
nothing #hide

# ## 1. The model
#
# Eq. (1) of the paper: a wall energy J for every pair of unlike neighbouring sites, over
# the 20 neighbours up to the fourth shell, and an area constraint Γ(a − A)² per bubble. The
# shear adds, for a copy of the source's bubble into the target site, the bias
# γ(y, t)·(x_target − x_source) along x (Eq. 2 in the displacement form, deviation DV3),
# with γ on the two boundary rows only (Eq. 6, boundary shear) or linear in y about the
# mid-plane (Eq. 7, bulk shear), steady or sin(ωt).

@potts_model ShearedFoam begin
    @structural_parameters begin
        lattice = (256, 256)                       # sites (04b p.5822)
    end
    @kinds medium bubble                           # dry foam: no site is medium
    @parameters begin
        J = 3.0                                    # wall energy per unlike pair (p.5823)
        Γ = 1.0                                    # area constraint (p.5823); Γ = 0 coarsens
        T = 1.0e-6                                 # T → 0⁺ (DV2)
        γ0 = 0.0                                   # boundary shear amplitude (Eq. 6)
        β = 0.0                                    # bulk shear rate (Eq. 7)
        bulk = 0.0                                 # 1: Eq. 7, else Eq. 6
        periodic = 0.0                             # 1: G = sin(ω mcs), else G = 1
        ω = 2π / 4000
        ytop = 256.0                               # the top row, L_y
        ymid = 128.5                               # the mid-plane, (L_y + 1)/2
    end
    @variables begin
        A(cell) = 256.0                            # target area, 16² (p.5823)
    end
    ## x periodic, y closed walls (no wall cells, A-2)
    @lattice Lattice(lattice; boundary = (Periodic(), Closed()), neighborhood = NeighborOrder(4))
    @relations proposal = NeighborOrder(4)
    @energy begin
        contacts => J
        cells(bubble) => Γ * (volume - A)^2
    end
    ## γ > 0 biases copies towards −x: the top row moves +x and the bottom −x (Figs. 2, 4, 5)
    @drive copy => ifelse(periodic > 0.5, sin(ω * mcs), 1.0) *
                   ifelse(bulk > 0.5, -β * (position[target][2] - ymid),
        γ0 * (ifelse(position[target][2] < 1.5, 1.0, 0.0) - ifelse(position[target][2] > ytop - 0.5, 1.0, 0.0))) *
                   direction[1]
    @sweep Metropolis(; temperature = T)
end
nothing #hide

# ## 2. A minimal run
#
# The paper's ordered foam (p.5823): 256 bricks of 16² in common bond, a short anneal at
# T = 3, then relaxation at T = 0. Proposals are made at wall sites only
# (`BoundarySiteCPM`), to a uniform neighbour among the 20 (deviation DV1).

brick(L) = Int32[(r = (y - 1) ÷ 16; r * (L[1] ÷ 16) + mod(x - 1 - (isodd(r) ? 8 : 0), L[1]) ÷ 16 + 1)
                 for x in 1:L[1], y in 1:L[2]]
L = (256, 256)
σ0 = brick(L)
nb = Int(maximum(σ0))
u0 = [ownership => σ0, kind => fill(:bubble, nb), :A => fill(256.0, nb)]
prob = PottsProblem(ShearedFoam(; name = :foam), u0, (0, 10); seed = 1)
alg = BoundarySiteCPM()
annealed = solve(remake(prob; p = [:T => 3.0]), alg).u[end]                       # 10 MCS at T = 3
relaxed = solve(remake(prob; u0 = [ownership => Array(annealed.σ), kind => fill(:bubble, nb), :A => fill(256.0, nb)],
    tspan = (0, 1000)), alg).u[end]                                                 # 1000 MCS at T → 0⁺
lat = Lattice(L; boundary = (Periodic(), Closed()))
(hexagons = count(==(6), side_counts(Array(relaxed.σ), lat)), μ2_n = topology_moments(Array(relaxed.σ), lat).mu2_n)

# `side_counts` gives each bubble's number of sides n. The closed wall is not a side (A-2),
# so the 16 + 16 bubbles on the two walls have 4 sides and every other one 6: μ2(n) =
# 32 × 2² / 256 = 7/16 = 0.4375 (the paper's Fig. 11(c): 0.437). Counting the wall as a side
# would give the wall bubbles 5 sides and μ2(n) = 0.109.
#
# ## 3. Results
#
# ```@raw html
# <details><summary>Code: the helpers, the smoke-scale runs and the record (if any) used below</summary>
# ```

## one problem per lattice size, remade per run (compiling a problem is the costly part)
const PROBS = Dict{Tuple{Int, Int}, Any}()
foam_lat(L) = Lattice(L; boundary = (Periodic(), Closed()))
function foam_problem(σ, A, tend; seed, p...)
    L = size(σ)
    base = get!(() -> PottsProblem(ShearedFoam(; name = :foam, lattice = L),
            [ownership => brick(L), kind => fill(:bubble, Int(maximum(brick(L)))), :A => fill(256.0, Int(maximum(brick(L))))],
            (0, 1); seed = 1), PROBS, L)
    pp = Pair{Symbol, Float64}[:ytop => L[2], :ymid => (L[2] + 1) / 2, (k => Float64(v) for (k, v) in p)...]
    return remake(base; u0 = [ownership => σ, kind => fill(:bubble, length(A)), :A => A], p = pp, tspan = (0, tend), seed)
end
## interior bubbles (not touching y = 1 or y = L_y) with n = 6, over interior bubbles
function hexfrac(σ)
    n = side_counts(σ, foam_lat(size(σ)))
    edge = Set(σ[:, [1, end]])
    live = Set(σ)
    int = [b for b in live if !(b in edge)]
    return count(b -> b <= length(n) && n[b] == 6, int) / length(int)
end
mu2n(σ) = topology_moments(σ, foam_lat(size(σ))).mu2_n
area_frac(σ, A; J = 3.0) = (a = [count(==(b), σ) for b in eachindex(A)];
    Ea = sum((a[b] - A[b])^2 for b in eachindex(A) if a[b] > 0); Ea / (Ea + J * stored_energy(σ, foam_lat(size(σ)))))
"""Run `prob` for `tend` MCS, keeping σ every `every` MCS (and at the start) for the video."""
function frames!(integ, tend, every; each = (m, σ) -> nothing)
    F = [copy(Array(integ.u.σ))]
    for m in 1:tend
        step!(integ)
        each(m, integ.u.σ)
        m % every == 0 && push!(F, copy(Array(integ.u.σ)))
    end
    return F
end

## smoke-scale foams, as the frozen test's SMOKE tier makes them (same seeds): 2 ordered, and
## 1 disordered (μ2(n) → 0.81) coarsened from its own ordered foam
function ordered(seed; video = false)
    A = fill(256.0, nb)
    i1 = init(foam_problem(brick(L), A, 10; seed, T = 3.0), alg)
    F1 = frames!(i1, 10, 1)
    i2 = init(foam_problem(Array(i1.u.σ), A, 1000; seed), alg)
    F2 = frames!(i2, 1000, video ? 10 : 1000)
    return (; σ = Array(i2.u.σ), A, frames = video ? [F1; F2[2:end]] : nothing)
end
function disordered(o, target, seed)
    integ = init(foam_problem(o.σ, o.A, 20_000; seed, T = 3.0, Γ = 0.0), alg)
    F = [copy(o.σ)]
    m = 0
    trace = [(0, mu2n(o.σ))]
    while m < 20_000
        for _ in 1:10
            step!(integ)
        end
        m += 10
        push!(F, copy(Array(integ.u.σ)))
        push!(trace, (m, mu2n(Array(integ.u.σ))))
        last(trace)[2] >= target && break
    end
    σc = Array(integ.u.σ)
    A = Float64.(integ.u.cell.volume[1:Int(maximum(σc))])
    relaxed = solve(foam_problem(σc, A, 1000; seed), alg).u[end]
    return (; σ = Array(relaxed.σ), A, stop = m, frames = F, trace)
end
t_ord = @elapsed foams = [ordered(9_400_000 + k; video = k == 1) for k in 1:2]
d081 = disordered(ordered(9_400_010), 0.81, 9_400_010)            # the frozen test's first d081 try
smoke = [(; hex = hexfrac(f.σ), mu2 = mu2n(f.σ), af = area_frac(f.σ, f.A), nbub = length(unique(f.σ))) for f in foams]
dis = (; hex = hexfrac(d081.σ), mu2 = mu2n(d081.σ), af = area_frac(d081.σ, d081.A), nbub = length(unique(d081.σ)))

## a short bulk shear (model β, κ not yet calibrated) on the ordered and the disordered foam:
## φ̂ every 10 MCS, T1 events per MCS (VonNeumann(1) contacts, one T1 = 1), frames every 30 MCS
function sheared(f, βm, tend, seed; γ0 = 0.0)
    integ = init(foam_problem(f.σ, f.A, tend; seed, β = βm, bulk = βm > 0 ? 1.0 : 0.0, γ0), alg)
    fl = foam_lat(size(f.σ))
    φ0 = stored_energy(f.σ, fl)
    g = Ref(cell_graph(f.σ, fl))
    φ, t1 = Float64[], Float64[]
    each = function (m, σ)
        g2 = cell_graph(σ, fl)
        push!(t1, t1_events(g[], g2; unit = :t1))
        g[] = g2
        m % 10 == 0 && push!(φ, stored_energy(σ, fl) / φ0)
    end
    t = @elapsed F = frames!(integ, tend, 30; each)
    return (; frames = F, φ, t1, wall = t, σ = Array(integ.u.σ))
end
const SHEAR_MCS = 3000
sh_ord = sheared(foams[1], 0.05, SHEAR_MCS, 9_400_021)
sh_dis = sheared(d081, 0.05, SHEAR_MCS, 9_400_023)
sh_nul = sheared(foams[1], 0.0, 500, 9_400_022)                 # control: no shear, no T1
## steady boundary shear (Eq. 6) at model γ0 = 24, the largest the frozen test's feasibility
## probe tried without a T1 under periodic shear (κ not yet calibrated)
const Γ0_MODEL = 24.0
sh_bnd = sheared(foams[1], 0.0, SHEAR_MCS, 9_400_024; γ0 = Γ0_MODEL)

## the full-run record, if one has been committed
rec_root = joinpath(pkgdir(PottsModels), "reproductions", "data", "04")
rec_dirs = isdir(rec_root) ? filter(d -> startswith(d, "full-") && isdir(joinpath(rec_root, d)), readdir(rec_root)) : String[]
rec_dir = length(rec_dirs) == 1 ? joinpath(rec_root, only(rec_dirs)) : nothing
rec_rows(file) = (l = split.(readlines(joinpath(rec_dir, file)), '\t'); [Dict(zip(l[1], r)) for r in l[2:end]])
nothing #hide

## videos: one fixed colour per bubble id, no outlines (a bubble keeps its colour while others vanish)
function foam_video(file, F; fps = 15, title = "")
    n = maximum(maximum, F)
    rng = Xoshiro(4)
    pal = [RGBf(0.25 .+ 0.7 .* rand(rng, 3)...) for _ in 1:n]
    img = Observable(pal[F[1]])
    fig = Figure(size = (420, 440))
    ax = Axis(fig[1, 1]; aspect = DataAspect(), title)
    hidedecorations!(ax)
    image!(ax, img; interpolate = false)
    record(fig, file, eachindex(F); framerate = fps) do i
        img[] = pal[F[i]]
    end
    return file
end
foam_video("04_foam_ordered.mp4", foams[1].frames; title = "brick wall → anneal → relax")
foam_video("04_foam_coarsening.mp4", d081.frames; title = "coarsening to μ2(n) = 0.81 (Γ = 0, T = 3)")
foam_video("04_foam_bulk_ordered.mp4", sh_ord.frames; title = "ordered foam, bulk shear")
foam_video("04_foam_bulk_d081.mp4", sh_dis.frames; title = "disordered foam (μ2(n) ≈ 0.8), bulk shear")
foam_video("04_foam_boundary_ordered.mp4", sh_bnd.frames; title = "ordered foam, steady boundary shear")
nothing #hide

# ```@raw html
# </details>
# ```
#
# ### The runs, as videos
#
# Each bubble keeps one colour, without outlines. Left: the ordered foam forming from the
# brick wall (10 MCS at T = 3, then 1000 MCS at T → 0⁺, every 10 MCS). Right: that foam
# coarsening at Γ = 0, T = 3 until μ2(n) reaches 0.81, the paper's first disordered foam
# (Figs. 6, 8(b), 11); the frozen protocol then resets each bubble's target area and
# relaxes at T → 0⁺.
#
# ```@raw html
# <figure><video src="../04_foam_ordered.mp4" controls loop muted playsinline width="400"></video>
# <video src="../04_foam_coarsening.mp4" controls loop muted playsinline width="400"></video></figure>
# ```
#
# Bulk shear (Eq. 7) at model β = 0.05 for 3000 MCS, every 30 MCS: the ordered foam (left)
# and the disordered one (right). The top moves +x and the bottom −x, as the arrows of the
# paper's Figs. 4(a) and 5(a). The rate is in model units: the full run calibrates the
# factor κ between model and paper γ, and the time scale τ (Details).
#
# ```@raw html
# <figure><video src="../04_foam_bulk_ordered.mp4" controls loop muted playsinline width="400"></video>
# <video src="../04_foam_bulk_d081.mp4" controls loop muted playsinline width="400"></video></figure>
# ```
#
# Steady boundary shear (Eq. 6, the paper's Figs. 2 and 6) on the ordered foam at model
# γ0 = 24 for 3000 MCS, every 30 MCS: only the rows y = 1 and y = L_y are driven. The paper's
# γ0 = 7 (DV5) becomes κ × 7 in the full run, which also runs the disordered foam (V9); both
# are pending the full run.
#
# ```@raw html
# <figure><video src="../04_foam_boundary_ordered.mp4" controls loop muted playsinline width="400"></video></figure>
# ```

let f = Figure(size = (900, 300)) #hide
    ax1 = Axis(f[1, 1]; xlabel = "MCS at Γ = 0, T = 3", ylabel = "μ2(n)", title = "coarsening to a μ2(n) target") #hide
    lines!(ax1, first.(d081.trace), last.(d081.trace); color = :dodgerblue4) #hide
    hlines!(ax1, [0.81]; color = :gray55, linestyle = :dash) #hide
    ax2 = Axis(f[1, 2]; xlabel = "MCS", ylabel = "φ / φ(0)", title = "stored energy, bulk shear") #hide
    for (s, c, l) in ((sh_ord, :dodgerblue4, "ordered"), (sh_dis, :darkorange3, "μ2(n) ≈ 0.8")) #hide
        lines!(ax2, 10 .* eachindex(s.φ), s.φ; color = c, label = l) #hide
    end #hide
    axislegend(ax2; position = :lt, framevisible = false) #hide
    ax3 = Axis(f[1, 3]; xlabel = "MCS", ylabel = "T1 events (cumulative)", title = "T1 events, bulk shear") #hide
    for (s, c) in ((sh_ord, :dodgerblue4), (sh_dis, :darkorange3)) #hide
        lines!(ax3, eachindex(s.t1), cumsum(s.t1); color = c) #hide
    end #hide
    f #hide
end #hide

# ### Verdicts at a glance
#
# The rows are pre-registered in the frozen test (`test/reproductions/04_foam.jl`, D-190),
# with the paper's acceptance bands. Smoke-scale values below come from this page's runs
# (2 ordered foams, 1 disordered); the full run judges 10 ordered foams, 30 disordered ones
# and every shear row on 5 replicates.

fmt(x; d = 3) = string(round(x; digits = d)) #hide
pf(ok) = ok ? "PASS" : "**FAIL**" #hide
checks = [all(s -> s.hex >= 0.95, smoke), all(s -> 0.3 <= s.mu2 <= 0.6, smoke), all(s -> s.af < 5e-3, smoke), #hide
    abs(dis.mu2 - 0.81) <= 0.3, dis.hex < 0.95, sum(sh_nul.t1) == 0] #hide
if rec_dir === nothing #hide
    Markdown.parse(join([ #hide
        "**Smoke scale: $(count(checks)) of $(length(checks)) checks pass. V2–V20: pending the full run.**", #hide
        "", #hide
        "| Row | Target (paper) | Band | Ours (smoke scale) | Result |", #hide
        "|---|---|---|---|---|", #hide
        "| V1 | relaxed ordered foam all-hexagonal (p.5823, Fig. 2(a)) | interior n = 6 share ≥ 0.95, every foam | $(join(fmt.(getfield.(smoke, :hex)), ", ")) (2 foams) | $(pf(checks[1])) (smoke) |", #hide
        "| V1b | μ2(n) of the ordered foam ≈ 0.437 (Fig. 11(c)) | [0.3, 0.6], every foam | $(join(fmt.(getfield.(smoke, :mu2); d = 4), ", ")) | $(pf(checks[2])) (smoke) |", #hide
        "| V19 | area energy ≈ 10⁻³ of the total at T = 0 (p.5823) | < 5 × 10⁻³ | $(join(fmt.(getfield.(smoke, :af); d = 6), ", ")) | $(pf(checks[3])) (smoke) |", #hide
        "| PREP | disordered foams reach their μ2(n) | \\|μ2(n) − 0.81\\| ≤ 0.3 | $(fmt(dis.mu2; d = 4)) after $(d081.stop) MCS of coarsening, $(dis.nbub) bubbles | $(pf(checks[4])) (smoke, 1 of 30 foams) |", #hide
        "| C-V1 | control: V1's measure rejects a disordered foam | hexagon share < 0.95 | $(fmt(dis.hex)) | $(pf(checks[5])) (smoke) |", #hide
        "| C-S2 | control: no shear, no T1 at T → 0⁺ | 0 T1 in 500 MCS | $(sum(sh_nul.t1)) | $(pf(checks[6])) (smoke) |", #hide
        "| V2–V20 | boundary shear, loops, J and T sweeps, (J, γ0) boundaries, bulk shear localisation, spectra, N̄(β), yield strain, μ2(n) rise, no system-wide avalanches | Details | under bulk shear at model β = 0.05: $(fmt(sum(sh_ord.t1); d = 1)) T1 events (ordered) and $(fmt(sum(sh_dis.t1); d = 1)) (disordered) in $(SHEAR_MCS) MCS | pending the full run |", #hide
    ], "\n")) #hide
else #hide
    V = rec_rows("verdicts.tsv") #hide
    np, nf = count(r -> r["result"] == "PASS", V), count(r -> r["result"] == "FAIL", V) #hide
    Markdown.parse("**Full run `data/04/$(only(rec_dirs))`: $np PASS, $nf FAIL.**\n\n" * #hide
                   "| Row | Kind | Ours | Band | Result |\n|---|---|---|---|---|\n" * #hide
                   join(["| $(r["id"]) | $(r["kind"]) | $(replace(r["value"], "|" => "\\|")) | $(replace(r["band"], "|" => "\\|")) | " * #hide
                         (r["result"] == "FAIL" ? "**FAIL**" : r["result"]) * " |" for r in V], "\n")) #hide
end #hide

# ### Deviations
#
# One row per difference from the paper and per provisional target (D-154). The columns are
# our value, the paper's value, the suspected cause and the status of the question to the
# authors: "not an author question", "not asked" (the question is on our open question
# list; spec 04 §7 names it), "asked on ⟨date⟩" or "answered → ⟨D-entry⟩".

τ_brick = let σ = brick(L), s = 0.0, nbd = 0 #hide
    offs = [(a, b) for a in -2:2 for b in -2:2 if 0 < a^2 + b^2 <= 5] #hide
    for x in 1:L[1], y in 1:L[2] #hide
        u = count(((a, b),) -> 1 <= y + b <= L[2] && σ[x, y] != σ[mod1(x + a, L[1]), y + b], offs) #hide
        u > 0 && (s += u / 20; nbd += 1) #hide
    end #hide
    nbd / s #hide
end #hide
NA(a) = "not asked (on our open question list: spec 04 §7 $a)" #hide
Markdown.parse(join([ #hide
    "| Item | Ours | Paper | Suspected cause | Author question |", #hide
    "|---|---|---|---|---|", #hide
    "| V2–V20 (**provisional**) | not run yet: smoke-scale checks only (above) | Figs. 2–11 | the full run (about 150 CPU-hours) is offline work; this page cites its record once it is committed | not an author question |", #hide
    "| DV1 proposal law and time scale τ | a uniform neighbour among the 20, at wall sites (`BoundarySiteCPM`); like neighbours are null draws, so a wall site is updated less often per MCS than in the paper. One paper MCS is τ = 1/ū of our MCS, ū the mean unlike share of the wall sites' 20 neighbours: τ = $(fmt(τ_brick; d = 2)) on the brick wall; the full run measures it on its 5 relaxed ordered foams, and every shear time is in paper MCS | a wall site picked at random, a copy only to an unlike neighbour, every pick counted as a trial (p.5822) | the paper's unlike-neighbour proposal (`UnlikeNeighbor`) is not in the engine yet (D-186). τ corrects the mean rate, not the per-site spread | $(NA("A-4, A-5")) |", #hide
    "| DV2 T = 0 | T = 10⁻⁶ (the T → 0⁺ limit: ties accepted, uphill rejected) | T = 0 in Eq. 3, the ΔH = 0 case typeset ambiguously | Eq. 3 (A-6) | $(NA("A-6")) |", #hide
    "| DV3 shear form and scale κ | the bias γ(y, t)·(x_target − x_source) per copy, minimum image in x; model γ = κ × paper γ, κ calibrated so that the first T1 per cycle at J = 3 falls at the paper's γ0/J ≈ 1.9 (two-stage, pre-registered) | Eq. 2 written with an absolute x_i and a free index j | a literal reading makes the bias grow with x and breaks Fig. 3(c)'s lines through the origin (A-1) | $(NA("A-1")) |", #hide
    "| DV4 lattice of the low-μ2(a) foams | d095 and d107 on 320² (400 bricks) | 377 and 380 bubbles (Fig. 9) | 256² holds only 256 bricks of 16² (A-14) | $(NA("A-14")) |", #hide
    "| DV5 unstated values | steady boundary γ0 = 7 (Figs. 2, 6), β = 0.01 for Fig. 11(b), run lengths 2¹⁵ (N̄) and 10⁴ (μ2(n) rise); anneal 10 MCS at T = 3, relax 1000 MCS, coarsen at Γ = 0, T = 3 to the μ2(n) target | not stated | pre-registered choices (D-155, D-156) | $(NA("A-8, A-12")) |", #hide
    "| Wall type (A-2) | closed y edges without wall cells; a wall is not a side: μ2(n) = 7/16 = 0.4375 on the brick wall | 0.437 (Fig. 11(c)); the wall type is not stated | the reading that matches the paper's baseline (0.109 if the wall counted as a side, 0 with periodic y) | $(NA("A-2")) |", #hide
    "| T1 counting unit (A-15) | one T1 = 1 (`t1_events(…; unit = :t1)`); only ratios are targets | even-valued T1 bars (Figs. 4(b), 5(b)) | the paper seems to count each T1 twice | $(NA("A-15")) |", #hide
], "\n")) #hide

# ## 4. Details
#
# ```@raw html
# <details><summary>Protocol, every pre-registered row, the full-run command and provenance (click to open)</summary>
# ```
#
# ### Paper and sources
#
# - Y. Jiang, P.J. Swart, A. Saxena, M. Asipauskas, J.A. Glazier, *Phys. Rev. E* **59**,
#   5819–5832 (1999), doi:[10.1103/PhysRevE.59.5819](https://doi.org/10.1103/PhysRevE.59.5819);
#   the arXiv version cond-mat/9902111 has the same text without the figures.
# - Spec: `docs/design/research/model-specs/04_foam.md` (§2 mechanics, §5 targets, §7
#   ambiguities, §8 build plan). Frozen test: `lib/PottsModels/test/reproductions/04_foam.jl`
#   (D-190), which fixes every row, band, seed and run length below.
#
# ### Protocol
#
# - **Lattice and energy.** 256², x periodic, y closed without wall cells (A-2); J = 3 over
#   `NeighborOrder(4)` (20 neighbours, p.5822); Γ = 1, A = 256 (p.5823); a dry foam, no
#   medium site.
# - **Ordered foam.** The brick wall, anneal 10 MCS at T = 3, relax 1000 MCS at T → 0⁺
#   (A-8). Ten foams in the full run.
# - **Disordered foams.** From an ordered foam: Γ = 0 at T = 3, μ2(n) read every 10 MCS,
#   stop at the first read at or above the target (at most 2 × 10⁴ MCS); each bubble's target
#   area becomes its area at the stop; relax at T → 0⁺, Γ = 1. Accepted if μ2(n) is within
#   0.3 of the target, else the next seed (at most 5 tries). Targets 0.81, 1.65, 1.72, 2.02
#   on 256², and 0.95, 1.07 on 320² (DV4); five foams each.
# - **Shear.** Eq. 6 (boundary rows y = 1 and y = L_y) or Eq. 7 (linear in y about the
#   mid-plane), steady or sin(ωt) with a period of 4000 paper MCS. Model γ = κ × paper γ.
# - **Time.** Every shear duration, period, bin and spectral frequency is in paper MCS; one
#   paper MCS is τ of ours (DV1). Foam preparation is in our MCS.
# - **Calibration of κ.** At J = 3, the model γ0/J runs over 2^(−2 … 6) in steps of 2^0.25;
#   r\* is the first crossing of a median of 0.5 T1 per cycle, and κ = 3r\*/5.8 (the paper's
#   butterfly → U transition at γ0 = 5.7–5.8, Fig. 3(a)). No crossing stops the full run as a
#   science question.
# - **Observables** (`PottsModels.Analysis`). φ = `stored_energy` (Eq. 8, unlike pairs over
#   the 20 neighbours), φ̂ = φ/φ(0); n = `side_counts` (VonNeumann(1)); μ2(n), μ2(a) =
#   `topology_moments`; T1s per MCS = `t1_events` between consecutive `cell_graph`s;
#   spectra = `power_spectrum` and `spectral_exponent` (Eq. 9); N̄ = `mean_t1`; the first T1
#   avalanche = `yield_strain`.
#
# ### Every pre-registered row
#
# | Row | Target (spec 04 §5.2) | Rule (full run, 5 replicates unless stated) |
# |---|---|---|
# | V1 | ordered foam all-hexagonal | interior n = 6 share ≥ 0.95, every one of 10 foams |
# | V1b | μ2(n) baseline ≈ 0.44 | ∈ [0.3, 0.6], every foam |
# | PREP | disordered foams hit their μ2(n) | every foam accepted; mean μ2(a) of d165, d172 > of d095, d107 |
# | V2 | steady boundary shear γ0 = 7, 10⁴ MCS | interior n = 6 share > 0.95; φ̂ sawtooth (≥ 3 drops, median 0.5–2 %, regular spacing); T1s in bursts with quiet share ≥ 0.3 |
# | V3 | J = 3 loops vs γ0 | γ0 = 1 flat, no T1; 3.5 butterfly, height 1–3 %, no T1; 7 U-shaped, ≥ 1 T1 per cycle |
# | V4 | J sweep at γ0 = 7 | J = 10, 5 no T1; J = 3 one or two; J = 1 two or more; non-increasing in J |
# | V5 | (J, γ0) regime boundaries | lines γ0 = a + sJ: elastic s ∈ [0.7, 1.4], first T1 s ∈ [1.4, 2.5], \|a\| ≤ 1.6; boundaries ordered |
# | V6 | T sweep at γ0 = 4 | mean φ̂ increasing in T; loop height/noise > 3 at T = 0, < 1 at T = 15 |
# | V7 | ordered bulk β = 0.01 | non-hexagonal bubbles at the mid-plane ≥ 90 %; drops ≤ 0.6 × V2's; T1 spectral peak at f\* ∈ (5 × 10⁻⁴, 1.5 × 10⁻³) |
# | V8 | ordered bulk β = 0.05 | mid-plane share < 0.5 |
# | V9 | disordered (μ2(n) = 1.65), boundary shear | first T1 avalanche before 100 MCS in ≥ 4/5 |
# | V10 | ordered T1 spectra | α(0.05) ∈ [0.7, 1.3]; \|α(0.02)\| < 0.3 |
# | V11 | μ2(n) = 0.81 T1 spectra | α rises with β (Spearman ≥ 0.8); α(0.05) ∈ [0.7, 1.2]; α(0.001) < 0.4 |
# | V12 | μ2(n) = 1.65: no T1 power law | every one-decade window α ≤ 0.5 |
# | V13 | φ spectra 1/f-like | α_φ ∈ [0.5, 1.2], every window < 1.5 |
# | V14 | N̄(β) over five rates, four foams | N̄(10⁻⁴)/N̄(10⁻³) ∈ [4, 25]; N̄(10⁻³)/N̄(5 × 10⁻²) ≥ 10; high-μ2(a)/low-μ2(a) ≥ 5 at β ≥ 5 × 10⁻³ |
# | V15 | yield strain | ordered plateau spread ≤ 10 %; ε(0.05)/ε(0.01) ∈ [0.25, 0.6]; disordered ≤ 0.045 × the plateau |
# | V16 | μ2(n) rises under shear | mean over [2000, 10⁴] − initial ≥ 0.1 in ≥ 4/5, four foams |
# | V17 | μ2(n) excursions with φ drops | ≥ 80 % of ≥ 3 excursions overlap a falling leg |
# | V18 | no system-wide avalanches | share of bubbles changing contacts in a 100-MCS window < 0.5 |
# | V19 | area energy ≪ total | < 5 × 10⁻³ (relaxed foams; ordered β = 0.01 runs) |
# | V20 | bulk/boundary drop ratio ≈ 0.4 | ∈ [0.2, 0.6] |
#
# Negative controls: C-V1 (a disordered foam fails V1's measure), C-V1b (the wall counted
# as a side gives μ2(n) = 0.109, periodic y gives 0), C-V9 (the ordered foam does not yield
# early), C-V12 (the ordered β = 0.05 spectrum is a power law), C-V16 (no rise without
# shear), C-V18 (a row shift changes every contact list), and in the smoke tier no drift and
# no T1 without shear.
#
# ### The full run
#
# The full run is the frozen test's FULL tier, made resumable and parallel over runs by
# `lib/PottsModels/reproductions/data/04/run_full.jl`: 40 foams, 165 calibration loops, then
# 530 loops, 15 steady and 200 bulk runs, about 1.35 × 10⁸ of our MCS (≈ 150 CPU-hours at
# 4 ms per MCS). From the repository root:
#
# ```
# julia --project=lib/PottsModels/test lib/PottsModels/reproductions/data/04/run_full.jl \
#     --out <dir> --threads 24
# ```
#
# Each finished run is kept, so a rerun resumes. The record goes to `<dir>/record/` and is
# committed as `lib/PottsModels/reproductions/data/04/full-<date>/`; the frozen test then
# recomputes every row from it.
#
# ### Provenance of the smoke-scale results

Markdown.parse("PottsModels $(pkgversion(PottsModels)), Julia $(VERSION), on $(strip(Sys.cpu_info()[1].model)) " *
               "($(Sys.MACHINE)), CPU, one thread. Two ordered foams in $(round(t_ord; digits = 1)) s; " *
               "bulk shear $(round(1e3 * sh_ord.wall / SHEAR_MCS; digits = 2)) ms per MCS with the per-MCS " *
               "T1 detection (256², `BoundarySiteCPM`). Seeds: the foams use the frozen test's smoke seeds " *
               "(ordered 9 400 001–2; the d081 foam's ordered start, coarsening and relaxation 9 400 010, " *
               "its first try). The shear runs use 9 400 021 and 9 400 022, the frozen shear check's seeds, " *
               "here for 3000 MCS instead of its 500, and 9 400 023–24 for the disordered bulk and the " *
               "boundary run; the frozen test does not pin these.")

# | Date | Change | Reason |
# |---|---|---|
# | 2026-10-08 | First version, provisional: the model, the ordered and disordered foams, smoke-scale verdicts, a short bulk shear, videos, the deviations table and the full-run command | P6.4r; D-186, D-190 |
#
# ```@raw html
# </details>
# ```
