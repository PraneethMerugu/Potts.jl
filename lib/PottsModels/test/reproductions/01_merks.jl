# P6.3d (ROADMAP Phase 6, step 3): reproduction 01, Merks et al. 2006 (Variant E, 01a) and
# Merks et al. 2008 (Variant CI, 01b). Frozen (AUTONOMY §7.3; D-153). The pre-registered
# V-targets are spec 01 §5 (docs/design/research/model-specs/01_merks.md) as audited in
# D-153; every reference value and tolerance below is copied from §5's "Proposed
# acceptance" column, with the observable, time, seeds and replicate counts fixed here.
# The tutorial page `lib/PottsModels/reproductions/01_merks.jl` carries the same table.
#
# Models and starts (acceptance/p6_3d_merks_split.jl pins them):
#   2006: Merks2006() on 500² (1-site frame), merks2006_layout(; seed) = 282 cells of 10²
#         over the central 333² (01a Fig. 4).
#   2008: Merks2008() on 202² (2-site frame = TST 200²), merks2008_sprout(; seed) = 128
#         cells (Figs. 5–11); the paper's de novo geometry (V-C1, D-050 M10)
#         merks2008_denovo(; lattice = (502, 502), n = 1000, region = (85:417, 85:417), seed).
#   Every run: SequentialCPM() (the model's own neighbourhood), field_solver =
#   ExplicitEuler(substeps = 15), solver seed = layout seed = the run's seed.
#
# Time (D-050 M6; spec 01 §8 A-19, open): "N MCS" in the paper is our state after N MCS
# counted from the start of the run — TST's loop counter, which includes the 2008
# relaxation (MCS 0–99 without the field). Binding rows use that reading; the page also
# reports every 2008 value at N + 100 (time from the end of relaxation), not gating.
# 2006: 1 MCS = 30 s, so h hours = 120 h MCS.
#
# Observables (written here; spec 01 §5, §7.7):
#   O1 compactness C (01b p.5; TST Compactness(), ca.cpp:1376-1448, D-18): the number of
#      endothelial sites over the area of the convex hull of their site centres (Andrew's
#      monotone chain, shoelace), all endothelial sites (no largest-cluster selection).
#   O2 network share: endothelial sites in the largest 8-connected component of endothelial
#      sites, over all endothelial sites.
#   O3 lacunae: 4-connected components of medium sites with ≥ 10 sites that touch no
#      border site (enclosed by cells). Not the paper's skeleton count (A-18): a
#      network/coarsening measure only, never compared with Fig. 5's numbers.
#   O4 network classification: network iff O2 ≥ 0.9 and O3 ≥ 3; otherwise islands.
#   O5 mean displacement: the mean over cells of |centroid(t) − centroid(t₀)|, Δx = 2 µm.
#   O6 body-frame anisotropy (01a Fig. 11): over consecutive saves 10 MCS apart, the
#      centroid step d of each cell and the unit major axis e of its site covariance at the
#      earlier save; ratio = Σ (d·e)² / Σ (|d|² − (d·e)²) pooled over cells and steps.
#
# Tiers. SMOKE runs in the PottsModels suite (one thread, about 1.5 min on an idle machine); its rows are
# reduced versions of READY targets, binding at their reduced size. FULL runs with
# POTTS_FULL_REPRODUCTION=true (or REPRO=full) offline on an idle machine (D-146; about 20
# CPU-h, EnsembleThreads), and its outputs are committed to reproductions/data/01/.
#
# | Row | Target (spec 01 §5) | Rule | SMOKE | FULL |
# |---|---|---|---|---|
# | V-E1 | 2006 network at 12 h, coarser at 48 h (Fig. 4) | at 1440 MCS O4 network in ≥ 8/10; mean O3(5760) < mean O3(1440), mean O2(5760) ≥ 0.9; control λ_L = 0: mean O2(1440) ≤ elongated − 0.2 | 200² density-matched (100 cells), 1 seed, 1440 MCS: O4 network; control λ_L = 0 O2 lower by ≥ 0.2 | paper size, n = 10 (+10 controls) |
# | V-E5 | L = 20, 40 µm islands; L ≥ 60 µm network (Fig. 6) | at 5760 MCS (48 h; Fig. 6's time is not stated), O4 per replicate: islands for L ∈ {10, 20} px, network for L ∈ {30, 40, 50} px, each in ≥ 8/10 | — | 5 × 10 runs |
# | V-E6 | J_cc = 20…1 keep the network; J_cc = 1 not more lacunae (Fig. 7) | at 5760 MCS: network in ≥ 8/10 for J_cc ∈ {20, 5, 1}; mean O3(J_cc = 1) ≤ mean O3(J_cc = 40) of V-E1 | — | 3 × 10 runs |
# | V-E10 | elongated cells walk faster along their long axis (Fig. 11) | isolated cells, no chemotaxis: mean O6 > 1.2 (elongated); control L = 10, λ_L = 50 (round, 01a p.50): mean O6 < 1.2 and < elongated | 1000 MCS: 1 seed (elongated), 2 seeds (round) | 2000 MCS, 10 seeds each |
# | V-C1 | 1000 cells: islands without CI, network with CI at 10⁴ MCS (Fig. 2) | O4 network (CI) in ≥ 4/5; no CI: O2 < 0.5 in ≥ 4/5 | — | 2 × 5 runs, 502² |
# | V-C2 | sprout with CI, compact without at 10⁴ MCS (Fig. 4) | mean C(CI) < mean C(no CI) − 0.3 | 1000 MCS, 1 seed: C(CI) < C(no CI) − 0.2 | the V-C3 runs at ratio 0 and 1 |
# | V-C3 | C vs χcc/χcM at 10⁴ MCS (Fig. 5) | low plateau (ratio 0–0.4) 0.35 ± 0.07; high (0.7–1) 0.9 ± 0.07; midpoint in [0.45, 0.65] | — | 11 ratios × 10 |
# | V-C4 | C vs J(c,c) at 5000 MCS (Fig. 7) | ±0.1: CI 0.3 at J_cc 20 and 40, 0.85 at 80; no CI 0.35 at 0, 0.83 at 15, 20, 40; C rises by > 0.3 from the lowest to the highest J_cc in both | — | 11 points × 10 |
# | V-C5 | C vs χ(c,M) at 5000 MCS (Fig. 8) | ±0.1: CI 0.9 / 0.35 / 0.2 at χcM 0 / 500 / 5000; no CI 0.95 / 0.7 at 0 / 5000 | — | 5 points × 10 |
# | V-C7 | C vs s at 5000 MCS (Fig. 9) | CI: midpoint in s ∈ [0.07, 0.15]; no CI: \|C − 0.95\| ≤ 0.1 at s 0, 0.1, 0.25 | — | 11 points × 10 |
# | V-C9 | C vs T at 5000 MCS (Fig. 11) | ext-only C(T = 50) > 0.85; ext-retr C(T = 50) < 0.5; both < 0.3 at T = 800 | 1000 MCS, 1 seed: ext-only − ext-retr > 0.2 at T = 50 | 4 × 10 runs |
# | V-C12 | displacement CI ≈ 85 µm vs no CI ≈ 42 µm over 160 h (Fig. 6E) | O5 from MCS 100 to 19 300: ratio CI/no CI in [1.5, 2.5] | — | 2 × 10 runs |
# | M6 time | — | every 2008 binding value also at N + 100 MCS | — | reported |
#
# PARKED (D-153; not run, listed on the page): V-E2, V-E3, V-E4 (lacunae and branch points
# need the 01a morphometry pipeline, whose pixel scale is unknown: A-18; G12 not built),
# V-E7 (the metric is "not shown"), V-E8 (Figs. 9–10 parameter sets conflict with the files:
# D-14, D-15), V-E9 (speed interval unspecified), V-C6 (cord width undefined), V-C8 (no
# 1024-cell set-up: D-2, A-10), V-C10 and V-C11 (no Fig. 12/13 set-up, 256 cells on 500²
# inferred only: D-2; Fig. 13 bookkeeping D-17). L = 50 vs 60 px stays an author question
# (M2): the V-E rows run the default L = 50.
#
# Negative controls (D-048): V-E1's round control; V-E5's two island lengths against three
# network lengths; V-E10's round control; V-C2/V-C3's no-CI end (ratio 1); V-C9's
# extension-only arm; the observable checks below (a hand-built network, islands, a
# convex blob and a ring each give the classification and C derived by hand).
using Potts, PottsModels, Test
using Statistics: mean, std

const P63D_FULLREPRO = get(ENV, "POTTS_FULL_REPRODUCTION", "false") == "true" || get(ENV, "REPRO", "") == "full"
const P63D_RSOLVER = ExplicitEuler(substeps = 15)

# ---------------------------------------------------------------------------------------------
# Observables
# ---------------------------------------------------------------------------------------------
const P63D_R8 = [(a, b) for a in -1:1 for b in -1:1 if (a, b) != (0, 0)]
const P63D_R4 = [(1, 0), (-1, 0), (0, 1), (0, -1)]

p63d_cross(o, a, b) = (a[1] - o[1]) * (b[2] - o[2]) - (a[2] - o[2]) * (b[1] - o[1])
"""Area of the convex hull of integer points (Andrew's monotone chain, shoelace); 0 for < 3
non-collinear points."""
function p63d_hull_area(pts)
    P = sort(unique(pts))
    length(P) < 3 && return 0.0
    chain(Q) = foldl(Q; init = eltype(Q)[]) do h, q
        while length(h) >= 2 && p63d_cross(h[end - 1], h[end], q) <= 0
            pop!(h)
        end
        push!(h, q)
    end
    h = [chain(P)[1:(end - 1)]; chain(reverse(P))[1:(end - 1)]]
    length(h) < 3 && return 0.0
    return abs(sum(k -> h[k][1] * h[mod1(k + 1, end)][2] - h[mod1(k + 1, end)][1] * h[k][2], eachindex(h))) / 2
end
"""O1: TST compactness (σ: 0 medium, 1 frame, ≥ 2 endothelial)."""
p63d_compactness(σ) = (pts = [(I[1], I[2]) for I in findall(>=(2), σ)]; length(pts) / p63d_hull_area(pts))

function p63d_components(mask, offs)
    X, Y = size(mask)
    lab = zeros(Int, X, Y)
    sizes = Int[]
    stack = Tuple{Int, Int}[]
    for x in 1:X, y in 1:Y
        (mask[x, y] && lab[x, y] == 0) || continue
        push!(sizes, 0)
        k = length(sizes)
        lab[x, y] = k
        push!(stack, (x, y))
        while !isempty(stack)
            i, j = pop!(stack)
            sizes[k] += 1
            for (a, b) in offs
                p, q = i + a, j + b
                (1 <= p <= X && 1 <= q <= Y && mask[p, q] && lab[p, q] == 0) || continue
                lab[p, q] = k
                push!(stack, (p, q))
            end
        end
    end
    return sizes, lab
end
"""O2 and O3."""
function p63d_network(σ)
    occ, _ = p63d_components(σ .>= 2, P63D_R8)
    med, lab = p63d_components(σ .== 0, P63D_R4)
    touch = falses(length(med))
    X, Y = size(σ)
    for x in 1:X, y in 1:Y
        σ[x, y] == 1 || continue
        for (a, b) in P63D_R4
            p, q = x + a, y + b
            (1 <= p <= X && 1 <= q <= Y && lab[p, q] > 0) && (touch[lab[p, q]] = true)
        end
    end
    share = isempty(occ) ? 0.0 : maximum(occ) / sum(occ)
    return (; share, lacunae = count(k -> !touch[k] && med[k] >= 10, eachindex(med)))
end
"""O4."""
p63d_isnetwork(r) = r.share >= 0.9 && r.lacunae >= 3

"""Centroids of cells 2:maximum(σ) (NaN for an empty cell)."""
function p63d_centroids(σ)
    n = Int(maximum(σ))
    sx, sy, m = zeros(n), zeros(n), zeros(Int, n)
    for I in CartesianIndices(σ)
        c = σ[I]
        c >= 2 || continue
        sx[c] += I[1]; sy[c] += I[2]; m[c] += 1
    end
    return [(sx[c] / m[c], sy[c] / m[c]) for c in 2:n]
end
"""O5, in sites (× 2 µm)."""
p63d_displacement(σ0, σ1) = mean(((a, b),) -> hypot(b[1] - a[1], b[2] - a[2]), zip(p63d_centroids(σ0), p63d_centroids(σ1)))
"""O6 over a vector of σ's saved at equal intervals: (Σ par², Σ perp²)."""
function p63d_anisotropy(σs)
    par = perp = 0.0
    for k in 1:(length(σs) - 1)
        a, b = σs[k], σs[k + 1]
        for c in 2:Int(maximum(a))
            A, B = findall(==(c), a), findall(==(c), b)
            (isempty(A) || isempty(B)) && continue
            ma = (mean(I[1] for I in A), mean(I[2] for I in A))
            mb = (mean(I[1] for I in B), mean(I[2] for I in B))
            sxx = mean((I[1] - ma[1])^2 for I in A)
            syy = mean((I[2] - ma[2])^2 for I in A)
            sxy = mean((I[1] - ma[1]) * (I[2] - ma[2]) for I in A)
            λ = (sxx + syy) / 2 + sqrt(((sxx - syy) / 2)^2 + sxy^2)
            e = abs(sxy) > 1e-12 ? (λ - syy, sxy) : (sxx >= syy ? (1.0, 0.0) : (0.0, 1.0))
            e = e ./ hypot(e...)
            d = mb .- ma
            pa = (d[1] * e[1] + d[2] * e[2])^2
            par += pa
            perp += d[1]^2 + d[2]^2 - pa
        end
    end
    return par, perp
end

# ---------------------------------------------------------------------------------------------
# Runs
# ---------------------------------------------------------------------------------------------
"""One 2006 run: final σ's at the save times (MCS)."""
function p63d_run06(seed, saves; lattice = (500, 500), n = 282, p = Pair[])
    op = layout(merks2006_layout(; lattice, n, seed), lattice)
    prob = PottsProblem(Merks2006(; name = :m6, lattice), [op; p...], (0, maximum(saves)); field_solver = P63D_RSOLVER, seed)
    sol = solve(prob, SequentialCPM(); saveat = saves)
    return Dict(Int(t) => Array(u.σ) for (t, u) in zip(sol.t, sol.u))
end
"""One 2008 sprout run (or the paper de novo start): σ's at the save times (MCS)."""
function p63d_run08(seed, saves; p = Pair[], mode = :extension_retraction, denovo = false)
    lattice = denovo ? (502, 502) : (202, 202)
    l = denovo ? merks2008_denovo(; lattice, n = 1000, region = (85:417, 85:417), seed) : merks2008_sprout(; seed)
    op = layout(l, lattice)
    prob = PottsProblem(Merks2008(; name = :m8, lattice, mode), [op; p...], (0, maximum(saves)); field_solver = P63D_RSOLVER, seed)
    sol = solve(prob, SequentialCPM(); saveat = saves)
    return Dict(Int(t) => Array(u.σ) for (t, u) in zip(sol.t, sol.u))
end
"""O6 of isolated cells without chemotaxis (9 cells of 10² over 120² of a framed 160²)."""
function p63d_walk(seed; p = Pair[], tend = 2000)
    G = (160, 160)
    op = layout(merks2006_layout(; lattice = G, region = (120, 120), n = 9, seed), G)
    prob = PottsProblem(Merks2006(; name = :m6, lattice = G), [op; :χcM => 0.0; :χcc => 0.0; p...], (0, tend);
        field_solver = P63D_RSOLVER, seed)
    sol = solve(prob, SequentialCPM(); saveat = 200:10:tend)          # the first 200 MCS relax the squares
    par, perp = p63d_anisotropy([Array(u.σ) for u in sol.u])
    return par / perp
end
# a crossing of y(x) through `level` by linear interpolation, the first one (nothing if none)
function p63d_crossing(xs, ys, level)
    for k in 1:(length(xs) - 1)
        a, b = ys[k] - level, ys[k + 1] - level
        a == 0 && return xs[k]
        a * b < 0 && return xs[k] + (xs[k + 1] - xs[k]) * a / (a - b)
    end
    return nothing
end

# ---------------------------------------------------------------------------------------------
# Observable checks (always): hand-built states with hand-derived values
# ---------------------------------------------------------------------------------------------
@testset "01 observables on hand-built states" begin
    frame(dims) = (σ = zeros(Int32, dims); σ[[1, dims[1]], :] .= 1; σ[:, [1, dims[2]]] .= 1; σ)
    # a filled 10 × 10 square: 100 sites, hull of centres 9 × 9 = 81 → C = 100/81
    σ = frame((20, 20)); σ[5:14, 5:14] .= 2
    @test p63d_compactness(σ) ≈ 100 / 81
    # a plus of two 1-wide bars (cells 2 and 3): hull of centres of {x = 10, y 3:17} ∪ {y = 10, x 3:17}
    # is the diamond with vertices (10,3), (17,10), (10,17), (3,10): area 2·7² = 98; 29 sites
    σ = frame((20, 20)); σ[10, 3:17] .= 2; σ[3:17, 10] .= 3
    @test p63d_compactness(σ) ≈ 29 / 98
    # a ring of cells around a 6 × 6 hole: one component, one lacuna of 36 sites
    σ = frame((20, 20)); σ[5:14, 5:14] .= 2; σ[7:12, 7:12] .= 0
    r = p63d_network(σ)
    @test r.share == 1.0 && r.lacunae == 1 && !p63d_isnetwork(r)
    # three rings joined into a chain (one component, three lacunae ≥ 10): a network
    σ = frame((30, 40))
    for x0 in (3, 13, 23)
        σ[5:14, x0:(x0 + 9)] .= 2; σ[7:12, (x0 + 2):(x0 + 7)] .= 0
    end
    r = p63d_network(σ)
    @test r.share == 1.0 && r.lacunae == 3 && p63d_isnetwork(r)
    # a hole of 9 sites is not a lacuna; medium touching the frame is not one either
    σ = frame((20, 20)); σ[5:14, 5:14] .= 2; σ[8:10, 8:10] .= 0; σ[2:4, :] .= 0
    @test p63d_network(σ).lacunae == 0
    # islands: four separate blocks → largest share 1/4
    σ = frame((30, 30)); σ[3:6, 3:6] .= 2; σ[3:6, 20:23] .= 3; σ[20:23, 3:6] .= 4; σ[20:23, 20:23] .= 5
    @test p63d_network(σ).share == 0.25 && !p63d_isnetwork(p63d_network(σ))
    # displacement: cell 2 moves by (3, 4), cell 3 stays → mean 2.5 sites
    a = frame((20, 20)); a[3:4, 3:4] .= 2; a[10:11, 10:11] .= 3
    b = frame((20, 20)); b[6:7, 7:8] .= 2; b[10:11, 10:11] .= 3
    @test p63d_displacement(a, b) ≈ 2.5
    # anisotropy: a 2 × 6 bar along y stepping 1 along y (parallel) vs along x (perpendicular)
    a = frame((20, 20)); a[5:6, 5:10] .= 2
    b = frame((20, 20)); b[5:6, 6:11] .= 2
    c = frame((20, 20)); c[6:7, 5:10] .= 2
    @test p63d_anisotropy([a, b]) == (1.0, 0.0)
    @test p63d_anisotropy([a, c]) == (0.0, 1.0)
    @test p63d_crossing([0.0, 0.5, 1.0], [0.3, 0.5, 0.9], 0.6) ≈ 0.5 + 0.5 * 0.1 / 0.4
end

# ---------------------------------------------------------------------------------------------
# SMOKE (binding in the suite)
# ---------------------------------------------------------------------------------------------
@testset "01 SMOKE: V-E1 (reduced) — 2006 network at 12 h, density-matched 200²" begin
    # 100 cells of 10² on a framed 200² (≈ the paper's 282·100 / 333²), 1440 MCS = 12 h
    el = [p63d_network(p63d_run06(s, [1440]; lattice = (200, 200), n = 100)[1440]) for s in 90001:90001]
    ro = [p63d_network(p63d_run06(s, [1440]; lattice = (200, 200), n = 100, p = [:λ_L => 0.0])[1440]) for s in 90001:90001]
    @info "01 SMOKE V-E1 (share, lacunae)" el ro
    @test all(p63d_isnetwork, el)
    @test mean(r -> r.share, ro) <= mean(r -> r.share, el) - 0.2               # control: round cells
end

@testset "01 SMOKE: V-C2 / V-C9 (reduced) — the sprout at 1000 MCS" begin
    C(seed; kw...) = p63d_compactness(p63d_run08(seed, [1000]; kw...)[1000])
    ci = [C(s) for s in 90011:90011]
    noci = [C(s; p = [:χcc => 500.0]) for s in 90011:90011]
    eo = [C(s; mode = :extension_only) for s in 90011:90011]
    @info "01 SMOKE V-C2/V-C9 compactness at 1000 MCS" ci noci eo
    @test mean(ci) < mean(noci) - 0.2                                          # V-C2: CI sprouts
    @test mean(eo) - mean(ci) > 0.2                                            # V-C9: retractions matter at T = 50
end

@testset "01 SMOKE: V-E10 (reduced) — elongated cells walk along their long axis" begin
    el = [p63d_walk(s; tend = 1000) for s in 90021:90021]
    ro = [p63d_walk(s; p = [:L => 10.0, :λ_L => 50.0], tend = 1000) for s in 90021:90022]
    @info "01 SMOKE V-E10 anisotropy" el ro
    @test mean(el) > 1.2
    @test mean(ro) < 1.2 && mean(ro) < mean(el)
end

# ---------------------------------------------------------------------------------------------
# FULL (offline; POTTS_FULL_REPRODUCTION=true)
# ---------------------------------------------------------------------------------------------
p63d_tmap(f, xs) = (out = Vector{Any}(undef, length(xs)); Threads.@threads(for i in eachindex(xs)
                                                                             out[i] = f(xs[i])
                                                                         end); out)
if P63D_FULLREPRO

    @testset "01 FULL: V-E1, V-E5, V-E6 (2006, paper size)" begin
        H = [480, 1080, 1440, 2880, 5760]                                      # 4, 9, 12, 24, 48 h
        std_runs = p63d_tmap(s -> p63d_run06(s, H), 1001:1010)
        net(t) = [p63d_network(r[t]) for r in std_runs]
        @test count(p63d_isnetwork, net(1440)) >= 8
        @test mean(r -> r.lacunae, net(5760)) < mean(r -> r.lacunae, net(1440))
        @test mean(r -> r.share, net(5760)) >= 0.9
        round_runs = p63d_tmap(s -> p63d_network(p63d_run06(s, [1440]; p = [:λ_L => 0.0])[1440]), 1101:1110)
        @test mean(r -> r.share, round_runs) <= mean(r -> r.share, net(1440)) - 0.2
        # V-E5: L in px (20, 40, 60, 80, 100 µm)
        for (k, L) in enumerate((10.0, 20.0, 30.0, 40.0, 50.0))
            rs = p63d_tmap(i -> p63d_network(p63d_run06(1200 + 10(k - 1) + i, [5760]; p = [:L => L])[5760]), 1:10)
            nnet = count(p63d_isnetwork, rs)
            @test L <= 20 ? (10 - nnet >= 8) : (nnet >= 8)
        end
        # V-E6: J_cc = 20, 5, 1 (J_cM = 20)
        for (k, Jcc) in enumerate((20.0, 5.0, 1.0))
            J = [0.0 20.0 0.0; 20.0 Jcc 100.0; 0.0 100.0 0.0]
            rs = p63d_tmap(i -> p63d_network(p63d_run06(1300 + 10(k - 1) + i, [5760]; p = [:J => J])[5760]), 1:10)
            @test count(p63d_isnetwork, rs) >= 8
            Jcc == 1.0 && @test mean(r -> r.lacunae, rs) <= mean(r -> r.lacunae, net(5760))
        end
    end

    @testset "01 FULL: V-E10 (isolated cells, no chemotaxis)" begin
        el = p63d_tmap(s -> p63d_walk(s), 1401:1410)
        ro = p63d_tmap(s -> p63d_walk(s; p = [:L => 10.0, :λ_L => 50.0]), 1411:1420)
        @test mean(el) > 1.2
        @test mean(ro) < 1.2 && mean(ro) < mean(el)
    end

    @testset "01 FULL: V-C2, V-C3 (compactness vs χcc/χcM at 10⁴ MCS)" begin
        ratios = 0.0:0.1:1.0
        C = [p63d_tmap(i -> p63d_compactness(p63d_run08(3000 + 100j + i, [10_000, 10_100]; p = [:χcc => 500.0 * r])[10_000]), 1:10)
             for (j, r) in enumerate(ratios)]
        m = mean.(C)
        @test m[1] < m[end] - 0.3                                              # V-C2 (ratio 0 = CI, 1 = no CI)
        low, high = mean(m[1:5]), mean(m[8:11])
        @test abs(low - 0.35) <= 0.07 && abs(high - 0.9) <= 0.07
        mid = p63d_crossing(collect(ratios), m, (low + high) / 2)
        @test mid !== nothing && 0.45 <= mid <= 0.65
    end

    @testset "01 FULL: V-C4, V-C5, V-C7 (compactness at 5000 MCS)" begin
        C(seed; p) = p63d_compactness(p63d_run08(seed, [5000, 5100]; p)[5000])
        Jm(Jcc) = [0.0 20.0 0.0; 20.0 Jcc 100.0; 0.0 100.0 0.0]
        # V-C4: (J_cc, CI?) points
        pts4 = [(0.0, true), (20.0, true), (40.0, true), (60.0, true), (80.0, true),
            (0.0, false), (5.0, false), (10.0, false), (15.0, false), (20.0, false), (40.0, false)]
        m4 = Dict(pt => mean(p63d_tmap(i -> C(4000 + 100k + i; p = [:J => Jm(pt[1]); pt[2] ? Pair[] : [:χcc => 500.0]]), 1:10))
                  for (k, pt) in enumerate(pts4))
        @test abs(m4[(20.0, true)] - 0.3) <= 0.1 && abs(m4[(40.0, true)] - 0.3) <= 0.1 && abs(m4[(80.0, true)] - 0.85) <= 0.1
        @test abs(m4[(0.0, false)] - 0.35) <= 0.1 && all(J -> abs(m4[(J, false)] - 0.83) <= 0.1, (15.0, 20.0, 40.0))
        @test m4[(80.0, true)] - m4[(0.0, true)] > 0.3 && m4[(40.0, false)] - m4[(0.0, false)] > 0.3
        # V-C5: (χcM, CI?) → paper value
        pts5 = [((0.0, true), 0.9), ((500.0, true), 0.35), ((5000.0, true), 0.2), ((0.0, false), 0.95), ((5000.0, false), 0.7)]
        for (k, ((χ, ci), want)) in enumerate(pts5)
            got = mean(p63d_tmap(i -> C(5000 + 100k + i; p = [:χcM => χ; ci ? Pair[] : [:χcc => χ]]), 1:10))
            @test abs(got - want) <= 0.1
        end
        # V-C7: s sweep
        ss = [0.0, 0.025, 0.05, 0.075, 0.1, 0.125, 0.15, 0.175, 0.2, 0.25]
        mci = [mean(p63d_tmap(i -> C(7000 + 100k + i; p = [:s => s]), 1:10)) for (k, s) in enumerate(ss)]
        mid = p63d_crossing(ss, mci, (mci[1] + mci[end]) / 2)
        @test mid !== nothing && 0.07 <= mid <= 0.15
        for (k, s) in enumerate((0.0, 0.1, 0.25))
            @test abs(mean(p63d_tmap(i -> C(7500 + 100k + i; p = [:s => s, :χcc => 500.0]), 1:10)) - 0.95) <= 0.1
        end
    end

    @testset "01 FULL: V-C9 (T and the extension-only mode at 5000 MCS)" begin
        C(seed, T, mode) = p63d_compactness(p63d_run08(seed, [5000, 5100]; p = [:T => T], mode)[5000])
        m = Dict((T, mode) => mean(p63d_tmap(i -> C(9000 + 100k + i, T, mode), 1:10))
                 for (k, (T, mode)) in enumerate(((50.0, :extension_only), (50.0, :extension_retraction),
                                                   (800.0, :extension_only), (800.0, :extension_retraction))))
        @test m[(50.0, :extension_only)] > 0.85
        @test m[(50.0, :extension_retraction)] < 0.5
        @test m[(800.0, :extension_only)] < 0.3 && m[(800.0, :extension_retraction)] < 0.3
    end

    @testset "01 FULL: V-C12 (displacement over 160 h, CI vs no CI)" begin
        D(seed; p) = (r = p63d_run08(seed, [100, 19_300]; p); p63d_displacement(r[100], r[19_300]))
        ci = p63d_tmap(i -> D(12_000 + i; p = Pair[]), 1:10)
        no = p63d_tmap(i -> D(12_100 + i; p = [:χcc => 500.0]), 1:10)
        @test 1.5 <= mean(ci) / mean(no) <= 2.5
    end

    @testset "01 FULL: V-C1 (1000 cells, the paper geometry, 10⁴ MCS)" begin
        ci = p63d_tmap(i -> p63d_network(p63d_run08(20_000 + i, [10_000, 10_100]; denovo = true)[10_000]), 1:5)
        no = p63d_tmap(i -> p63d_network(p63d_run08(20_100 + i, [10_000, 10_100]; denovo = true, p = [:χcc => 500.0])[10_000]), 1:5)
        @test count(p63d_isnetwork, ci) >= 4
        @test count(r -> r.share < 0.5, no) >= 4
    end
end
