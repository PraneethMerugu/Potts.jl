# Merks et al. (2006) parameter set as the defaults of `MerksVasculogenesis` and
# `merks_state` (D-050 M1, M2, M5; maintainer: "Also change defaults tonight").
#
# (a) Pins: the constructor's defaults are the 2006 set in lattice units (2 µm/px, 30 s/MCS;
#     01_merks.md §3.1, §7.8): A = 100, λ = 50, λ_L = 5, L = 50 px ("about 100 µm", D-050 M2),
#     χ = 1000, T = 50, J_cc = 40, J_cM = 20, D = 10⁻¹³ m²/s → 0.75 px²/MCS,
#     α = ε = 1.8·10⁻⁴ s⁻¹ → 5.4·10⁻³ per MCS. `merks_state` seeds 282 squares of 10² (= A)
#     over 333² of 500². The docstring names the paper's field schedule, 15 Euler substeps
#     per MCS (Δt = 2 s, D-050 M5), as the field solver.
#
# (b) Oracle (the paper's Fig. 4 claim: a stable polygonal network): at the paper's cell
#     density (282·100 sites over 333², ≈ 0.25; here 100 cells of 100 sites on 200²) and
#     cell size, after 3000 MCS (25 h) the endothelial sites form one large 8-connected
#     component holding ≥ 90 % of them, enclosing ≥ 3 lacunae (4-connected medium regions of
#     ≥ 10 sites that do not touch the lattice edge). Negative control: the previous
#     defaults (A = 50, λ = 25, L = 30, 7² seeds, 2 field substeps), passed explicitly, with
#     the same cell count, stay in islands: the largest component holds < 70 % per seed and
#     < 50 % on average.
#
#     Thresholds from runs on feffb976 (/tmp/merks06/explore.jl, seeds 1–4, 200², 100 cells):
#       2006 set, largest-component share at MCS 1000/2000/3000/4000: 0.94–0.98 / 0.96–1.0 /
#         0.98–1.0 / 0.98–1.0; lacunae at 3000: 5, 5, 7, 2 (seeds 1–4);
#       old defaults: share 0.17–0.30 / 0.24–0.50 / 0.27–0.45 / 0.23–0.41, 11–28 components.
#     So ≥ 0.9 (vs ≥ 0.98 seen) and < 0.7 per seed / < 0.5 mean (vs ≤ 0.45, mean 0.35) leave
#     margin both ways; ≥ 3 lacunae holds for seeds 1–3 (5, 5, 7), seed 4 is not used.
#     The 500² paper-size run (282 cells, 6000 MCS) is too slow for the suite (about 50 s per
#     4000 MCS at 200² with 15 substeps already).

const M06_M8 = [(a, b) for a in -1:1, b in -1:1 if (a, b) != (0, 0)]
const M06_N4 = [(1, 0), (-1, 0), (0, 1), (0, -1)]

"""Connected components of `mask` under the offsets `offs`: sizes and whether each touches the
lattice edge."""
function m06_components(mask, offs)
    X, Y = size(mask)
    lab = zeros(Int, X, Y); sizes = Int[]; edge = Bool[]; stack = Tuple{Int, Int}[]
    for x in 1:X, y in 1:Y
        (mask[x, y] && lab[x, y] == 0) || continue
        push!(sizes, 0); push!(edge, false); k = length(sizes)
        lab[x, y] = k; push!(stack, (x, y))
        while !isempty(stack)
            i, j = pop!(stack)
            sizes[k] += 1
            (i == 1 || j == 1 || i == X || j == Y) && (edge[k] = true)
            for (a, b) in offs
                p, q = i + a, j + b
                (1 <= p <= X && 1 <= q <= Y && mask[p, q] && lab[p, q] == 0) || continue
                lab[p, q] = k; push!(stack, (p, q))
            end
        end
    end
    return sizes, edge
end

"""Share of endothelial sites in the largest 8-connected component, and the number of
lacunae (4-connected medium regions of ≥ `minhole` sites not touching the edge)."""
function m06_network(σ; minhole = 10)
    occ, _ = m06_components(σ .!= 0, M06_M8)
    med, edge = m06_components(σ .== 0, M06_N4)
    return (; share = maximum(occ) / sum(occ), lacunae = count(i -> !edge[i] && med[i] >= minhole, eachindex(med)))
end

const M06_G = 200          # lattice side
const M06_N = 100          # cells: 100·100 / 200² ≈ 0.25, the paper's 282·100 / 333²
const M06_T = 3000         # MCS

function m06_final(seed; old = false)
    G = (M06_G, M06_G)
    sys, op, solver = if old
        (MerksVasculogenesis(; name = :m, lattice = G, V₀ = 50.0, λ = 25.0, L = 30.0, λ_L = 5.0),
            merks_state(; lattice = G, n = M06_N, side = 7, seed), ExplicitEuler(substeps = 2, lower = 0.0))
    else
        (MerksVasculogenesis(; name = :m, lattice = G), merks_state(; lattice = G, n = M06_N, seed),
            ExplicitEuler(substeps = 15, lower = 0.0))
    end
    prob = PottsProblem(sys, op, (0, M06_T); seed, field_solver = solver)
    return solve(prob, SequentialCPM(); saveat = M06_T).u[end].σ
end

@testset "Merks 2006 defaults: the paper's parameter set" begin
    prob = PottsProblem(MerksVasculogenesis(; name = :m, lattice = (20, 20)), merks_state(; lattice = (20, 20), n = 1),
        (0, 1); field_solver = ExplicitEuler(substeps = 15, lower = 0.0))
    p = prob.p
    @test p.V₀ == 100.0 && p.λ == 50.0
    @test p.λ_L == 5.0 && p.L == 50.0
    @test p.χ == 1000.0 && p.T == 50.0
    @test p.Dc == 0.75 && p.σc == 5.4e-3 && p.δc == 5.4e-3
    @test Matrix(p.J) == [0.0 20.0; 20.0 40.0]
    @test PottsModels.MerksVasculogenesis(; name = :m).lattice.dims == (500, 500)

    op = merks_state()
    σ = op[1].second
    @test size(σ) == (500, 500) && length(op[2].second) == 282 && all(==(:endothelial), op[2].second)
    @test all(c -> count(==(c), σ) == 100, 1:282)                         # 10² squares (= A)
    occupied = findall(!=(0), σ)
    @test all(I -> 84 <= I[1] <= 417 && 84 <= I[2] <= 417, occupied)    # within the central 333²

    doc = string(@doc MerksVasculogenesis)
    @test occursin("ExplicitEuler(substeps = 15, lower = 0.0)", doc)
    @test !occursin("substeps = 2", doc)
end

@testset "Merks 2006 defaults: the network persists; the old defaults fragment" begin
    new = [m06_network(m06_final(s)) for s in 1:3]
    old = [m06_network(m06_final(s; old = true)) for s in 1:3]
    @info "Merks 2006 network (share, lacunae)" new old
    @test all(r -> r.share >= 0.9, new)
    @test all(r -> r.lacunae >= 3, new)
    @test all(r -> r.share < 0.7, old)
    @test sum(r -> r.share, old) / length(old) < 0.5
end
