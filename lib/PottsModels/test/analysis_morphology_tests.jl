# PottsModels.Analysis: skeletons, percolation, pair graphs, sprouts and lineage trees.
# Each helper is checked against hand-built shapes with known answers or a brute-force
# oracle, with a negative control.

@testitem "Analysis: skeleton graph of hand-built skeletons" setup = [
    AnalysisSetup,
] tags = [
    :pottsmodels, :core,
] begin
    canvas() = falses(15, 15)
    # a plus: 4 tips, 1 junction, 4 branches of length 3
    plus = canvas()
    plus[8, 5:11] .= true
    plus[5:11, 8] .= true
    g = AN.skeleton_graph(plus)
    @test length(g.nodes) == 5 && sort(g.degree) == [1, 1, 1, 1, 4]
    @test all(e -> e[3] ≈ 3, g.edges) && g.loops == 0
    @test AN.skeleton_counts(plus) == (; tips = 4, junctions = 1, branches = 4, loops = 0)
    # min_length drops short branches: negative control on the same shape
    @test AN.skeleton_counts(plus; min_length = 3.5).branches == 0
    # a closed square ring: one self-loop, perimeter 16
    ring = canvas()
    ring[3:7, 3:7] .= true
    ring[4:6, 4:6] .= false
    g = AN.skeleton_graph(ring)
    @test (length(g.nodes), length(g.edges), g.loops) == (1, 1, 1)
    @test only(g.edges)[3] ≈ 16
    # the ring with a tail: one junction, one tip, one branch and the loop
    tail = copy(ring)
    tail[5, 8:12] .= true
    @test AN.skeleton_counts(tail) == (; tips = 1, junctions = 1, branches = 1, loops = 1)
    # theta: the ring with a middle bar holds two loops
    theta = copy(ring)
    theta[5, 4:6] .= true
    @test AN.skeleton_counts(theta).loops == 2
    # a diagonal line: m-adjacency counts each step once (length 4√2, no junction)
    diag = canvas()
    for k in 0:4
        diag[3 + k, 3 + k] = true
    end
    g = AN.skeleton_graph(diag)
    @test length(g.nodes) == 2 && only(g.edges)[3] ≈ 4 * sqrt(2)
    # negative controls: a straight line has no junction, branch or loop; an empty mask no
    # node; an isolated site is one node of degree 0
    line = canvas()
    line[8, 2:14] .= true
    @test AN.skeleton_counts(line) == (; tips = 2, junctions = 0, branches = 0, loops = 0)
    @test isempty(AN.skeleton_graph(canvas()).nodes)
    dot = canvas()
    dot[4, 4] = true
    @test AN.skeleton_graph(dot).degree == [0]
    # two separate rings: components enter the loop count
    two = falses(15, 30)
    two[:, 1:15] .= ring
    two[:, 16:30] .= ring
    @test AN.skeleton_graph(two).loops == 2
end

@testitem "Analysis: skeletonize keeps topology" setup = [AnalysisSetup] tags = [
    :pottsmodels, :core,
] begin
    disk(r; c = 20) = [hypot(i - c, j - c) <= r for i in 1:40, j in 1:40]
    annulus = disk(14) .& .!disk(9)
    # a thick ring thins to one loop; the filled disk (negative control) to none
    @test AN.skeleton_counts(AN.skeletonize(annulus)).loops == 1
    @test AN.skeleton_counts(AN.skeletonize(disk(12))).loops == 0
    # a thick plus thins to four tips around one junction
    tp = falses(31, 31)
    tp[14:18, 3:29] .= true
    tp[3:29, 14:18] .= true
    @test AN.skeleton_counts(AN.skeletonize(tp)) ==
        (; tips = 4, junctions = 1, branches = 4, loops = 0)
    # properties: the skeleton lies inside the mask, is one site wide (no 2 × 2 block), and
    # has as many 8-connected components as the mask
    function ncomp8(m)
        lab = zeros(Int, size(m))
        k = 0
        for x in CartesianIndices(m)
            (m[x] && lab[x] == 0) || continue
            k += 1
            stack = [x]
            lab[x] = k
            while !isempty(stack)
                y = pop!(stack)
                for o in CartesianIndices((-1:1, -1:1))
                    z = y + o
                    checkbounds(Bool, m, z) && m[z] && lab[z] == 0 || continue
                    lab[z] = k
                    push!(stack, z)
                end
            end
        end
        return k
    end
    shapes = (annulus, disk(12), tp, disk(5; c = 10) .| disk(5; c = 30))
    for m in shapes
        s = AN.skeletonize(m)
        @test all(m[s])
        @test !any(all(s[i:(i + 1), j:(j + 1)]) for i in 1:(size(s, 1) - 1), j in 1:(size(s, 2) - 1))
        @test ncomp8(s) == ncomp8(m)
    end
end

@testitem "Analysis: spanning clusters against a flood-fill oracle" setup = [
    AnalysisSetup,
] tags = [
    :pottsmodels, :core,
] begin
    # oracle: grow the set reachable from the first slice by repeated dilation within the
    # mask, then keep the clusters that reach the last slice
    function oracle(m, axis, offs)
        reach = falses(size(m))
        for x in CartesianIndices(m)
            x[axis] == 1 && m[x] && (reach[x] = true)
        end
        changed = true
        while changed
            changed = false
            for x in CartesianIndices(m), o in offs
                y = x + o
                (reach[x] && checkbounds(Bool, m, y) && m[y] && !reach[y]) || continue
                reach[y] = true
                changed = true
            end
        end
        # clusters touching the first slice that reach the last
        out = falses(size(m))
        for x in CartesianIndices(m)
            (reach[x] && x[axis] == size(m, axis)) || continue
            # the cluster of x within reach
            stack = [x]
            out[x] = true
            while !isempty(stack)
                y = pop!(stack)
                for o in offs
                    z = y + o
                    (checkbounds(Bool, m, z) && reach[z] && !out[z]) || continue
                    out[z] = true
                    push!(stack, z)
                end
            end
        end
        return out
    end
    face = [CartesianIndex(1, 0), CartesianIndex(-1, 0), CartesianIndex(0, 1), CartesianIndex(0, -1)]
    full = [o for o in CartesianIndices((-1:1, -1:1)) if o != CartesianIndex(0, 0)]
    rng = MersenneTwister(7)
    for p in (0.4, 0.55, 0.7), rep in 1:10, axis in (1, 2)
        m = rand(rng, 12, 15) .< p
        @test AN.spanning_cluster(m; axis) == oracle(m, axis, face)
        @test AN.spanning_cluster(m; axis, adjacency = :full) == oracle(m, axis, full)
    end
    # a diagonal staircase spans only with corner neighbors (negative control: :face)
    stair = Bool[1 0 0 0; 0 1 0 0; 0 0 1 0; 0 0 0 1]
    @test AN.percolates(stair; axis = 2, adjacency = :full)
    @test !AN.percolates(stair; axis = 2)
    # a path that spans axis 2 only through the periodic seam of axis 1
    seam = falses(6, 4)
    seam[1, 1:2] .= true
    seam[6, 2:4] .= true
    @test !AN.percolates(seam; axis = 2)
    @test AN.percolates(seam; axis = 2, periodic = (true, false))
    # on an ownership array, through a predicate
    σ = [1 1 0 2; 0 1 1 1; 3 0 0 1]
    @test AN.spanning_cluster(in((1, 2)), σ; axis = 2) == (σ .∈ Ref((1, 2)))
    @test !AN.percolates(==(3), σ; axis = 2)
    # bad arguments are typed errors
    @test_throws ArgumentError AN.spanning_cluster(seam; axis = 1, periodic = true)
    @test_throws ArgumentError AN.spanning_cluster(seam; axis = 3)
    @test_throws ArgumentError AN.spanning_cluster(seam; adjacency = :corner)
end

@testitem "Analysis: pair graph clusters" setup = [AnalysisSetup] tags = [
    :pottsmodels, :core,
] begin
    # points in 2D; a pair is linked when close and aligned: the clusters are the transitive
    # closure, so a chain of close pairs forms one cluster
    pos = [(0.0, 0.0), (1.5, 0.0), (3.0, 0.0), (10.0, 0.0), (11.0, 0.0), (20.0, 0.0)]
    dir = [0.0, 0.1, 0.0, 0.0, π / 2, 0.0]
    near(i, j) = hypot((pos[i] .- pos[j])...) < 2
    aligned(i, j) = abs(dir[i] - dir[j]) < π / 4
    g = AN.pair_graph((i, j) -> near(i, j) && aligned(i, j), 6)
    @test g[1] == [2] && g[2] == [1, 3]
    @test AN.components(g, 1:6) == [[1, 2, 3], [4], [5], [6]]
    # without the alignment test, 4 and 5 join
    @test AN.components(AN.pair_graph(near, 6), 1:6) == [[1, 2, 3], [4, 5], [6]]
    # negative control: a predicate that never holds leaves singletons
    @test AN.components(AN.pair_graph((i, j) -> false, 4), 1:4) == [[1], [2], [3], [4]]
    @test AN.pair_graph((i, j) -> true, 0) == Vector{Int}[]
    @test_throws TypeError AN.pair_graph((i, j) -> 1, 2)
    @test_throws ArgumentError AN.pair_graph((i, j) -> true, -1)
end

@testitem "Analysis: sprout length and thickness" setup = [AnalysisSetup] tags = [
    :pottsmodels, :core,
] begin
    # a base of 5 rows, then sprouts of width 2 (to row 12) and 3 (to row 9)
    m = falses(20, 16)
    m[1:5, :] .= true
    m[6:12, 3:4] .= true
    m[6:9, 10:12] .= true
    @test AN.sprout_length(m; from = 5) == 7
    w = AN.width_profile(m)
    @test w[1:5] == fill(16.0, 5) && w[6:9] == fill(2.5, 4) && w[10:12] == fill(2.0, 3)
    @test all(isnan, w[13:20])
    @test AN.sprout_thickness(m; slices = 6:20) ≈ (4 * 2.5 + 3 * 2) / 7
    # along axis 2 the same mask transposed gives the same answers
    @test AN.sprout_length(permutedims(m); axis = 2, from = 5) == 7
    @test isequal(AN.width_profile(permutedims(m); axis = 2), w)
    # negative controls: no site past the base, and an empty mask
    @test AN.sprout_length(m[1:5, :]; from = 5) == 0
    @test AN.sprout_length(falses(4, 4)) == 0
    @test isnan(AN.sprout_thickness(falses(4, 4)))
    @test_throws ArgumentError AN.width_profile(m; axis = 3)
end

@testitem "Analysis: lineage trees" setup = [AnalysisSetup] tags = [
    :pottsmodels, :core,
] begin
    # two founders; 1 → 3, 4; 3 → 5 → 7; 2 → 6
    rec = [1 => nothing, 2 => nothing, 3 => 1, 4 => 1, 5 => 3, 6 => 2, 7 => 5]
    lin = AN.lineage(rec)
    @test lin.roots == [1, 2]
    @test [lin.founder[c] for c in 1:7] == [1, 2, 1, 1, 1, 2, 1]
    @test [lin.depth[c] for c in 1:7] == [0, 0, 1, 1, 2, 1, 3]
    @test lin.children[1] == [3, 4] && isempty(lin.children[7])
    @test AN.clone_sizes(lin, [4, 6, 7]) == Dict(1 => 2, 2 => 1)
    # the record order does not change the tree
    lin2 = AN.lineage(reverse(rec))
    @test lin2.founder == lin.founder && lin2.depth == lin.depth
    # a parent that never appears as a child is a root without a founder record
    @test AN.lineage([5 => 9]).roots == [9]
    # labels need not be integers: (mcs, id) pairs for reused cell numbers
    t = AN.lineage([(0, 1) => nothing, (10, 2) => (0, 1), (20, 1) => (10, 2)])
    @test t.depth[(20, 1)] == 2 && t.founder[(20, 1)] == (0, 1)
    # a repeated identical record is fine; negative controls: two parents, a cycle, an
    # unknown cell
    @test AN.lineage([3 => 1, 3 => 1]).depth[3] == 1
    @test_throws ArgumentError AN.lineage([3 => 1, 3 => 2])
    @test_throws ArgumentError AN.lineage([1 => 2, 2 => 3, 3 => 1])
    @test_throws ArgumentError AN.clone_sizes(lin, [8])
end
