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
