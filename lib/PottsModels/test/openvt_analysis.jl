# OpenVT monolayer analysis (P6.15d, D-149): behaviour outside the frozen acceptance file
# `acceptance/p6_15d_openvt_analysis.jl`. The spatial grids of `concave_hull` are checked
# against a brute-force concaveman that scans every point and edge with the same kernels.
using Random: MersenneTwister

const OVT_AN = PottsModels.Analysis

# brute-force concaveman on the Graham output: every live point and every edge examined
function ovt_brute_hull(points; concavity = 2.0)
    pts = NTuple{2, Float64}[(Float64(p[1]), Float64(p[2])) for p in points]
    hull = OVT_AN._graham_hull!(pts)
    length(hull) == length(pts) && return pts[hull]
    alive = [all(h -> pts[h] != p, hull) for p in pts]
    P = pts[hull]
    n = length(P)
    nxt = [mod1(e + 1, n) for e in 1:n]
    prv = [mod1(e - 1, n) for e in 1:n]
    function clear(a, b)
        xl, xh, yl, yh = min(a[1], b[1]), max(a[1], b[1]), min(a[2], b[2]), max(a[2], b[2])
        for e in eachindex(P)
            nxt[e] == 0 && continue
            p, q = P[e], P[nxt[e]]
            (min(p[1], q[1]) > xh || max(p[1], q[1]) < xl || min(p[2], q[2]) > yh || max(p[2], q[2]) < yl) && continue
            OVT_AN._intersects(p, q, a, b) && return false
        end
        return true
    end
    queue = collect(1:n)
    k = 1
    while k <= length(queue)
        e = queue[k]
        k += 1
        a, b, c, d = P[prv[e]], P[e], P[nxt[e]], P[nxt[nxt[e]]]
        maxsq = OVT_AN._sqdist(b, c) / (concavity * concavity)
        cands = sort!([(OVT_AN._sqsegdist(pts[i], b, c), i) for i in eachindex(pts) if alive[i]])
        filter!(t -> !(t[1] > maxsq), cands)
        i = findfirst(t -> t[1] < OVT_AN._sqsegdist(pts[t[2]], a, b) && t[1] < OVT_AN._sqsegdist(pts[t[2]], c, d) &&
            clear(b, pts[t[2]]) && clear(c, pts[t[2]]), cands)
        i === nothing && continue
        p = pts[cands[i][2]]
        min(OVT_AN._sqdist(p, b), OVT_AN._sqdist(p, c)) <= maxsq || continue
        push!(P, p)
        push!(nxt, nxt[e])
        push!(prv, e)
        prv[nxt[e]] = length(P)
        nxt[e] = length(P)
        push!(queue, e, length(P))
        alive .&= (pts .!= Ref(p))
    end
    out = NTuple{2, Float64}[]
    e = nxt[n]
    while true
        push!(out, P[e])
        e == n && break
        e = nxt[e]
    end
    return out
end

@testset "OpenVT analysis: concave_hull's grids find what a full scan finds" begin
    rng = MersenneTwister(15)
    clouds = Vector{NTuple{2, Float64}}[]
    for n in (6, 40, 300)
        push!(clouds, [(50rand(rng), 20rand(rng)) for _ in 1:n])                                  # uniform, flat box
        push!(clouds, [(θ = 2π * rand(rng); r = 9sqrt(rand(rng)) * (1 + 0.4sin(5θ)); (r * cos(θ), r * sin(θ))) for _ in 1:n])  # ragged
        push!(clouds, [(1.0e6 + rand(rng), -3.0 + 1.0e-3 * rand(rng)) for _ in 1:n])              # offset, thin
    end
    for pts in clouds, concavity in (1.0, 1.5, 3.0)
        @test OVT_AN.concave_hull(pts; concavity) == ovt_brute_hull(pts; concavity)
    end
    # the boundary is a subset of the input, holds the convex hull and has no repeated vertex
    pts = clouds[5]
    h = OVT_AN.concave_hull(pts; concavity = 1.5)
    @test issubset(h, pts) && allunique(h) && issubset(OVT_AN.concave_hull(pts; concavity = Inf), h)
    # negative control: a smaller concavity carves more
    @test length(OVT_AN.concave_hull(pts; concavity = 1.0)) > length(OVT_AN.concave_hull(pts; concavity = 3.0))
end

@testset "OpenVT analysis: invalid input" begin
    @test_throws ArgumentError openvt_metrics(Float64[], Float64[], Int[])
    @test_throws DimensionMismatch openvt_metrics([1.0, 2.0], [1.0], [1])
    mktempdir() do dir
        path = joinpath(dir, "empty.csv")
        write(path, "x,y,g,n\n")
        @test_throws ArgumentError openvt_metrics(path)
        write(path, "x,y,g,n\n1,2,zz,3\n")
        @test_throws ArgumentError openvt_metrics(path)
    end
    @test_throws ArgumentError OVT_AN.concave_hull([(0.0, 0.0), (1.0, 0.0), (0.0, 1.0)]; concavity = 0)
    @test_throws ArgumentError OVT_AN.concave_hull([(0.0, 0.0), (1.0, 0.0), (0.0, 1.0)]; length_threshold = -1)
    @test_throws ArgumentError OVT_AN.concave_hull([(0.0, 0.0), (NaN, 0.0)])
    @test_throws ArgumentError openvt_inhibition_fractions(Int[])
    @test_throws ArgumentError openvt_neighbor_histogram([2, -1])
    @test_throws ArgumentError openvt_filename(:O4)
    @test_throws ArgumentError write_openvt(IOBuffer(), :O5, (x_pos = [1.0], y_pos = [1.0], radius_i = [1.0], inhibited = [2]))
    # a failed write leaves no file behind
    mktempdir() do dir
        path = joinpath(dir, "o1.csv")
        @test_throws ArgumentError write_openvt(path, :O1, (x = [1.0], y = [1.0], i = [7], n = [1]))
        @test !isfile(path)
    end
end

# ── D12: the Graham order is a strict weak ordering ────────────────────────────────────────

@testset "OpenVT analysis: points collinear with p₀ give one strictly convex hull (D12)" begin
    # seven points on one ray from p₀, exactly collinear in Float64 (the steps are exact
    # multiples of 2⁻¹⁰ on top of a full-precision start), plus two corners
    X, Y = 1234.567890123, 987.654321987
    ray = [(X + k * (3 / 1024), Y + k * (5 / 1024)) for k in 0:6]
    P = [ray; (X + 0.0625, Y); (X + 0.0625, Y + 0.0390625)]
    @test all(OVT_AN._orientation_exact(ray[1], ray[i], ray[j]) == 0 for i in 2:7, j in 2:7)
    # metrics.cpp's orientation on this ray is rounding noise, and not antisymmetric
    cpp_orient(a, b, c) = a[1] * (b[2] - c[2]) + b[1] * (c[2] - a[2]) + c[1] * (a[2] - b[2])
    @test any(cpp_orient(ray[1], ray[i], ray[j]) != -cpp_orient(ray[1], ray[j], ray[i]) for i in 2:7, j in 2:7)
    # p₀, the far end of the ray, the two corners: strictly convex, whatever the input order
    want = [ray[1], ray[7], P[9], P[8]]
    for perm in (1:9, 9:-1:1, [6, 7, 8, 3, 9, 1, 4, 2, 5], [2, 4, 6, 8, 1, 3, 5, 7, 9])
        @test OVT_AN.concave_hull(P[perm]; concavity = Inf) == want
    end
    # negative control: metrics.cpp's comparator and scan, with Julia's stable sort, keep an
    # interior ray point on the "convex" hull for the third order above
    function cpp_graham(q)
        q = copy(q)
        p0 = q[argmin([(p[2], p[1]) for p in q])]
        o(a, b, c) = (v = cpp_orient(a, b, c); v < 0 ? -1 : v > 0 ? 1 : 0)
        d2(a) = (p0[1] - a[1]) * (p0[1] - a[1]) + (p0[2] - a[2]) * (p0[2] - a[2])
        sort!(q; lt = (a, b) -> (s = o(p0, a, b); s == 0 ? d2(a) < d2(b) : s < 0))
        h = Int[]
        for i in eachindex(q)
            while length(h) > 1 && !(o(q[h[end - 1]], q[h[end]], q[i]) < 0)
                pop!(h)
            end
            push!(h, i)
        end
        return length(h)
    end
    @test cpp_graham(P[[6, 7, 8, 3, 9, 1, 4, 2, 5]]) == 5
    # integer rays from p₀ (exact arithmetic either way): nearer points on a hull ray dropped
    sq = [(0.0, 0.0), (0.0, 1.0), (0.0, 2.0), (0.0, 3.0), (1.0, 0.0), (2.0, 0.0), (3.0, 0.0), (3.0, 3.0), (1.0, 1.0), (2.0, 2.0)]
    for q in (sq, reverse(sq))
        @test OVT_AN.concave_hull(q; concavity = Inf) == [(0.0, 0.0), (0.0, 3.0), (3.0, 3.0), (3.0, 0.0)]
    end
end

# ── D13: the candidate search does not prune ───────────────────────────────────────────────

# A 37-point jittered lattice (P6.15d review, minimised from a fuzz failure). At concavity
# 1.5, metrics.cpp's concaveman (R-tree, node size 32) returns 30 vertices: its box distance
# over-estimates next to the near-vertical edges and the search never reaches point 23
# (≈ (5, 1)). The same C++ with box pruning disabled returns the 31 vertices below, as here.
const OVT_LATTICE37 = [
    (1.0000002084006556, 0.9999999128868909), (0.9999999051942863, 2.0000000159682174),
    (0.9999999644961459, 5.000000075441719), (1.9999999541256472, 1.0000000558799673),
    (2.0000000265588174, 2.0000001630084294), (1.9999999674297495, 3.0000000949042938),
    (1.9999999598747447, 3.9999999863099465), (2.00000001499794, 5.000000148553812),
    (3.000000041021583, 0.9999997849656583), (2.9999999773655923, 1.9999998390447076),
    (3.00000007253542, 2.9999999630765717), (3.0000001137281673, 15.000000041426468),
    (4.000000230919902, 1.000000016721847), (3.9999999750730435, 6.999999864095429),
    (4.000000176834082, 7.999999877839823), (3.9999999601848577, 8.999999962887184),
    (4.000000123212885, 9.999999854855812), (3.9999999685072565, 10.999999962075872),
    (3.999999814258214, 12.000000106289686), (4.00000032199259, 13.00000002980112),
    (3.9999998797096796, 14.00000004756452), (4.000000105860022, 15.000000054130133),
    (5.0000000235342, 0.9999999643747605), (5.000000019604974, 2.000000039248345),
    (4.999999991723065, 9.000000004254593), (8.000000073321878, 11.999999986818175),
    (7.9999999105863875, 12.999999978325796), (8.000000236696405, 14.00000017761535),
    (8.999999951392422, 1.0000000600982144), (8.99999996753795, 2.0000000646309695),
    (9.000000148083775, 3.0000000127652857), (8.999999892657957, 3.999999998862443),
    (8.999999886910114, 9.999999949604955), (9.000000191275774, 10.999999993784279),
    (8.999999928899188, 11.999999988892442), (9.00000003611196, 12.999999879468831),
    (10.000000168050136, 0.9999999586705186),
]
# the unpruned C++ answer, as indices into OVT_LATTICE37 (computed with `hullh_nobox`, the
# reference concaveman without box pruning, and by this port)
const OVT_LATTICE37_HULL = [29, 30, 24, 23, 13, 9, 4, 1, 2, 6, 7, 3, 8, 14, 15, 16, 17, 18, 19, 20, 12, 22,
    21, 28, 36, 35, 34, 33, 32, 31, 37]

@testset "OpenVT analysis: no pruning error next to near-parallel edges (D13)" begin
    h = OVT_AN.concave_hull(OVT_LATTICE37; concavity = 1.5)
    @test h == OVT_LATTICE37[OVT_LATTICE37_HULL]
    @test h == ovt_brute_hull(OVT_LATTICE37; concavity = 1.5)
    # the pruned C++ answer lacks point 23; it is a valid candidate here
    @test OVT_LATTICE37[23] in h
end

# ── D12 on a consortium frame (gated: OPENVT_MONOLAYER_REPO, never copied into git) ─────────

@testset "OpenVT analysis: Artistoo frame 1656 (D12; OPENVT_MONOLAYER_REPO)" begin
    repo = get(ENV, "OPENVT_MONOLAYER_REPO", "")
    zipf = joinpath(repo, "results", "Artistoo", "Monolayer", "Type 1", "Centroid_data.zip")
    if isempty(repo) || !isfile(zipf) || Sys.which("unzip") === nothing
        @test_broken !isempty(repo) && isfile(zipf)
    else
        mktempdir() do tmp
            run(`unzip -q -j $zipf Centroid_data/centroids_neighbors_mcs_1656.csv -d $tmp`)
            path = joinpath(tmp, "centroids_neighbors_mcs_1656.csv")
            lines = filter(!isempty, readlines(path))
            names = split(lines[1], ',')
            # Artistoo's header is cell_id,x,y,active,neighbors: g is `active`
            ix, iy, ia = (findlast(==(c), names) for c in ("x", "y", "active"))
            rows = [split(l, ',') for l in lines[2:end]]
            x, y = [parse(Float64, r[ix]) for r in rows], [parse(Float64, r[iy]) for r in rows]
            g = [parse(Int, r[ia]) for r in rows]
            pts = collect(zip(x, y))
            # metrics.cpp (libc++) gives a 74-vertex convex hull; a stable sort with its
            # comparator gave 85 and w_rel 0.44
            @test length(OVT_AN.concave_hull(pts; concavity = Inf)) == 74
            m = openvt_metrics(x, y, g)
            @test m.w_rel ≈ 0.0155 atol = 1e-4
            @test openvt_metrics_line(m) == "10002,261.993,215834,1798.96,4.06557,0.203659,1.09234,0.0155179\n"
        end
    end
end

@testset "OpenVT analysis: reader edge cases" begin
    mktempdir() do dir
        path = joinpath(dir, "f.csv")
        write(path, "x,y,g,n\n1e500,2,1,3\n0,0,1,1\n1,0,0,1\n")
        @test_throws ArgumentError openvt_metrics(path)
        # CRLF line ends and stod-prefix fields
        write(path, "x,y,g,n\r\n0,0,1,3\r\n1,0,0x,5\r\n1,1abc,1.0,5\r\n0,1,1,6\r\n")
        @test openvt_metrics_line(openvt_metrics(path)) == "4,0.707107,1,4,0,0.75,1.12838,0\n"
    end
    @test_throws ArgumentError openvt_metrics([0.0, 1.0, 0.0], [0.0, 0.0, 1.0], [1, 0.5, 1])
    @test_throws ArgumentError openvt_neighbor_histogram(Int[])
end
