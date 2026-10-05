# PottsModels.Analysis (P6.2a, D-069): brute-force oracles for every definition, the tie
# order of the NumPy argsort port, and negative controls. The frozen acceptance file
# `acceptance/p6_2a_akeeb_analysis.jl` holds the hand-derived SciPy cases.
using Random: MersenneTwister

const AN = PottsModels.Analysis

# --- independent oracles (definitions, not the SciPy scans) ------------------------------------

# peaks: every maximal run of equal samples [l, r], strictly inside the signal, higher than
# both its neighbours; the peak is its midpoint (l + r) ÷ 2
function oracle_maxima(x)
    out = Int[]
    l = 1
    while l <= length(x)
        r = l
        while r < length(x) && x[r + 1] == x[l]
            r += 1
        end
        l > 1 && r < length(x) && x[l - 1] < x[l] && x[r + 1] < x[l] && push!(out, (l + r) ÷ 2)
        l = r + 1
    end
    return out
end

# prominence: the samples reachable from the peak without passing a higher one, on each
# side; the base is the minimum there, the one nearest the peak on ties
function oracle_prominence(x, p)
    a = p
    while a > 1 && x[a - 1] <= x[p]
        a -= 1
    end
    b = p
    while b < length(x) && x[b + 1] <= x[p]
        b += 1
    end
    lmin, rmin = minimum(x[a:p]), minimum(x[p:b])
    lb = findlast(==(lmin), x[a:p]) + a - 1
    rb = findfirst(==(rmin), x[p:b]) + p - 1
    return x[p] - max(lmin, rmin), lb, rb
end

# width: the last sample at or below the reference height on each side (or the base), then
# the linear crossing between it and its inner neighbour
function oracle_width(x, p, rel)
    prom, lb, rb = oracle_prominence(x, p)
    h = x[p] - prom * rel
    i = something(findlast(j -> x[j] <= h, lb:p), 1) + lb - 1
    j = something(findfirst(k -> x[k] <= h, p:rb), rb - p + 1) + p - 1
    l = x[i] < h ? i + (h - x[i]) / (x[i + 1] - x[i]) : Float64(i)
    r = x[j] < h ? j - (h - x[j]) / (x[j - 1] - x[j]) : Float64(j)
    return r - l, l, r
end

# the distance filter on distinct heights: greedy from the highest peak
function oracle_distance(x, peaks, d)
    keep = Int[]
    for p in peaks[sortperm(x[peaks]; rev = true)]
        all(q -> abs(p - q) >= ceil(d), keep) && push!(keep, p)
    end
    return sort!(keep)
end

randperm_signal(rng, n) = Float64.(sortperm(rand(rng, n)))           # distinct heights

@testset "Analysis: find_peaks against definitional oracles" begin
    rng = MersenneTwister(62)
    for n in [0, 1, 2, 3, 5, 10, 40, 200], rep in 1:40
        x = rand(rng, 0:6, n)                               # many plateaus and ties
        pk = AN.find_peaks(x)
        @test pk == oracle_maxima(x)
        isempty(pk) && continue
        pr = AN.peak_prominences(x, pk)
        @test all(k -> (pr.prominences[k], pr.left_bases[k], pr.right_bases[k]) == oracle_prominence(x, pk[k]), eachindex(pk))
        for rel in (0.25, 0.5, 1.0)
            wd = AN.peak_widths(x, pk; rel_height = rel)
            o = [oracle_width(x, p, rel) for p in pk]
            @test wd.widths ≈ first.(o) && wd.left_ips ≈ getindex.(o, 2) && wd.right_ips ≈ last.(o)
        end
        for pmin in (1, 3), wmin in (1.0, 2.5)
            w = AN.peak_widths(x, pk).widths
            @test AN.find_peaks(x; prominence = pmin) == pk[pr.prominences .>= pmin]
            @test AN.find_peaks(x; width = wmin) == pk[w .>= wmin]
        end
    end
    # the distance filter: distinct heights (no ties) against the greedy definition; with ties
    # its invariants (kept peaks ≥ ceil(d) apart; each removed peak lies within reach of a kept
    # peak at least as high)
    for n in (30, 100, 400), rep in 1:30, d in (1, 2, 3.5, 7)
        x = randperm_signal(rng, n)
        pk = AN.find_peaks(x)
        @test AN.find_peaks(x; distance = d) == oracle_distance(x, pk, d)
        y = rand(rng, 0:3, n)
        kept = AN.find_peaks(y; distance = d)
        @test all(>=(ceil(d)), diff(kept))
        @test all(p -> p in kept || any(q -> abs(p - q) < ceil(d) && y[q] >= y[p], kept), AN.find_peaks(y))
    end
    # negative control: the oracle notices a wrong tie rule (leftmost plateau sample)
    @test oracle_maxima([0, 2, 2, 2, 2, 0]) == [3] != [2]
    @test_throws ArgumentError AN.peak_prominences([1, 2, 1], [4])
    @test_throws ArgumentError AN.find_peaks([1 2; 3 4])
end
@testset "Analysis: the NumPy argsort port and its tie order" begin
    rng = MersenneTwister(2026)
    for n in [0:40; 100; 1000], rep in 1:20
        v = Float64.(rand(rng, 1:3, n))
        t = AN._np_argsort(v)
        @test sort(t) == 1:n && issorted(v[t])
    end
    # ≤ 16 elements: insertion sort, stable (equal keys keep their order)
    @test AN._np_argsort(ones(16)) == 1:16
    @test AN._np_argsort([2.0, 1, 2, 1, 2]) == [2, 4, 1, 3, 5]
    # NaN sorts last (DOUBLE_LT)
    @test AN._np_argsort([NaN, 1.0, 0.0]) == [3, 2, 1]
    # heapsort fallback, by hand: five equal keys. Heapify moves nothing (no key is strictly
    # larger); each extraction swaps the root to the end and sifts nothing: [5,2,3,4,1] →
    # [4,2,3,5,1] → [3,2,4,5,1] → [2,3,4,5,1].
    @test AN._np_aheapsort!(collect(1:5), ones(5), 1, 5) == [2, 3, 4, 5, 1]
    # An organ pipe [1:89; 89:-1:1] exhausts the introsort depth budget (2⌊log₂ 178⌋ = 14)
    # and reaches the heapsort fallback. Each value occurs twice (at k and 179 − k); below
    # are the values whose right copy comes first, cross-checked against an independent
    # literal transcription of NumPy 1.21 `aquicksort_double` (P6.2a dispatch). A stable
    # sort would put every left copy first.
    v = Float64.([1:89; 89:-1:1])
    t = AN._np_argsort(v)
    @test issorted(v[t])
    @test [k for k in 1:89 if t[2k - 1] != k] ==
          [2, 5, 6, 7, 8, 9, 12, 15, 16, 17, 18, 19, 22, 23, 24, 26, 28, 29, 30, 31, 33, 38, 47, 49, 51, 52, 53,
        54, 55, 57, 58, 59, 60, 62, 64, 65, 66, 67, 69, 72, 76, 77, 79, 80, 81, 83, 85, 87, 89]
    @test t != sortperm(v)                                   # negative control: not stable
end

@testset "Analysis: merge_peaks, column_tops and trapz" begin
    rng = MersenneTwister(3)
    for rep in 1:50
        pk = sort!(unique(rand(rng, 1:300, 20)))
        m = AN.merge_peaks(pk, 15)
        @test first(m) == first(pk) && all(>(15), diff(m)) && issubset(m, pk)
        # every dropped peak is within 15 of the last kept peak before it
        @test all(p -> p in m || p - maximum(filter(<(p), m)) <= 15, pk)
    end
    σ = rand(rng, 0:4, 9, 7)
    pred = isodd
    @test AN.column_tops(pred, σ) == [maximum((y for y in 1:7 if σ[x, y] != 0 && pred(σ[x, y])); init = 0) for x in 1:9]
    @test AN.column_tops(σ) == [maximum((y for y in 1:7 if σ[x, y] != 0); init = 0) for x in 1:9]
    @test AN.column_tops(zeros(Int, 3, 2)) == [0, 0, 0]
    # trapz is exact for piecewise-linear data on uneven samples: ∫₀⁵ (2t + 1) dt = 30
    xs = [0, 0.5, 2, 3.25, 5]
    @test AN.trapz(xs, 2 .* xs .+ 1) == 30
    @test AN.trapz(1:4, [1, 1, 1, 1]) == 3.0
    @test_throws ArgumentError AN.trapz(1:3, 1:2)
end

# Brute-force contact graph: every pair of lattice-neighbour sites, per axis wrap.
function oracle_graph(σ, per, offs)
    n = maximum(σ; init = 0)
    g = [Set{Int}() for _ in 1:n]
    for i in CartesianIndices(σ), o in offs
        j = Tuple(i) .+ o
        all(d -> per[d] || 1 <= j[d] <= size(σ, d), 1:ndims(σ)) || continue
        j = map((x, m) -> mod1(x, m), j, size(σ))
        a, b = σ[i], σ[j...]
        a != 0 && b != 0 && a != b && push!(g[a], b)
    end
    return [sort!(collect(s)) for s in g]
end
const VN4 = [(1, 0), (-1, 0), (0, 1), (0, -1)]
const MOORE8 = [(a, b) for a in -1:1 for b in -1:1 if (a, b) != (0, 0)]

@testset "Analysis: cell_graph, reachable, components and centroids against brute force" begin
    rng = MersenneTwister(7)
    for rep in 1:20, per in ((false, false), (true, false), (true, true))
        σ = rand(rng, 0:12, 11, 8)
        @test AN.cell_graph(σ; periodic = per) == oracle_graph(σ, per, VN4)
        @test AN.cell_graph(σ; periodic = per, neighborhood = Moore(1)) == oracle_graph(σ, per, MOORE8)
    end
    # 3D, von Neumann
    σ3 = rand(rng, 0:6, 4, 4, 4)
    vn6 = [ntuple(k -> k == d ? s : 0, 3) for d in 1:3 for s in (-1, 1)]
    @test AN.cell_graph(σ3) == oracle_graph(σ3, (false, false, false), vn6)
    # hex (axial): the neighbours are (±1, 0), (0, ±1), (1, −1), (−1, 1); (1, 1) is not one
    hexσ = [0 0 0; 0 1 0; 0 0 2]                            # 1 at (2, 2), 2 at (3, 3): axial (1, 1) apart
    hex = Lattice((3, 3); boundary = Closed(), geometry = Hexagonal())
    @test AN.cell_graph(hexσ, hex; neighborhood = Hex(1)) == [Int[], Int[]]
    @test AN.cell_graph(hexσ; neighborhood = Moore(1)) == [[2], [1]]      # control: Moore sees it
    hexσ2 = [0 0 0; 0 1 0; 0 2 0]                           # (2, 2) and (3, 2): axial (1, 0)
    @test AN.cell_graph(hexσ2, hex; neighborhood = Hex(1)) == [[2], [1]]
    @test_throws ArgumentError AN.cell_graph(σ3; periodic = (true, false))

    # reachable and components against a union–find over the induced edges
    for rep in 1:30
        σ = rand(rng, 0:30, 12, 12)
        g = AN.cell_graph(σ)
        cells = sort!(unique(rand(rng, 1:30, 18)))
        parent = collect(1:30)
        root(c) = parent[c] == c ? c : (parent[c] = root(parent[c]))
        for a in cells, b in g[a]
            b in cells && (parent[root(a)] = root(b))
        end
        groups = sort!([sort!(filter(c -> root(c) == r, cells)) for r in unique(root.(cells))]; by = first)
        @test AN.components(g, cells) == groups
        s = rand(rng, 1:30)
        full = AN.components(g, 1:30)
        @test AN.reachable(g, [s]) == only(filter(c -> s in c, full))
        @test AN.reachable(g, [s, s]) == AN.reachable(g, [s])
    end
    @test AN.components([Int[], Int[]], Int[]) == Vector{Int}[]

    σ = rand(rng, 0:5, 7, 6)
    σ[σ .== 3] .= 0                                          # id 3 owns no site
    com = AN.centroids(σ)
    for c in (1, 2, 4, 5)
        s = findall(==(c), σ)
        @test com[c][1] ≈ sum(i -> i[1], s) / length(s) && com[c][2] ≈ sum(i -> i[2], s) / length(s)
    end
    @test all(isnan, com[3])
end

@testset "Analysis: cell_graph on a 500 × 300 state" begin
    σ = zeros(Int32, 500, 300)
    k = 0
    for y in 1:3:120, x in 1:3:498
        σ[x:(x + 2), y:(y + 2)] .= (k += 1)
    end
    AN.cell_graph(σ[1:30, 1:30]; periodic = (true, false))
    bytes = @allocated g = AN.cell_graph(σ; periodic = (true, false))
    @test length(g) == k && all(c -> length(g[c]) <= 4, 1:k)
    @test bytes < 50 * 2^20                                  # ~2 MB measured; no per-site allocation
end

@testset "akeeb_observables reads kinds only of ids that own sites" begin
    # 6 × 5: follower 1 at (3, 2) is the main tumour; leader 3 at (5, 4) is alone above it;
    # id 2 owns no site, so its kind (here not a leader or follower) is never read
    σ = zeros(Int, 6, 5)
    σ[3, 2] = 1
    σ[5, 4] = 3
    o = akeeb_observables(σ, [:follower, :medium, :leader])
    @test (o.singles, o.detached, o.clusters, o.fingers) == (1, 1, 0, 0)
    @test o.invasive === 0.0 && o.infiltrative === 0.0         # one kept column (x = 3)
    # negative control: once id 2 owns a site its kind is checked
    σ[2, 4] = 2
    @test_throws ArgumentError akeeb_observables(σ, [:follower, :medium, :leader])
end
